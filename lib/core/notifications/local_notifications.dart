import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
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

      // L'icône doit être une ressource **drawable** : le greffon la résout
      // avec `getIdentifier(nom, "drawable", paquet)` et refuse
      // `@mipmap/ic_launcher`. Une icône invalide faisait échouer
      // l'initialisation, donc toutes les lectures de permission.
      const AndroidInitializationSettings android =
          AndroidInitializationSettings('ic_stat_akiba');
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

  /// État **réel** de l'autorisation système, sans ouvrir de fenêtre et sans
  /// dépendre de l'initialisation du greffon.
  ///
  /// `areNotificationsEnabled()` interroge directement le `NotificationManager`
  /// (POST_NOTIFICATIONS sur API 33+, activation générale avant). `null`
  /// signifie « illisible sur cette plateforme », jamais « refusé ».
  static Future<bool?> platformPermissionState() async {
    if (!supported) return null;
    try {
      if (Platform.isAndroid) {
        return await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled();
      }
      if (Platform.isIOS || Platform.isMacOS) {
        final NotificationsEnabledOptions? options = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions();
        return options?.isEnabled;
      }
      return true;
    } catch (error) {
      _lastError = error.runtimeType.toString();
      return null;
    }
  }

  /// État **réel** de l'autorisation système, sans ouvrir de fenêtre.
  ///
  /// La lecture de la plateforme n'est **jamais** conditionnée à
  /// l'initialisation du greffon : un échec d'initialisation ne doit pas se
  /// traduire par « notifications non autorisées ».
  static Future<bool> permissionGranted() async {
    if (!supported) return false;
    final bool? platform = await platformPermissionState();
    if (platform != null) return platform;
    // Dernier recours : permission_handler, qui lit POST_NOTIFICATIONS.
    try {
      if (Platform.isAndroid) return await Permission.notification.isGranted;
    } catch (error) {
      _lastError = error.runtimeType.toString();
    }
    return false;
  }

  /// État de livraison d'un canal Android nommé. `null` indique que le canal
  /// n'existe pas (ou que la plateforme ne permet pas de le lire).
  static Future<bool?> androidChannelEnabled(String channelId) async {
    if (!Platform.isAndroid) return null;
    try {
      final List<AndroidNotificationChannel>? channels = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.getNotificationChannels();
      if (channels == null) return null;
      for (final AndroidNotificationChannel channel in channels) {
        if (channel.id == channelId) {
          return channel.importance != Importance.none;
        }
      }
      return null;
    } catch (error) {
      _lastError = error.runtimeType.toString();
      return null;
    }
  }

  static Future<bool> requestPermission() async {
    if (!supported) return false;
    try {
      if (Platform.isAndroid) {
        final bool? already = await platformPermissionState();
        if (already == true) return true;
        // Le greffon doit être initialisé avant toute demande système, sinon
        // Android répond « introuvable » sur certains appareils.
        await ensureReady();
        final AndroidFlutterLocalNotificationsPlugin? android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final bool? granted = await android?.requestNotificationsPermission();
        if (granted == true) return true;
        // `null` signifie « rien à demander » sur certaines versions : on
        // relit l'état réel au lieu de répondre « refusé » à tort.
        final bool? after = await platformPermissionState();
        if (after != null) return after;
        return Permission.notification.request().then(
          (PermissionStatus status) => status.isGranted,
        );
      }
      if (Platform.isIOS || Platform.isMacOS) {
        final IOSFlutterLocalNotificationsPlugin? ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final bool? granted = await ios?.requestPermissions(
          alert: true,
          sound: true,
        );
        if (granted == true) return true;
        return await permissionGranted();
      }
      return true;
    } catch (error) {
      _lastError = error.runtimeType.toString();
      return false;
    }
  }

  /// Affiche une notification immédiate, sans planification.
  ///
  /// Utilisé pour la bienvenue de fin d'onboarding. Ne demande **pas** de
  /// permission : sans autorisation déjà accordée, rien ne s'affiche et la
  /// fonction renvoie faux (aucune fenêtre système surprise).
  static Future<bool> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!supported) return false;
    if (!await permissionGranted()) return false;
    // Initialisation au mieux : l'icône est fournie explicitement, donc
    // l'affichage n'échoue pas si le greffon n'a pas pu s'initialiser.
    await ensureReady();
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'akiba_accueil',
            'AKIBA',
            icon: 'ic_stat_akiba',
            channelDescription:
                'Bienvenue et messages d’accueil. '
                'Aucun montant.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
        payload: 'welcome',
      );
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
        icon: 'ic_stat_akiba',
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
    // Sans initialisation préalable, `cancelAll` ne peut pas atteindre le
    // service de notifications : rien n'est annulé et les anciens rappels
    // restent programmés.
    if (!await ensureReady()) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Aucun rappel à annuler.
    }
  }
}
