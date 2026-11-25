import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:url_launcher/url_launcher.dart';

import '../config/google_oauth_config.dart';
import 'google_android_auth.dart';
import 'google_auth_exception.dart';
import 'google_token_vault.dart';

export 'google_auth_exception.dart';

/// Jeton d'accès en mémoire ; le jeton de rafraîchissement (ordinateur
/// uniquement) reste dans le coffre du système.
class GoogleSession {
  GoogleSession({
    required this.accessToken,
    required this.expiresAt,
    this.email = '',
    this.accountId = '',
  });

  final String accessToken;
  final DateTime expiresAt;
  final String email;
  final String accountId;

  bool get expired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));
}

/// Connexion Google et sauvegarde chiffrée dans l'espace applicatif de Drive.
///
/// - **Android** : `google_sign_in` (Play services). La boucle locale est
///   dépréciée par Google pour les applications mobiles et répond souvent
///   « 400 invalid_request » ; aucun navigateur ni `client_secret` n'est alors
///   utilisé.
/// - **Ordinateur** : flux **code + PKCE** avec redirection sur la boucle
///   locale, sans secret embarqué dans l'application.
/// - Aucune lecture du Drive de la personne : uniquement `appDataFolder`, qui
///   contient les sauvegardes AKIBA et disparaît avec l'application.
/// - L'enveloppe déposée est **déjà chiffrée AES-256-GCM** : Google ne voit
///   que du chiffré, la phrase secrète ne quitte jamais l'appareil.
/// - Hors ligne ou sans identifiants, l'application reste pleinement utilisable.
class GoogleDriveService {
  GoogleDriveService({
    GoogleTokenVault? vault,
    GoogleAndroidAuth? androidAuth,
    bool? android,
  }) : _vault = vault ?? const SecureGoogleTokenVault(),
       _androidAuth = androidAuth ?? GoogleSignInAndroidAuth(),
       // Injectable : les tests vérifient les deux branches sans appareil.
       _android = android ?? Platform.isAndroid;

  final GoogleTokenVault _vault;
  final GoogleAndroidAuth _androidAuth;
  final bool _android;

  /// Jeton durable du flux ordinateur. Son absence signifie « session
  /// Android » : Play services renouvelle le jeton lui-même, aucun mode de
  /// connexion n'a donc besoin d'être mémorisé séparément.
  static const String _refreshKey = 'akiba_google_refresh_token';
  static const String _emailKey = 'akiba_google_email';
  static const String _accountIdKey = 'akiba_google_account_id';

  /// `google_sign_in` ne publie pas de date d'expiration : Google accorde une
  /// heure environ, marge de sécurité déduite.
  static const Duration _androidTokenLife = Duration(minutes: 50);

  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const String _driveEndpoint = 'https://www.googleapis.com/drive/v3';
  static const String _uploadEndpoint =
      'https://www.googleapis.com/upload/drive/v3/files';

  GoogleSession? _session;

  /// Adresse du compte lié, ou `null` si aucune connexion n'est enregistrée.
  Future<String?> linkedEmail() async {
    try {
      final String? email = await _vault.read(_emailKey);
      return (email == null || email.isEmpty) ? null : email;
    } catch (_) {
      return null;
    }
  }

  Future<bool> get isLinked async => (await linkedEmail()) != null;

  /// Identifiant Google stable (claim `sub`), uniquement en mémoire dans les
  /// enveloppes; il sert à dériver la clé et n'est jamais ajouté au backup.
  Future<String> currentAccountId() async => (await _activeSession()).accountId;

  /// Connecte le compte Google : `google_sign_in` sur Android, navigateur +
  /// boucle locale ailleurs. Lève [GoogleAuthException] si la connexion échoue.
  Future<GoogleSession> signIn() async {
    // La configuration arrive normalement de `main` : on ne relit le disque
    // que si rien n'est encore chargé (écran monté seul, test).
    if (GoogleOAuthConfig.clientId.isEmpty &&
        GoogleOAuthConfig.androidServerClientId.isEmpty) {
      await GoogleOAuthConfig.load();
    }
    if (_android) return _signInAndroid();
    if (!GoogleOAuthConfig.isConfigured) {
      throw GoogleAuthException(
        'Aucun identifiant OAuth exploitable. ${GoogleOAuthConfig.setupHint}',
      );
    }

    final String verifier = _randomVerifier();
    final String challenge = _challenge(verifier);
    final String state = _randomVerifier();
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final String redirect = GoogleOAuthConfig.redirectUri(server.port);

    final Uri authorization = GoogleOAuthConfig.authorizationUri(
      port: server.port,
      codeChallenge: challenge,
      state: state,
    );

    final Completer<Uri> callback = Completer<Uri>();
    final StreamSubscription<HttpRequest> subscription = server.listen((
      HttpRequest request,
    ) async {
      if (request.uri.path != '/') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><meta charset="utf-8">'
        '<title>AKIBA</title>'
        '<body style="font-family:sans-serif;padding:40px">'
        '<h2>Connexion Google terminée</h2>'
        '<p>Vous pouvez revenir à AKIBA et fermer cet onglet.</p>',
      );
      await request.response.close();
      if (!callback.isCompleted) callback.complete(request.uri);
    });

    try {
      final bool opened = await launchUrl(
        authorization,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw const GoogleAuthException(
          'Impossible d’ouvrir le navigateur pour la connexion Google.',
        );
      }
      final Uri result = await callback.future.timeout(
        GoogleOAuthConfig.signInTimeout,
        onTimeout: () => throw const GoogleAuthException(
          'Connexion Google expirée sans retour du navigateur. Si la page '
          'affichait « 400 invalid_request », utilisez un client OAuth de type '
          '« Application de bureau » ; sinon réessayez depuis le centre de '
          'sauvegarde. Le dossier Drive synchronisé reste disponible.',
        ),
      );

      final String? error = result.queryParameters['error'];
      if (error != null) {
        throw GoogleAuthException(_explain(error));
      }
      if (result.queryParameters['state'] != state) {
        throw const GoogleAuthException(
          'Réponse OAuth invalide : recommencez la connexion Google.',
        );
      }
      final String? code = result.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw const GoogleAuthException('Réponse Google incomplète.');
      }

      final Map<String, dynamic> tokens =
          await _postForm(_tokenEndpoint, <String, String>{
            'client_id': GoogleOAuthConfig.clientId,
            'code': code,
            'code_verifier': verifier,
            'grant_type': 'authorization_code',
            'redirect_uri': redirect,
            if (GoogleOAuthConfig.clientSecret.isNotEmpty)
              'client_secret': GoogleOAuthConfig.clientSecret,
          });
      return _remember(tokens);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  /// Connexion Android native : Play services rend un jeton Drive, et c'est
  /// Play services qui le renouvellera silencieusement plus tard.
  Future<GoogleSession> _signInAndroid() async {
    if (!GoogleOAuthConfig.isAndroidReady) {
      throw GoogleAuthException(
        'Connexion Google Android non configurée. '
        '${GoogleOAuthConfig.androidHint}',
      );
    }
    return _rememberAndroid(await _androidAuth.connect());
  }

  /// Traduit les refus de Google en actions concrètes, sans jargon inutile.
  ///
  /// « Accès rejeté » vient presque toujours de l'écran de consentement
  /// (compte absent des testeurs), d'un mauvais type de client OAuth ou d'une
  /// portée non déclarée — jamais du code de l'application.
  String _explain(String error) {
    switch (error) {
      case 'access_denied':
        return 'Google a refusé l’accès. Vérifiez que ce compte figure bien '
            'dans les « utilisateurs test » de l’écran de consentement OAuth '
            '(Google Cloud Console → API et services → Écran de consentement), '
            'ou publiez l’application. Le type de client doit être '
            '« Application de bureau ».';
      case 'redirect_uri_mismatch':
        return 'L’adresse de retour n’est pas autorisée pour ce client OAuth. '
            'Créez un client de type « Application de bureau » et utilisez son '
            'identifiant : les URI de boucle locale sont alors acceptées '
            'automatiquement.';
      case 'invalid_client':
        return 'Identifiant OAuth refusé. Vérifiez que '
            'secrets/google_oauth.json contient bien le client de type '
            '« Application de bureau », puis relancez '
            '« dart run tool/sync_oauth_secrets.dart ». Le dossier Drive '
            'synchronisé reste utilisable en attendant.';
      case 'admin_policy_enforced':
        return 'Votre organisation Google interdit cette application. '
            'Utilisez un compte personnel ou faites autoriser l’application '
            'par l’administrateur.';
      case 'invalid_request':
        // Android ne passe plus par ici (`google_sign_in` le remplace) : cette
        // réponse ne vient donc que du flux de bureau.
        return 'Google a refusé la requête (400 invalid_request). Causes '
            'usuelles : identifiant vide ou copié avec un espace, client OAuth '
            'de type « Application Web » au lieu de « Application de bureau », '
            'ou portée drive.appdata non déclarée. Vérifiez '
            '${GoogleOAuthConfig.devFilePath} : la copie embarquée est '
            'réécrite à la prochaine build Android. Le dossier Drive '
            'synchronisé reste utilisable en attendant.';
      case 'unauthorized_client':
        return 'Ce client OAuth n’est pas autorisé à utiliser le flux des '
            'applications installées. Créez un client « Application de bureau » '
            'et utilisez son identifiant.';
      case 'invalid_scope':
        return 'La portée demandée est refusée. Activez l’API Google Drive et '
            'la portée drive.appdata sur l’écran de consentement.';
      case 'disallowed_useragent':
        return 'Google refuse les navigateurs intégrés. Choisissez un '
            'navigateur externe (Chrome, Firefox, Safari) pour vous connecter.';
      default:
        return 'Google a refusé la connexion ($error). Vérifiez l’écran de '
            'consentement OAuth et la portée drive.appdata.';
    }
  }

  /// Oublie la connexion : les jetons sont effacés du coffre et, sur Android,
  /// l'autorisation accordée à AKIBA est révoquée.
  Future<void> signOut() async {
    _session = null;
    try {
      await _vault.delete(_refreshKey);
      await _vault.delete(_emailKey);
      await _vault.delete(_accountIdKey);
    } catch (_) {
      // Coffre indisponible : la session en mémoire est déjà oubliée.
    }
    if (_android) await _androidAuth.disconnect();
  }

  /// Dépose l'enveloppe chiffrée et ne garde que les cinq plus récentes.
  Future<DateTime> upload(Map<String, dynamic> envelope) async {
    final GoogleSession session = await _activeSession();
    final DateTime now = DateTime.now();
    final String name =
        'akiba-${now.year}${_two(now.month)}${_two(now.day)}-'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}.akiba';

    final String boundary = 'akiba-${now.microsecondsSinceEpoch}';
    final String metadata = jsonEncode(<String, Object?>{
      'name': name,
      'parents': <String>['appDataFolder'],
    });
    final String body =
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json\r\n\r\n'
        '${jsonEncode(envelope)}\r\n'
        '--$boundary--\r\n';
    final List<int> bytes = utf8.encode(body);

    final Uri uri = Uri.parse(_uploadEndpoint).replace(
      queryParameters: <String, String>{
        'uploadType': 'multipart',
        'fields': 'id,name',
      },
    );
    final HttpClient client = _client();
    try {
      final HttpClientRequest request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.headers.set('Authorization', 'Bearer ${session.accessToken}');
      request.headers.contentType = ContentType(
        'multipart',
        'related',
        parameters: <String, String>{'boundary': boundary},
      );
      request.contentLength = bytes.length;
      request.add(bytes);
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final String text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleAuthException(_driveError(response.statusCode, text));
      }
    } on GoogleAuthException {
      rethrow;
    } on SocketException {
      throw const GoogleAuthException(
        'Google Drive injoignable : vérifiez la connexion internet.',
      );
    } on TimeoutException {
      throw const GoogleAuthException('Google Drive n’a pas répondu à temps.');
    } finally {
      client.close(force: true);
    }

    await _prune(session);
    return now.toUtc();
  }

  /// Relit la sauvegarde la plus récente, ou `null` s'il n'y en a aucune.
  Future<Map<String, dynamic>?> download() async {
    final GoogleSession session = await _activeSession();
    final String? id = await _latestFileId(session);
    if (id == null) return null;

    final HttpClient client = _client();
    try {
      final HttpClientRequest request = await client
          .getUrl(
            Uri.parse(
              '$_driveEndpoint/files/$id',
            ).replace(queryParameters: <String, String>{'alt': 'media'}),
          )
          .timeout(const Duration(seconds: 15));
      request.headers.set('Authorization', 'Bearer ${session.accessToken}');
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final String text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 404) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleAuthException(_driveError(response.statusCode, text));
      }
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const GoogleAuthException('Sauvegarde Drive illisible.');
      }
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const GoogleAuthException('Sauvegarde Drive illisible.');
    } on SocketException {
      throw const GoogleAuthException(
        'Google Drive injoignable : vérifiez la connexion internet.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Date de la sauvegarde Drive la plus récente, sans télécharger le contenu.
  Future<DateTime?> latestStamp() async {
    final GoogleSession session = await _activeSession();
    final List<Map<String, dynamic>> files = await _listFiles(session);
    if (files.isEmpty) return null;
    return DateTime.tryParse('${files.first['createdTime'] ?? ''}');
  }

  // -------------------------------------------------------------- Interne

  HttpClient _client() =>
      HttpClient()..connectionTimeout = const Duration(seconds: 15);

  Future<GoogleSession> _activeSession() async {
    final GoogleSession? cached = _session;
    if (cached != null && !cached.expired) return cached;
    final GoogleSession refreshed = await _refresh();
    _session = refreshed;
    return refreshed;
  }

  Future<GoogleSession> _refresh() async {
    String? refreshToken;
    String email = '';
    try {
      refreshToken = await _vault.read(_refreshKey);
      email = await _vault.read(_emailKey) ?? '';
    } catch (_) {
      throw const GoogleAuthException(
        'Le coffre du système est indisponible : reconnectez-vous à Google.',
      );
    }

    // Pas de jeton durable : session Android, renouvelée silencieusement par
    // Play services (aucun navigateur, rien à écrire sur disque).
    if (refreshToken == null || refreshToken.isEmpty) {
      if (!_android) {
        throw const GoogleAuthException(
          'Connectez d’abord votre compte Google dans le centre de sauvegarde.',
        );
      }
      final GoogleAndroidToken? token = await _androidAuth.restore();
      if (token == null) {
        throw const GoogleAuthException(
          'Session Google expirée : reconnectez-vous depuis le centre de '
          'sauvegarde. Le dossier Drive synchronisé reste utilisable.',
        );
      }
      final GoogleSession session = GoogleSession(
        accessToken: token.accessToken,
        expiresAt: DateTime.now().add(_androidTokenLife),
        email: token.email.isEmpty ? email : token.email,
        accountId: token.accountId,
      );
      _session = session;
      return session;
    }

    try {
      final Map<String, dynamic> tokens =
          await _postForm(_tokenEndpoint, <String, String>{
            'client_id': GoogleOAuthConfig.clientId,
            'refresh_token': refreshToken,
            'grant_type': 'refresh_token',
            if (GoogleOAuthConfig.clientSecret.isNotEmpty)
              'client_secret': GoogleOAuthConfig.clientSecret,
          });
      return GoogleSession(
        accessToken: '${tokens['access_token']}',
        expiresAt: _expiry(tokens),
        email: email,
        accountId: await _vault.read(_accountIdKey) ?? '',
      );
    } on GoogleAuthException {
      // Jeton révoqué : on oublie la connexion pour ne pas boucler.
      await signOut();
      rethrow;
    }
  }

  /// Session Android : ni navigateur, ni jeton de rafraîchissement à écrire.
  Future<GoogleSession> _rememberAndroid(GoogleAndroidToken token) async {
    if (token.accessToken.isEmpty) {
      throw const GoogleAuthException(
        'Google n’a pas renvoyé de jeton Drive : réessayez la connexion.',
      );
    }
    try {
      if (token.email.isNotEmpty) {
        await _vault.write(_emailKey, token.email);
      }
      if (token.accountId.isNotEmpty) {
        await _vault.write(_accountIdKey, token.accountId);
      }
    } catch (_) {
      throw const GoogleAuthException(
        'La session Google n’a pas pu être protégée sur cet appareil.',
      );
    }
    final GoogleSession session = GoogleSession(
      accessToken: token.accessToken,
      expiresAt: DateTime.now().add(_androidTokenLife),
      email: token.email,
      accountId: token.accountId,
    );
    _session = session;
    return session;
  }

  Future<GoogleSession> _remember(Map<String, dynamic> tokens) async {
    final String access = '${tokens['access_token'] ?? ''}';
    final String refresh = '${tokens['refresh_token'] ?? ''}';
    if (access.isEmpty || refresh.isEmpty) {
      throw const GoogleAuthException(
        'Google n’a pas renvoyé de jeton durable : réessayez la connexion.',
      );
    }
    final String email = _emailFrom(tokens['id_token']);
    final String accountId = _accountIdFrom(tokens['id_token']);
    if (email.isNotEmpty) {
      try {
        await _vault.write(_emailKey, email);
        if (accountId.isNotEmpty) await _vault.write(_accountIdKey, accountId);
      } catch (_) {
        // L'adresse n'est qu'un libellé : son absence ne bloque pas la synchro.
      }
    }
    final GoogleSession session = GoogleSession(
      accessToken: access,
      expiresAt: _expiry(tokens),
      email: email,
      accountId: accountId,
    );
    try {
      await _vault.write(_refreshKey, refresh);
    } catch (_) {
      throw const GoogleAuthException(
        'Le jeton Google n’a pas pu être protégé sur cet appareil.',
      );
    }
    _session = session;
    return session;
  }

  DateTime _expiry(Map<String, dynamic> tokens) {
    final int seconds = (tokens['expires_in'] as num?)?.toInt() ?? 3600;
    return DateTime.now().add(Duration(seconds: seconds));
  }

  static String _emailFrom(Object? idToken) {
    if (idToken is! String) return '';
    final List<String> parts = idToken.split('.');
    if (parts.length < 2) return '';
    try {
      final String padded = parts[1].padRight(
        (parts[1].length + 3) ~/ 4 * 4,
        '=',
      );
      final Object? decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (decoded is Map && decoded['email'] is String) {
        return decoded['email'] as String;
      }
    } catch (_) {
      // Un id_token illisible n'empêche pas la sauvegarde.
    }
    return '';
  }

  static String _accountIdFrom(Object? idToken) {
    if (idToken is! String) return '';
    final List<String> parts = idToken.split('.');
    if (parts.length < 2) return '';
    try {
      final String padded = parts[1].padRight(
        (parts[1].length + 3) ~/ 4 * 4,
        '=',
      );
      final Object? decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (decoded is Map && decoded['sub'] is String) {
        return decoded['sub'] as String;
      }
    } catch (_) {
      // Un jeton illisible ne révèle jamais sa charge utile aux journaux.
    }
    return '';
  }

  Future<Map<String, dynamic>> _postForm(
    String url,
    Map<String, String> body,
  ) async {
    final HttpClient client = _client();
    try {
      final HttpClientRequest request = await client
          .postUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(Uri(queryParameters: body).query);
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final String text = await response.transform(utf8.decoder).join();
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
      if (response.statusCode != 200) {
        final Object? error = decoded is Map ? decoded['error'] : null;
        throw GoogleAuthException(
          error == 'invalid_grant'
              ? 'Autorisation Google expirée ou révoquée : reconnectez-vous.'
              : 'Google a refusé la demande (HTTP ${response.statusCode}).',
        );
      }
      if (decoded is! Map) {
        throw const GoogleAuthException('Réponse Google illisible.');
      }
      return Map<String, dynamic>.from(decoded);
    } on GoogleAuthException {
      rethrow;
    } on SocketException {
      throw const GoogleAuthException(
        'Connexion Google impossible sans internet.',
      );
    } on TimeoutException {
      throw const GoogleAuthException('Google n’a pas répondu à temps.');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Map<String, dynamic>>> _listFiles(GoogleSession session) async {
    final HttpClient client = _client();
    try {
      final Uri uri = Uri.parse('$_driveEndpoint/files').replace(
        queryParameters: <String, String>{
          'spaces': 'appDataFolder',
          'orderBy': 'createdTime desc',
          'pageSize': '20',
          'fields': 'files(id,name,createdTime)',
          'q': "name contains '.akiba' and trashed = false",
        },
      );
      final HttpClientRequest request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.headers.set('Authorization', 'Bearer ${session.accessToken}');
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final String text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleAuthException(_driveError(response.statusCode, text));
      }
      final Object? decoded = jsonDecode(text);
      final Object? files = decoded is Map ? decoded['files'] : null;
      if (files is! List) return const <Map<String, dynamic>>[];
      return <Map<String, dynamic>>[
        for (final Object? file in files)
          if (file is Map) Map<String, dynamic>.from(file),
      ];
    } on GoogleAuthException {
      rethrow;
    } on SocketException {
      throw const GoogleAuthException(
        'Google Drive injoignable : vérifiez la connexion internet.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _latestFileId(GoogleSession session) async {
    final List<Map<String, dynamic>> files = await _listFiles(session);
    if (files.isEmpty) return null;
    final Object? id = files.first['id'];
    return id is String ? id : null;
  }

  /// Ne conserve que [GoogleOAuthConfig.keepBackups] fichiers.
  Future<void> _prune(GoogleSession session) async {
    final List<Map<String, dynamic>> files = await _listFiles(session);
    if (files.length <= GoogleOAuthConfig.keepBackups) return;
    final HttpClient client = _client();
    try {
      for (final Map<String, dynamic> file in files.skip(
        GoogleOAuthConfig.keepBackups,
      )) {
        final Object? id = file['id'];
        if (id is! String) continue;
        final HttpClientRequest request = await client.deleteUrl(
          Uri.parse('$_driveEndpoint/files/$id'),
        );
        request.headers.set('Authorization', 'Bearer ${session.accessToken}');
        final HttpClientResponse response = await request.close();
        await response.drain<void>();
      }
    } catch (_) {
      // Le ménage est un confort : une sauvegarde réussie ne doit pas échouer.
    } finally {
      client.close(force: true);
    }
  }

  static String _driveError(int status, String body) {
    if (status == 401) {
      return 'Autorisation Google expirée : reconnectez-vous.';
    }
    if (status == 403) {
      return 'Google refuse l’accès (quota ou autorisation) : réessayez plus '
          'tard ou reconnectez-vous.';
    }
    if (status == 404) {
      return 'Sauvegarde Drive introuvable.';
    }
    if (status >= 500) {
      return 'Google Drive est momentanément indisponible.';
    }
    return 'Google Drive a refusé la demande (HTTP $status).';
  }

  static String _randomVerifier() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _challenge(String verifier) => base64Url
      .encode(hash.sha256.convert(utf8.encode(verifier)).bytes)
      .replaceAll('=', '');

  static String _two(int value) => value.toString().padLeft(2, '0');
}
