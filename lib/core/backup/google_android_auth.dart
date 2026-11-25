import 'package:google_sign_in/google_sign_in.dart';

import '../config/google_oauth_config.dart';
import 'google_auth_exception.dart';

/// Jeton d'accès Drive obtenu auprès de Google Play services.
class GoogleAndroidToken {
  const GoogleAndroidToken({
    required this.accessToken,
    required this.email,
    this.accountId = '',
  });

  final String accessToken;
  final String email;
  final String accountId;
}

/// Contrat minimal de la connexion Android, pour tester la branche et le repli
/// sans appareil ni greffon.
abstract interface class GoogleAndroidAuth {
  /// Connexion interactive (l'écran Google s'ouvre).
  Future<GoogleAndroidToken> connect();

  /// Reconnexion silencieuse, `null` si aucune session utilisable.
  Future<GoogleAndroidToken?> restore();

  /// Révoque l'autorisation accordée à AKIBA.
  Future<void> disconnect();
}

/// Implémentation `google_sign_in` 7.x.
///
/// Android ne reçoit jamais de `client_secret` : l'identifiant transmis est le
/// client « Application Web » (`serverClientId`), et le client « Android »
/// (package `com.akiba.app` + empreinte SHA-1) est reconnu par Play services.
/// Le jeton d'accès vit une heure environ ; il n'est jamais écrit sur disque,
/// seul le compte lié est mémorisé par `GoogleDriveService`.
class GoogleSignInAndroidAuth implements GoogleAndroidAuth {
  static bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: GoogleOAuthConfig.androidServerClientId,
      );
      _initialized = true;
    } on GoogleSignInException catch (error) {
      throw GoogleAuthException(_explain(error));
    } catch (error) {
      throw GoogleAuthException(
        'Le service Google Play est indisponible sur cet appareil '
        '(${error.runtimeType}). Repli : dossier Google Drive synchronisé.',
      );
    }
  }

  @override
  Future<GoogleAndroidToken> connect() async {
    await _ensureInitialized();
    try {
      final GoogleSignInAccount account = await GoogleSignIn.instance
          .authenticate(scopeHint: GoogleOAuthConfig.driveScopes);
      return _token(account, interactive: true);
    } on GoogleSignInException catch (error) {
      throw GoogleAuthException(_explain(error));
    }
  }

  @override
  Future<GoogleAndroidToken?> restore() async {
    await _ensureInitialized();
    try {
      final GoogleSignInAccount? account = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (account == null) return null;
      return _token(account, interactive: false);
    } on GoogleSignInException {
      // Session révoquée ou compte retiré : un simple message, pas d'écran.
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      // Déjà déconnecté ou Play services absent : rien à faire.
    }
  }

  /// Le jeton Drive n'est demandé que par ce chemin : l'authentification seule
  /// ne donne aucun accès aux fichiers.
  Future<GoogleAndroidToken> _token(
    GoogleSignInAccount account, {
    required bool interactive,
  }) async {
    final GoogleSignInAuthorizationClient client = account.authorizationClient;
    GoogleSignInClientAuthorization? authorization;
    try {
      authorization = await client.authorizationForScopes(
        GoogleOAuthConfig.driveScopes,
      );
      if (authorization == null && interactive) {
        authorization = await client.authorizeScopes(
          GoogleOAuthConfig.driveScopes,
        );
      }
    } on GoogleSignInException catch (error) {
      throw GoogleAuthException(_explain(error));
    }
    if (authorization == null) {
      throw const GoogleAuthException(
        'Google n’a pas accordé l’accès à l’espace applicatif du Drive : '
        'reconnectez-vous et acceptez l’autorisation demandée. Le dossier '
        'Drive synchronisé reste utilisable en attendant.',
      );
    }
    return GoogleAndroidToken(
      accessToken: authorization.accessToken,
      email: account.email,
      accountId: account.id,
    );
  }

  /// Traduit les codes du greffon en actions concrètes (jamais de jeton).
  String _explain(GoogleSignInException error) {
    switch (error.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Connexion Google annulée. Le dossier Google Drive synchronisé '
            'reste disponible pour la sauvegarde chiffrée.';
      case GoogleSignInExceptionCode.interrupted:
        return 'Connexion Google interrompue : réessayez depuis AKIBA.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'L’écran de connexion Google n’a pas pu s’ouvrir : réessayez '
            'depuis l’application, en gardant l’écran allumé.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
      case GoogleSignInExceptionCode.unknownError:
        return 'Google refuse la connexion Android. '
            '${GoogleOAuthConfig.androidHint} Vérifiez aussi que ce compte '
            'figure dans les « utilisateurs test » de l’écran de consentement '
            'et que la portée drive.appdata est déclarée.';
      case GoogleSignInExceptionCode.userMismatch:
        return 'Un autre compte Google est déjà connecté sur cet appareil : '
            'déconnectez-le puis réessayez.';
    }
  }
}
