import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Identifiants OAuth Google — **seul fichier de code à connaître**.
///
/// Google Cloud Console → APIs et services → Identifiants :
/// - client **Application de bureau** (ordinateur) → `clientId` ;
/// - client **Android** (package `com.akiba.app` + empreinte SHA-1) ;
/// - client **Application Web** → `androidServerClientId`, seul identifiant
///   transmis à `google_sign_in` (aucun secret).
///
/// Puis `secrets/google_oauth.json` (ignoré par Git) :
///
/// ```json
/// {
///   "AKIBA_GOOGLE_CLIENT_ID": "…apps.googleusercontent.com",
///   "AKIBA_GOOGLE_CLIENT_SECRET": "",
///   "AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID": "…apps.googleusercontent.com"
/// }
/// ```
///
/// **Aucune commande à retaper** : la tâche Gradle `syncOAuthSecrets` copie
/// `secrets/google_oauth.json` vers `assets/config/google_oauth.json` (ignoré
/// par Git, embarqué dans l'APK) avant chaque build Android. Ce fichier ne fait
/// que **lire** : il n'écrit jamais sur le disque.
///
/// Ordre de résolution (le premier non vide gagne) : `--dart-define`, puis
/// `secrets/google_oauth.json` (ordinateur), puis la copie embarquée (seule
/// voie sur Android/iOS). Aucun jeton n'est écrit dans ces fichiers : le jeton
/// d'accès reste en mémoire, le jeton de rafraîchissement dans le coffre
/// système.
abstract final class GoogleOAuthConfig {
  static const String clientIdKey = 'AKIBA_GOOGLE_CLIENT_ID';
  static const String clientSecretKey = 'AKIBA_GOOGLE_CLIENT_SECRET';
  static const String androidServerKey =
      'AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID';

  /// Copie embarquée, écrite par la tâche Gradle depuis [devFilePath].
  static const String assetPath = 'assets/config/google_oauth.json';

  /// Fichier de développement, lu seulement quand il existe.
  static const String devFilePath = 'secrets/google_oauth.json';

  static const String _suffix = '.apps.googleusercontent.com';

  /// Marche à suivre affichée quand aucun identifiant n'est trouvé.
  static const String setupHint =
      'Placez l’identifiant dans $devFilePath : la tâche Gradle '
      '`syncOAuthSecrets` le copie dans $assetPath avant chaque build Android. '
      'En attendant, la sauvegarde fonctionne dans le dossier Google Drive '
      'synchronisé de l’appareil, sans connexion.';

  /// Marche à suivre spécifique à `google_sign_in` (Android).
  static const String androidHint =
      'Connexion Android : créez un client OAuth « Android » (package '
      'com.akiba.app + empreinte SHA-1 de la clé de signature) et un client '
      '« Application Web », puis renseignez $androidServerKey dans '
      '$devFilePath.';

  static const String _idDefine = String.fromEnvironment(
    'AKIBA_GOOGLE_CLIENT_ID',
  );
  static const String _secretDefine = String.fromEnvironment(
    'AKIBA_GOOGLE_CLIENT_SECRET',
  );
  static const String _serverDefine = String.fromEnvironment(
    'AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID',
  );

  static String _fileClientId = '';
  static String _fileSecret = '';
  static String _fileServer = '';

  /// L'identifiant est nettoyé : un espace copié depuis la console Google
  /// suffit à déclencher un `invalid_request` côté Google.
  static String get clientId =>
      _firstNonEmpty(<String>[_idDefine, _fileClientId]);

  static String get clientSecret =>
      _firstNonEmpty(<String>[_secretDefine, _fileSecret]);

  /// Identifiant du client « Application Web » utilisé par `google_sign_in`.
  static String get androidServerClientId =>
      _firstNonEmpty(<String>[_serverDefine, _fileServer]);

  /// Vrai si le flux de bureau (boucle locale + PKCE) est configurable.
  static bool get isConfigured => clientId.endsWith(_suffix);

  /// Vrai si la connexion Android native (`google_sign_in`) est configurable.
  static bool get isAndroidReady => androidServerClientId.endsWith(_suffix);

  /// Vrai si la voie de connexion de **cette** plateforme est configurée :
  /// `google_sign_in` sur Android, flux de bureau ailleurs. Un client de
  /// bureau ne sert à rien sur Android, et inversement.
  static bool get canSignIn =>
      Platform.isAndroid ? isAndroidReady : isConfigured;

  /// Charge les identifiants : `--dart-define`, puis [devPath] ou
  /// [devFilePath], puis la copie embarquée.
  ///
  /// Ne lève jamais : toute erreur de lecture laisse simplement AKIBA sans
  /// connexion Google, avec le repli du dossier synchronisé. Lecture seule :
  /// seule la tâche Gradle `syncOAuthSecrets` écrit la copie embarquée.
  static Future<void> load({String? devPath}) async {
    final Map<String, dynamic>? source =
        await _readFile(devPath ?? devFilePath) ?? await _readAsset();
    _fileClientId = _text(source?[clientIdKey]);
    _fileSecret = _text(source?[clientSecretKey]);
    _fileServer = _text(source?[androidServerKey]);
  }

  /// Portée Drive demandée à `google_sign_in` (espace applicatif uniquement).
  static const List<String> driveScopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  /// Portée du flux de bureau : identité pour l'adresse + Drive applicatif.
  static const List<String> scopes = <String>[
    'openid',
    'email',
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  static const String authorizationEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';

  /// Redirection de boucle locale, forme documentée par Google pour les
  /// applications installées : `http://127.0.0.1:<port>`, sans chemin. Le port
  /// est choisi à l'exécution puis réutilisé à l'identique pour l'échange du
  /// code.
  static String redirectUri(int port) =>
      Uri(scheme: 'http', host: '127.0.0.1', port: port).toString();

  /// Requête d'autorisation du flux installé (ordinateur uniquement : Android
  /// passe par `google_sign_in`).
  ///
  /// `access_type=offline` et `prompt=consent` sont requis : sans eux, une
  /// deuxième connexion ne renvoie aucun jeton de rafraîchissement.
  /// `include_granted_scopes` reste absent (non pris en charge par ce flux).
  /// La chaîne est encodée avec [Uri.encodeComponent] : les espaces du `scope`
  /// partent en `%20`, jamais en `+` (forme ambiguë refusée par Google).
  static Uri authorizationUri({
    required int port,
    required String codeChallenge,
    required String state,
  }) {
    final Map<String, String> parameters = <String, String>{
      'client_id': clientId,
      'redirect_uri': redirectUri(port),
      'response_type': 'code',
      'scope': scopes.join(' '),
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': state,
      'access_type': 'offline',
      'prompt': 'consent',
    };
    // Un identifiant vide n'est jamais émis : `client_id=` déclenche
    // « invalid_request » chez Google.
    final String query = parameters.entries
        .where((MapEntry<String, String> entry) => entry.value.isNotEmpty)
        .map(
          (MapEntry<String, String> entry) =>
              '${entry.key}=${Uri.encodeComponent(entry.value)}',
        )
        .join('&');
    return Uri.parse('$authorizationEndpoint?$query');
  }

  /// Délai accordé à la personne pour terminer la connexion dans le navigateur.
  static const Duration signInTimeout = Duration(minutes: 3);

  /// Conservation des cinq dernières sauvegardes Drive.
  static const int keepBackups = 5;

  // -------------------------------------------------------------- Interne

  static String _firstNonEmpty(List<String> values) {
    for (final String value in values) {
      final String trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  static Future<Map<String, dynamic>?> _readAsset() async {
    try {
      return _decode(await rootBundle.loadString(assetPath));
    } catch (_) {
      // Copie absente (clone sans secrets) : AKIBA reste hors ligne.
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _readFile(String path) async {
    try {
      final File file = File(path);
      if (!await file.exists()) return null;
      return _decode(await file.readAsString());
    } catch (_) {
      // Android/iOS : pas de dossier `secrets/`, on passe à la copie embarquée.
      return null;
    }
  }

  static Map<String, dynamic>? _decode(String text) {
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // JSON illisible : aucune connexion Google, jamais d'écran bloqué.
    }
    return null;
  }
}
