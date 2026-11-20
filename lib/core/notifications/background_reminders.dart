import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../state/akiba_settings.dart';
import 'reminder_planner.dart';

/// Tâche périodique d'arrière-plan : toutes les 30 minutes, un rappel de repas
/// est publié **uniquement** dans les plages prévues (petit-déjeuner,
/// déjeuner, dîner). Hors plage, la tâche s'arrête immédiatement : le coût
/// batterie reste minime.
///
/// Les messages ne contiennent **jamais** de montant : le masquage reste
/// effectif même dans le tiroir de notifications.
const String akibaMealTask = 'akiba.meal.reminders';
const String akibaMealTaskName = 'Rappels de repas';

@pragma('vm:entry-point')
void akibaCallbackDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    try {
      final DateTime now = DateTime.now();
      final String? message = mealMessageFor(now);
      if (message == null) return true;

      const AndroidInitializationSettings android =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      final FlutterLocalNotificationsPlugin plugin =
          FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(android: android),
      );
      await plugin.show(
        id: 4200 + now.hour,
        title: 'AKIBA',
        body: ReminderPlanner.sanitize(message, masked: true),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'akiba_repas',
            'Rappels de repas',
            channelDescription:
                'Rappels du petit-déjeuner, du déjeuner et du dîner. '
                'Aucun montant.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
      return true;
    } catch (error) {
      // Aucune donnée, uniquement le type d'erreur.
      debugPrint('AKIBA rappel arrière-plan (${error.runtimeType}).');
      return true;
    }
  });
}

/// Message de repas correspondant à l'heure, ou `null` hors plage.
String? mealMessageFor(DateTime now) {
  final int hour = now.hour;
  if (hour >= 7 && hour < 9) {
    return 'Petit-déjeuner : un geste pour noter la journée ?';
  }
  if (hour >= 12 && hour < 14) {
    return 'Déjeuner : pensez à noter vos dépenses du midi.';
  }
  if (hour >= 19 && hour < 21) {
    return 'Dîner : la journée se termine, un dernier point ?';
  }
  return null;
}

/// Enregistre la tâche périodique si les rappels sont actifs.
abstract final class BackgroundReminders {
  static bool _registered = false;

  static Future<bool> ensureScheduled(AkibaSettings settings) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    if (_registered) return true;
    final bool wanted =
        settings.morningEnabled ||
        settings.noonEnabled ||
        settings.eveningEnabled;
    if (!wanted) return false;

    try {
      await Workmanager().initialize(akibaCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        akibaMealTask,
        akibaMealTaskName,
        frequency: const Duration(minutes: 30),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.notRequired),
      );
      _registered = true;
      return true;
    } catch (error) {
      debugPrint('AKIBA planification arrière-plan (${error.runtimeType}).');
      return false;
    }
  }

  static Future<void> cancel() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Workmanager().cancelByUniqueName(akibaMealTask);
      _registered = false;
    } catch (_) {
      // Rien à annuler.
    }
  }
}
