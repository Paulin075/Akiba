import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/google_oauth_config.dart';

/// Erreur lisible de la connexion Google (jamais un jeton).
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Jetons OAuth en mémoire ; seul le jeton de rafraîchissement est conservé,
/// dans le coffre du système.
class GoogleSession {
  GoogleSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.email = '',
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String email;

  bool get expired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));
}

/// Connexion Google et sauvegarde chiffrée dans l'espace applicatif de Drive.
///
/// - Flux **code + PKCE** avec redirection sur la boucle locale, sans secret
///   embarqué dans l'application.
/// - Aucune lecture du Drive de la personne : uniquement `appDataFolder`, qui
///   contient les sauvegardes AKIBA et disparaît avec l'application.
/// - L'enveloppe déposée est **déjà chiffrée AES-256-GCM** : Google ne voit
///   que du chiffré, la phrase secrète ne quitte jamais l'appareil.
/// - Hors ligne ou sans identifiants, l'application reste pleinement utilisable.
class GoogleDriveService {
  GoogleDriveService({this.storage = const FlutterSecureStorage()});

  final FlutterSecureStorage storage;

  static const String _refreshKey = 'akiba_google_refresh_token';
  static const String _emailKey = 'akiba_google_email';

  static const String _authEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const String _driveEndpoint = 'https://www.googleapis.com/drive/v3';
  static const String _uploadEndpoint =
      'https://www.googleapis.com/upload/drive/v3/files';

  GoogleSession? _session;

  /// Adresse du compte lié, ou `null` si aucune connexion n'est enregistrée.
  Future<String?> linkedEmail() async {
    try {
      final String? email = await storage.read(key: _emailKey);
      return (email == null || email.isEmpty) ? null : email;
    } catch (_) {
      return null;
    }
  }

  Future<bool> get isLinked async => (await linkedEmail()) != null;

  /// Ouvre le navigateur, attend le retour de Google et enregistre le jeton de
  /// rafraîchissement. Lève [GoogleAuthException] si le flux échoue.
  Future<GoogleSession> signIn() async {
    if (!GoogleOAuthConfig.isConfigured) {
      throw const GoogleAuthException(
        'Ajoutez d’abord votre identifiant OAuth dans '
        'lib/core/config/google_oauth_config.dart.',
      );
    }

    final String verifier = _randomVerifier();
    final String challenge = _challenge(verifier);
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final String redirect = GoogleOAuthConfig.redirectUri(server.port);

    final Uri authorization = Uri.parse(_authEndpoint).replace(
      queryParameters: <String, String>{
        'client_id': GoogleOAuthConfig.clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': GoogleOAuthConfig.scopes.join(' '),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
        'include_granted_scopes': 'true',
      },
    );

    final Completer<Uri> callback = Completer<Uri>();
    final StreamSubscription<HttpRequest> subscription = server.listen((
      HttpRequest request,
    ) async {
      if (request.uri.path != GoogleOAuthConfig.redirectPath) {
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
          'Connexion Google expirée : réessayez depuis le centre de sauvegarde.',
        ),
      );

      final String? error = result.queryParameters['error'];
      if (error != null) {
        throw GoogleAuthException(_explain(error));
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
            '« Application de bureau » et relancez avec '
            '--dart-define-from-file.';
      case 'admin_policy_enforced':
        return 'Votre organisation Google interdit cette application. '
            'Utilisez un compte personnel ou faites autoriser l’application '
            'par l’administrateur.';
      default:
        return 'Google a refusé la connexion ($error). Vérifiez l’écran de '
            'consentement OAuth et la portée drive.appdata.';
    }
  }

  /// Oublie la connexion : le jeton de rafraîchissement est effacé du coffre.
  Future<void> signOut() async {
    _session = null;
    try {
      await storage.delete(key: _refreshKey);
      await storage.delete(key: _emailKey);
    } catch (_) {
      // Coffre indisponible : la session en mémoire est déjà oubliée.
    }
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
      refreshToken = await storage.read(key: _refreshKey);
      email = await storage.read(key: _emailKey) ?? '';
    } catch (_) {
      throw const GoogleAuthException(
        'Le coffre du système est indisponible : reconnectez-vous à Google.',
      );
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const GoogleAuthException(
        'Connectez d’abord votre compte Google dans le centre de sauvegarde.',
      );
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
        refreshToken: refreshToken,
        expiresAt: _expiry(tokens),
        email: email,
      );
    } on GoogleAuthException {
      // Jeton révoqué : on oublie la connexion pour ne pas boucler.
      await signOut();
      rethrow;
    }
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
    if (email.isNotEmpty) {
      try {
        await storage.write(key: _emailKey, value: email);
      } catch (_) {
        // L'adresse n'est qu'un libellé : son absence ne bloque pas la synchro.
      }
    }
    final GoogleSession session = GoogleSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: _expiry(tokens),
      email: email,
    );
    try {
      await storage.write(key: _refreshKey, value: refresh);
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
