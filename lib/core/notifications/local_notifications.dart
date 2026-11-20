import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_planner.dart';

/// Livraison des rappels par le système (notifications locales).
///
/// Android, iOS, macOS et Linux sont pris en charge par le greffon. Windows
/// n'expose pas encore de planification dans cette version : l'interface le
/// signale et propose les mêmes messages dans l'application.
abstract final class LocalNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static bool _timezoneReady = false;
  static String _lastError = '';

  static bool get supported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isLinux);

  static String get lastError => _lastError;

  static Future<bool> ensureReady({String timezone = 'Africa/Lome'}) async {
    if (!supported) return false;
    if (_ready) return true;

    try {
      if (!_timezoneReady) {
        tzdata.initializeTimeZones();
        try {
          tz.setLocalLocation(tz.getLocation(timezone));
        } catch (_) {
          tz.setLocalLocation(tz.getLocation('Africa/Lome'));
        }
        _timezoneReady = true;
      }

      const AndroidInitializationSettings android =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: false,
        requestSoundPermission: true,
      );
      _ready =
          await _plugin.initialize(
            settings: const InitializationSettings(
              android: android,
              iOS: darwin,
              macOS: darwin,
            ),
          ) ??
          false;
      return _ready;
    } catch (error) {
      _lastError = error.runtimeType.toString();
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    if (!supported) return false;
    try {
      if (Platform.isAndroid) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      }
      if (Platform.isIOS || Platform.isMacOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, sound: true) ??
            false;
      }
      return true;
    } catch (error) {
      _lastError = error.runtimeType.toString();
      return false;
    }
  }

  static Future<int> schedule(List<ReminderPlan> plans) async {
    final bool ready = await ensureReady();
    if (!ready) return 0;
    await cancelAll();

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'akiba_rappels',
        'Rappels AKIBA',
        channelDescription:
            'Rappels matin, midi et soir. Aucun montant si le masquage est '
            'actif.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      linux: LinuxNotificationDetails(),
    );

    int scheduled = 0;
    for (int index = 0; index < plans.length; index++) {
      final ReminderPlan plan = plans[index];
      try {
        await _plugin.zonedSchedule(
          id: 1000 + index,
          title: plan.title,
          body: plan.body,
          scheduledDate: tz.TZDateTime.from(plan.when, tz.local),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: plan.slot,
        );
        scheduled++;
      } catch (error) {
        _lastError = error.runtimeType.toString();
      }
    }
    return scheduled;
  }

  static Future<void> cancelAll() async {
    if (!supported) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Aucun rappel à annuler.
    }
  }
}
