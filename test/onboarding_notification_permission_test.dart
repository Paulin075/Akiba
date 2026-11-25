import 'package:akiba/core/notifications/app_notifications.dart';
import 'package:akiba/core/notifications/notification_permission.dart';
import 'package:akiba/core/state/akiba_data_revision.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/core/theme/akiba_theme.dart';
import 'package:akiba/data/simulation_store.dart';
import 'package:akiba/features/onboarding/onboarding_flow.dart';
import 'package:akiba/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PermissionGateway implements NotificationPermissionGateway {
  _PermissionGateway(this.current, this.requestResult);

  NotificationPermissionState current;
  final NotificationPermissionState requestResult;
  int requests = 0;
  int settingsOpens = 0;

  @override
  bool get isSupported => true;

  @override
  Future<NotificationPermissionState> status() async => current;

  @override
  Future<NotificationPermissionState> request() async {
    requests++;
    current = requestResult;
    return requestResult;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpens++;
    return true;
  }
}

void main() {
  late SimulationAkibaStore store;
  late AkibaSettings settings;

  Future<void> mount(WidgetTester tester, _PermissionGateway gateway) async {
    store = SimulationAkibaStore();
    settings = AkibaSettings(store);
    await settings.load();
    await settings.setOnboardingStep(7);
    await tester.pumpWidget(
      MaterialApp(
        theme: AkibaTheme.forId(AkibaThemeId.blanc),
        home: OnboardingFlow(
          store: store,
          settings: settings,
          revision: AkibaDataRevision(),
          onFinished: () {},
          notificationPermissionGateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Des permissions expliquées'), findsOneWidget);
  }

  Finder remindersSwitch() => find.ancestor(
    of: find.text('Rappels matin, midi et soir'),
    matching: find.byType(SwitchListTile),
  );

  testWidgets(
    'permission déjà accordée : active le rappel sans nouvelle demande',
    (WidgetTester tester) async {
      final _PermissionGateway gateway = _PermissionGateway(
        NotificationPermissionState.granted,
        NotificationPermissionState.granted,
      );
      await mount(tester, gateway);

      await tester.tap(remindersSwitch());
      await tester.pumpAndSettle();

      expect(gateway.requests, 0);
      expect(tester.widget<SwitchListTile>(remindersSwitch()).value, isTrue);
      expect(settings.flag('permission_notifications'), isTrue);
    },
  );

  testWidgets('permission demandeable : le tap lance la demande système', (
    WidgetTester tester,
  ) async {
    final _PermissionGateway gateway = _PermissionGateway(
      NotificationPermissionState.denied,
      NotificationPermissionState.granted,
    );
    await mount(tester, gateway);

    await tester.tap(remindersSwitch());
    await tester.pumpAndSettle();

    expect(gateway.requests, 1);
    expect(tester.widget<SwitchListTile>(remindersSwitch()).value, isTrue);
    expect(settings.flag('permission_notifications'), isTrue);
  });

  testWidgets(
    'Reprogrammer confirme le succès si la permission système est accordée, '
    'même quand le miroir local est encore faux',
    (WidgetTester tester) async {
      store = SimulationAkibaStore();
      settings = AkibaSettings(store);
      await settings.load();
      // Miroir volontairement périmé : c'est l'état système qui décide.
      expect(settings.flag('permission_notifications'), isFalse);
      int calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AkibaTheme.forId(AkibaThemeId.blanc),
          home: Scaffold(
            body: ProfileScreen(
              store: store,
              settings: settings,
              revision: AkibaDataRevision(),
              onReplayOnboarding: () {},
              reprogramReminders: (AkibaSettings _) async {
                calls++;
                return 3;
              },
              notificationPermissionCheck: () async => true,
              notificationsSupported: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final Finder button = find.text('Reprogrammer');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(
        find.textContaining('3 rappels planifiés sur 7 jours'),
        findsOneWidget,
      );
      expect(
        find.textContaining('non autorisées par le système'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'fin onboarding envoie la bienvenue avec le nom avant navigation',
    (WidgetTester tester) async {
      final _PermissionGateway gateway = _PermissionGateway(
        NotificationPermissionState.granted,
        NotificationPermissionState.granted,
      );
      store = SimulationAkibaStore();
      settings = AkibaSettings(store);
      await settings.load();
      await settings.setOnboardingStep(10);
      await settings.set('first_name', 'Ama');
      await settings.set('last_name', 'Koffi');
      String? sentTitle;
      String? sentBody;
      AppNotifications.senderOverride = (String title, String body) async {
        sentTitle = title;
        sentBody = body;
        return true;
      };
      // Le miroir local est faux (permission accordée hors AKIBA) : la
      // bienvenue doit quand même partir puisque le gateway voit l'accord.
      bool finished = false;
      addTearDown(() => AppNotifications.senderOverride = null);
      // La plateforme native n'existe pas en test : l'accord système est simulé.
      AppNotifications.permissionCheckOverride = () async => true;
      addTearDown(() => AppNotifications.permissionCheckOverride = null);

      await tester.pumpWidget(
        MaterialApp(
          theme: AkibaTheme.forId(AkibaThemeId.blanc),
          home: OnboardingFlow(
            store: store,
            settings: settings,
            revision: AkibaDataRevision(),
            onFinished: () => finished = true,
            notificationPermissionGateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entrer dans AKIBA'));
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();

      expect(gateway.current, NotificationPermissionState.granted);
      expect(sentTitle, 'Bienvenue dans AKIBA');
      expect(sentBody, contains('Ama Koffi'));
      expect(finished, isTrue);
    },
  );

  testWidgets(
    'refus définitif : propose les réglages et se rafraîchit au retour',
    (WidgetTester tester) async {
      final _PermissionGateway gateway = _PermissionGateway(
        NotificationPermissionState.permanentlyDenied,
        NotificationPermissionState.granted,
      );
      await mount(tester, gateway);

      await tester.tap(remindersSwitch());
      await tester.pumpAndSettle();

      expect(gateway.requests, 0);
      expect(tester.widget<SwitchListTile>(remindersSwitch()).value, isFalse);
      expect(find.textContaining('refusée'), findsOneWidget);
      final Finder openSettings = find.text(
        'Ouvrir les réglages de notification',
      );
      expect(openSettings, findsOneWidget);
      await tester.ensureVisible(openSettings);
      await tester.pumpAndSettle();
      await tester.tap(openSettings);
      await tester.pumpAndSettle();
      expect(gateway.settingsOpens, 1);

      gateway.current = NotificationPermissionState.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(remindersSwitch()).value, isTrue);
      expect(settings.flag('permission_notifications'), isTrue);
      expect(find.textContaining('refusée'), findsNothing);
    },
  );

  test('bienvenue : le miroir local périmé ne bloque plus l’envoi', () async {
    final SimulationAkibaStore localStore = SimulationAkibaStore();
    final AkibaSettings localSettings = AkibaSettings(localStore);
    await localSettings.load();
    await localSettings.set('first_name', 'Ama');
    await localSettings.set('last_name', 'Koffi');
    // Permission accordée dans Android, miroir AKIBA jamais synchronisé.
    expect(localSettings.flag('permission_notifications'), isFalse);

    String? sentTitle;
    String? sentBody;
    AppNotifications.senderOverride = (String title, String body) async {
      sentTitle = title;
      sentBody = body;
      return true;
    };
    addTearDown(() => AppNotifications.senderOverride = null);
    AppNotifications.permissionCheckOverride = () async => true;
    addTearDown(() => AppNotifications.permissionCheckOverride = null);

    final bool sent = await AppNotifications.welcome(localSettings);

    expect(sent, isTrue);
    expect(sentTitle, 'Bienvenue dans AKIBA');
    expect(sentBody, contains('Ama Koffi'));
    expect(sentBody, isNot(contains('FCFA')));
  });
}
