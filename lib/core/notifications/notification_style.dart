import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Style commun des notifications Android d'AKIBA.
///
/// Le texte complet est transmis **deux fois** : comme corps de la
/// notification (`contentText`) et comme `bigText`. Android affiche alors le
/// message entier en déplié, sans le couper par des points de suspension
/// « … », quelle que soit sa longueur.
abstract final class AkibaNotificationStyle {
  static const String icon = 'ic_stat_akiba';

  static const String welcomeChannelId = 'akiba_accueil';
  static const String welcomeChannelName = 'AKIBA';

  static const String remindersChannelId = 'akiba_rappels';
  static const String remindersChannelName = 'Rappels AKIBA';

  /// Détails Android d'une notification dont le corps ne doit jamais être
  /// tronqué.
  static AndroidNotificationDetails android({
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String title,
    required String body,
    Importance importance = Importance.defaultImportance,
    Priority priority = Priority.defaultPriority,
  }) {
    final String fullBody = body.trim();
    return AndroidNotificationDetails(
      channelId,
      channelName,
      icon: icon,
      channelDescription: channelDescription,
      importance: importance,
      priority: priority,
      ticker: fullBody.isEmpty ? title : fullBody,
      styleInformation: bigText(title: title, body: fullBody),
    );
  }

  /// Style « texte étendu » : [body] est repris tel quel dans `bigText`, sans
  /// reformatage ni troncature.
  static BigTextStyleInformation bigText({
    required String title,
    required String body,
  }) {
    return BigTextStyleInformation(body, contentTitle: title);
  }
}
