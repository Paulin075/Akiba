import '../state/akiba_settings.dart';
import 'local_notifications.dart';

/// Notifications applicatives ponctuelles (hors rappels planifiés).
///
/// Règles AKIBA :
/// - aucun montant n'est jamais écrit dans un message de notification ;
/// - rien n'est envoyé sans autorisation système réelle ; le drapeau
///   `permission_notifications` n'est qu'un miroir, jamais une condition ;
/// - l'échec d'affichage est silencieux (l'application n'est jamais bloquée).
abstract final class AppNotifications {
  static const int welcomeId = 900;

  /// Point d'injection utilisé par les tests pour vérifier le déclenchement
  /// sans greffon natif. En production il reste `null`.
  static Future<bool> Function(String title, String body)? senderOverride;

  /// Même rôle pour l'état **système** de l'autorisation : les tests peuvent
  /// simuler un accord ou un refus sans plateforme native.
  static Future<bool> Function()? permissionCheckOverride;

  static String welcomeTitle(String language) =>
      language == 'en' ? 'Welcome to AKIBA' : 'Bienvenue dans AKIBA';

  /// Message de bienvenue : jamais de montant, même hors mode masqué.
  static String welcomeBody(String language, {required String name}) {
    final String greeting = name.trim();
    if (language == 'en') {
      return greeting.isEmpty
          ? 'Welcome! Your space is ready. Tap the pig to record your first '
                'entry; your figures stay private and encrypted.'
          : 'Welcome, $greeting! Your space is ready. Tap the pig to record '
                'your first entry; your figures stay private and encrypted.';
    }
    return greeting.isEmpty
        ? 'Bienvenue ! Votre espace est prêt. Touchez le cochon pour '
              'enregistrer votre première ligne ; vos chiffres restent privés '
              'et chiffrés.'
        : 'Bienvenue, $greeting ! Votre espace est prêt. Touchez le cochon '
              'pour enregistrer votre première ligne ; vos chiffres restent '
              'privés et chiffrés.';
  }

  /// Envoie la bienvenue si la personne a autorisé les notifications.
  ///
  /// La langue suit le réglage actif. Le masquage des montants n'a aucun effet
  /// ici : le texte n'en contient aucun, par construction.
  static Future<bool> welcome(AkibaSettings settings) async {
    final Future<bool> Function(String title, String body)? override =
        senderOverride;
    if (override != null) {
      final bool granted =
          await (permissionCheckOverride?.call() ??
              LocalNotifications.permissionGranted());
      if (!granted) return false;
      final String name = <String>[
        settings.firstName.trim(),
        settings.lastName.trim(),
      ].where((String part) => part.isNotEmpty).join(' ');
      return override(
        welcomeTitle(settings.language),
        welcomeBody(settings.language, name: name),
      );
    }
    if (!LocalNotifications.supported) return false;
    // Toujours relire l'état système; le miroir local peut être obsolète ou
    // avoir manqué l'accord effectué hors AKIBA (cas constaté sur appareil).
    if (!await LocalNotifications.permissionGranted()) return false;
    await settings.setFlag('permission_notifications', true);
    final String language = settings.language;
    final String title = welcomeTitle(language);
    final String name = <String>[
      settings.firstName.trim(),
      settings.lastName.trim(),
    ].where((String part) => part.isNotEmpty).join(' ');
    final String body = welcomeBody(language, name: name);
    // `show` initialise le plugin et crée le canal akiba_accueil si nécessaire.
    return LocalNotifications.show(id: welcomeId, title: title, body: body);
  }
}
