import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../state/akiba_settings.dart';
import 'reminder_planner.dart';

/// Tâche périodique d'arrière-plan : toutes les 30 minutes, un rappel de repas
/// ou de saisie de dépenses est publié uniquement dans les plages prévues.
///
/// Les messages ne contiennent **jamais** de montant : le masquage reste
/// effectif même dans le tiroir de notifications.
const String akibaMealTask = 'akiba.meal.reminders';
const String akibaMealTaskName = 'Rappels de repas';
const String akibaExpenseTask = 'akiba.expense.reminders';
const String akibaExpenseTaskName = 'Rappels de dépenses';
bool _workmanagerInitialized = false;

/// Empreinte des réglages déjà enregistrés auprès du système, pour ne pas
/// réinscrire deux fois les mêmes tâches dans un même lancement.
String? _scheduledSignature;

@pragma('vm:entry-point')
void akibaCallbackDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    try {
      if (input?['enabled'] != true) return true;
      final DateTime now = DateTime.now();
      final String? message = task == akibaExpenseTask
          ? expenseMessageFor(now)
          : mealMessageFor(
              now,
              morningEnabled: input?['morning'] == true,
              noonEnabled: input?['noon'] == true,
              eveningEnabled: input?['evening'] == true,
            );
      if (message == null) return true;

      // Même icône `drawable` que le greffon principal : `@mipmap/…` est
      // refusé par la validation du greffon (code `invalid_icon`).
      const AndroidInitializationSettings android =
          AndroidInitializationSettings('ic_stat_akiba');
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
            icon: 'ic_stat_akiba',
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
String? mealMessageFor(
  DateTime now, {
  bool morningEnabled = true,
  bool noonEnabled = true,
  bool eveningEnabled = true,
}) {
  final int hour = now.hour;
  if (morningEnabled && hour >= 7 && hour < 9) {
    return 'Petit-déjeuner : un geste pour noter la journée ?';
  }
  if (noonEnabled && hour >= 12 && hour < 14) {
    return 'Déjeuner : pensez à noter vos dépenses du midi.';
  }
  if (eveningEnabled && hour >= 19 && hour < 21) {
    return 'Dîner : la journée se termine, un dernier point ?';
  }
  return null;
}

/// Rappel de saisie en fin de journée, sans montant ni détail financier.
String? expenseMessageFor(DateTime now) {
  if (now.hour >= 17 && now.hour < 20) {
    return 'Pensez à noter vos dépenses de la journée dans AKIBA.';
  }
  return null;
}

/// Enregistre la tâche périodique si les rappels sont actifs.
abstract final class BackgroundReminders {
  static Future<bool> ensureScheduled(AkibaSettings settings) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final bool mealsWanted =
        settings.morningEnabled ||
        settings.noonEnabled ||
        settings.eveningEnabled;
    if (!mealsWanted && !settings.expenseReminderEnabled) {
      await cancel();
      return false;
    }

    // Deux appels dans le même lancement (démarrage + Profil) ne doivent pas
    // annuler puis réinscrire la même tâche : Workmanager peut alors perdre sa
    // fenêtre ou dupliquer l'exécution.
    final String signature =
        '${settings.morningEnabled}|${settings.noonEnabled}|'
        '${settings.eveningEnabled}|${settings.expenseReminderEnabled}';
    if (_workmanagerInitialized && _scheduledSignature == signature) {
      return true;
    }

    try {
      if (!_workmanagerInitialized) {
        await Workmanager().initialize(akibaCallbackDispatcher);
        _workmanagerInitialized = true;
      }
      // Replace the registration so changing a switch cannot leave stale task
      // input enabled in the operating system's persisted work queue.
      await Workmanager().cancelByUniqueName(akibaMealTask);
      await Workmanager().cancelByUniqueName(akibaExpenseTask);
      if (mealsWanted) {
        await Workmanager().registerPeriodicTask(
          akibaMealTask,
          akibaMealTaskName,
          frequency: const Duration(minutes: 30),
          inputData: <String, dynamic>{
            'enabled': true,
            'morning': settings.morningEnabled,
            'noon': settings.noonEnabled,
            'evening': settings.eveningEnabled,
          },
          existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
          constraints: Constraints(networkType: NetworkType.notRequired),
        );
      }
      if (settings.expenseReminderEnabled) {
        await Workmanager().registerPeriodicTask(
          akibaExpenseTask,
          akibaExpenseTaskName,
          frequency: const Duration(minutes: 30),
          inputData: const <String, dynamic>{'enabled': true},
          existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
          constraints: Constraints(networkType: NetworkType.notRequired),
        );
      }
      _scheduledSignature = signature;
      return true;
    } catch (error) {
      _scheduledSignature = null;
      debugPrint('AKIBA planification arrière-plan (${error.runtimeType}).');
      return false;
    }
  }

  static Future<void> cancel() async {
    _scheduledSignature = null;
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Workmanager().cancelByUniqueName(akibaMealTask);
      await Workmanager().cancelByUniqueName(akibaExpenseTask);
    } catch (_) {
      // Rien à annuler.
    }
  }
}
