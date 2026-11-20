/// Identifiants OAuth Google — **seul fichier à modifier** pour brancher
/// « Se connecter avec Google ».
///
/// 1. Google Cloud Console → APIs et services → Identifiants.
/// 2. Créer un identifiant OAuth de type **Application de bureau**.
/// 3. Activer l'API Google Drive.
/// 4. Enregistrer le JSON téléchargé dans `secrets/` (ignoré par Git) et
///    fournir l'identifiant à la compilation, sans jamais l'écrire dans le
///    code suivi :
///
///    ```
///    flutter run --dart-define-from-file=secrets/google_oauth.json
///    ```
///
///    `secrets/google_oauth.json` contient
///    `{"AKIBA_GOOGLE_CLIENT_ID": "…apps.googleusercontent.com",
///    "AKIBA_GOOGLE_CLIENT_SECRET": ""}`. Le client de bureau AKIBA
///    (`954317884015-…`) n'a **pas** de secret : la chaîne vide est normale.
///
/// Les URI de redirection à déclarer côté Google sont les adresses de boucle
/// locale `http://127.0.0.1:<port>/oauth2callback` : un client de type
/// « Application de bureau » accepte n'importe quel port local.
///
/// Sans identifiants, AKIBA reste **100 % hors ligne** : le centre de
/// sauvegarde propose alors le dossier Google Drive synchronisé de l'appareil.
/// Aucun jeton n'est jamais écrit dans ce fichier ni dans la base : seul le
/// jeton de rafraîchissement est conservé, dans le coffre du système.
abstract final class GoogleOAuthConfig {
  /// Repli laissé vide à dessein : l'identifiant arrive par
  /// `--dart-define-from-file` et n'est donc jamais versionné.
  static const String clientIdPlaceholder = '';

  /// Secret facultatif : les clients de bureau récents n'en ont pas besoin
  /// (le client AKIBA n'en a pas). Même règle, jamais versionné.
  static const String clientSecretPlaceholder = '';

  static const String _clientIdDefine = String.fromEnvironment(
    'AKIBA_GOOGLE_CLIENT_ID',
  );
  static const String _clientSecretDefine = String.fromEnvironment(
    'AKIBA_GOOGLE_CLIENT_SECRET',
  );

  static String get clientId =>
      _clientIdDefine.isNotEmpty ? _clientIdDefine : clientIdPlaceholder;

  static String get clientSecret => _clientSecretDefine.isNotEmpty
      ? _clientSecretDefine
      : clientSecretPlaceholder;

  /// Vrai si un identifiant exploitable est présent.
  static bool get isConfigured =>
      clientId.trim().endsWith('.apps.googleusercontent.com');

  /// Espace `appDataFolder` : fichiers invisibles dans « Mon Drive » et
  /// supprimés avec l'application. Rien d'autre n'est lisible.
  static const List<String> scopes = <String>[
    'openid',
    'email',
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  static const String redirectPath = '/oauth2callback';

  static String redirectUri(int port) => 'http://127.0.0.1:$port$redirectPath';

  /// Délai accordé à la personne pour terminer la connexion dans le navigateur.
  static const Duration signInTimeout = Duration(minutes: 3);

  /// Nom des sauvegardes déposées sur Drive.
  static const String backupFileName = 'akiba-backup.akiba';

  /// Conservation des cinq dernières sauvegardes Drive.
  static const int keepBackups = 5;
}
