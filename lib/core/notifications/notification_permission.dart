import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

import 'local_notifications.dart';

/// Résultat explicite de l'autorisation système de notification.
enum NotificationPermissionState {
  granted,
  denied,
  permanentlyDenied,
  unavailable,
}

/// Frontière injectable entre l'onboarding et les API de permission système.
abstract interface class NotificationPermissionGateway {
  bool get isSupported;

  Future<NotificationPermissionState> status();

  Future<NotificationPermissionState> request();

  Future<bool> openSettings();
}

/// Implémentation système. Android passe par `permission_handler` pour lire
/// précisément POST_NOTIFICATIONS et détecter le refus définitif; les autres
/// plateformes gardent le flux du greffon de notifications locales.
class SystemNotificationPermissionGateway
    implements NotificationPermissionGateway {
  const SystemNotificationPermissionGateway();

  @override
  bool get isSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isLinux);

  @override
  Future<NotificationPermissionState> status() async {
    if (!isSupported) return NotificationPermissionState.unavailable;
    if (Platform.isAndroid) {
      // Lecture directe du NotificationManager : elle ne dépend pas de
      // l'initialisation du greffon et reflète « Notifications : Autorisé ».
      final bool? platform = await LocalNotifications.platformPermissionState();
      // permission_handler sert à nommer un refus, jamais à contredire un
      // accord constaté par le système.
      final NotificationPermissionState declared = _fromPermissionStatus(
        await Permission.notification.status,
      );
      if (platform == true || declared == NotificationPermissionState.granted) {
        return NotificationPermissionState.granted;
      }
      return declared;
    }
    return await LocalNotifications.permissionGranted()
        ? NotificationPermissionState.granted
        : NotificationPermissionState.denied;
  }

  @override
  Future<NotificationPermissionState> request() async {
    if (!isSupported) return NotificationPermissionState.unavailable;
    if (Platform.isAndroid) {
      final NotificationPermissionState before = await status();
      if (before == NotificationPermissionState.granted ||
          before == NotificationPermissionState.permanentlyDenied) {
        return before;
      }
      // Une seule fenêtre système : celle de POST_NOTIFICATIONS portée par le
      // greffon. `LocalNotifications.requestPermission` retombe sur
      // permission_handler si le greffon n'est pas disponible.
      final bool requested = await LocalNotifications.requestPermission();
      final NotificationPermissionState after = await status();
      if (requested || after == NotificationPermissionState.granted) {
        return NotificationPermissionState.granted;
      }
      return after;
    }
    await LocalNotifications.ensureReady();
    return await LocalNotifications.requestPermission()
        ? NotificationPermissionState.granted
        : NotificationPermissionState.denied;
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  NotificationPermissionState _fromPermissionStatus(PermissionStatus status) {
    if (status.isGranted) return NotificationPermissionState.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return NotificationPermissionState.permanentlyDenied;
    }
    return NotificationPermissionState.denied;
  }
}
