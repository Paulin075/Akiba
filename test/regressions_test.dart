import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:akiba/core/ai/ai_command_parser.dart';
import 'package:akiba/core/security/pin_vault.dart';
import 'package:akiba/core/state/akiba_data_revision.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/core/theme/akiba_theme.dart';
import 'package:akiba/core/widgets/cauri_drop.dart';
import 'package:akiba/data/models/transaction_record.dart';
import 'package:akiba/data/simulation_store.dart';
import 'package:akiba/features/analysis/analysis_screen.dart';
import 'package:akiba/features/portfolio/portfolio_screen.dart';
import 'package:akiba/features/splash/splash_screen.dart';

void main() {
  group('Analyse vocale : créances et dettes', () {
    test('« Koffi me doit 5 000 » produit une créance, pas une sortie', () {
      final AiDraft draft = AiCommandParser.parse('Koffi me doit 5000')!;

      expect(draft.debtDirection, 'owedToMe');
      expect(draft.counterparty, 'Koffi');
      expect(draft.amount, 5000);
      // Une créance n'est ni neutre ni une sortie d'argent.
      expect(draft.isNeutral, isFalse);
      expect(draft.kind, TransactionKind.income);
    });

    test('« On me doit 12 000 » est une créance sans contact nommé', () {
      final AiDraft draft = AiCommandParser.parse('On me doit 12 000')!;

      expect(draft.debtDirection, 'owedToMe');
      expect(draft.counterparty, isNull);
      expect(draft.isNeutral, isFalse);
      expect(draft.amount, 12000);
    });

    test('« Je dois 5 000 à Ama » produit une dette', () {
      final AiDraft draft = AiCommandParser.parse('Je dois 5 000 à Ama')!;

      expect(draft.debtDirection, 'iOwe');
      expect(draft.counterparty, 'Ama');
      expect(draft.amount, 5000);
      expect(draft.isNeutral, isFalse);
      expect(draft.kind, TransactionKind.expense);
    });

    test('« il me doit 3 000 » et « je dois rembourser » restent séparés', () {
      expect(
        AiCommandParser.parse('il me doit 3 000')?.debtDirection,
        'owedToMe',
      );
      expect(
        AiCommandParser.parse(
          'je dois rembourser 3 000 à Koffi',
        )?.debtDirection,
        'iOwe',
      );
    });

    test('une dépense ordinaire reste une sortie catégorisée', () {
      final AiDraft draft = AiCommandParser.parse(
        'j’ai payé 5 000 pour le transport',
      )!;

      expect(draft.debtDirection, isNull);
      expect(draft.kind, TransactionKind.expense);
      expect(draft.category, 'Transport');
      expect(draft.isNeutral, isFalse);
    });
  });

  group('Module PIN', () {
    test(
      'l’empreinte persiste et active le verrou après rechargement',
      () async {
        final SimulationAkibaStore store = SimulationAkibaStore();
        final AkibaSettings settings = AkibaSettings(store);
        await settings.load();

        expect(settings.pinEnabled, isFalse);

        await PinVault(settings.store).setPin('4821');
        await settings.load();

        expect(settings.pinEnabled, isTrue);
        expect(settings.pinHash.isNotEmpty, isTrue);
        expect(settings.pinSalt.isNotEmpty, isTrue);
        expect(await PinVault(store).verify('4821'), isTrue);
        expect(await PinVault(store).verify('4822'), isFalse);
      },
    );

    test(
      'le PIN est écrit dans les réglages, pas dans le magasin simulé',
      () async {
        final SimulationAkibaStore real = SimulationAkibaStore();
        final SimulationAkibaStore simulation = SimulationAkibaStore();
        final AkibaSettings settings = AkibaSettings(real);
        await settings.load();

        await PinVault(settings.store).setPin('7391');
        await settings.load();

        expect(settings.pinEnabled, isTrue);
        // Le mode simulation ne connaît pas le PIN : il ne peut pas le désactiver.
        expect(await PinVault(simulation).isConfigured(), isFalse);
      },
    );

    test('un PIN trivial reste refusé', () async {
      final SimulationAkibaStore store = SimulationAkibaStore();
      expect(
        () => PinVault(store).setPin('1111'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PinVault(store).setPin('1234'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('LockGate', () {
    const String salt = '00112233445566778899aabbccddeeff';

    Widget gate({required bool pinEnabled, bool biometrics = false}) {
      final String hash = pinEnabled ? PinVault.hashPin('4821', salt) : '';
      return MaterialApp(
        theme: AkibaTheme.light(),
        home: LockGate(
          pinEnabled: pinEnabled,
          pinHash: hash,
          pinSalt: salt,
          biometrics: biometrics,
          lockOnPause: true,
          biometricPrompt: () async => false,
          child: const Text('ACCUEIL'),
        ),
      );
    }

    testWidgets(
      'se verrouille dès que le PIN est activé, puis accepte le code',
      (WidgetTester tester) async {
        await tester.pumpWidget(gate(pinEnabled: false));
        expect(find.text('ACCUEIL'), findsOneWidget);

        // Activation du PIN dans le Profil : le verrou apparaît immédiatement.
        await tester.pumpWidget(gate(pinEnabled: true));
        await tester.pump();

        expect(find.text('AKIBA est verrouillé'), findsOneWidget);
        expect(find.text('ACCUEIL'), findsNothing);

        await tester.enterText(find.byType(TextField), '4821');
        await tester.tap(find.text('Déverrouiller'));
        await tester.pump();

        expect(find.text('ACCUEIL'), findsOneWidget);
      },
    );

    testWidgets('un code faux garde le verrou fermé', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(gate(pinEnabled: true));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.text('Déverrouiller'));
      await tester.pump();

      expect(find.text('Code incorrect.'), findsOneWidget);
      expect(find.text('ACCUEIL'), findsNothing);
    });

    testWidgets('biométrie indisponible : le PIN reste le repli', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(gate(pinEnabled: true, biometrics: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('AKIBA est verrouillé'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Utiliser la biométrie'), findsOneWidget);
    });
  });

  group('Robustesse des écrans (320 px)', () {
    testWidgets('Ouverture : animation seule sur 320 px, sans débordement', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(theme: AkibaTheme.light(), home: const SplashScreen()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(CauriDropAnimation), findsOneWidget);
      // Plus de titre ni de barre de chargement : l'animation seule.
      expect(find.text('AKIBA'), findsNothing);

      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Portefeuille > Épargne ne déborde pas', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final SimulationAkibaStore store = SimulationAkibaStore();
      final AkibaDataRevision revision = AkibaDataRevision();
      addTearDown(revision.dispose);
      final AkibaSettings settings = AkibaSettings(store);
      await settings.load();

      await tester.pumpWidget(
        MaterialApp(
          theme: AkibaTheme.light(),
          home: AkibaSettingsScope(
            settings: settings,
            child: Scaffold(
              body: PortfolioScreen(store: store, revision: revision),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Épargne'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(tester.takeException(), isNull);
      expect(find.text('ÉPARGNE TOTALE'), findsOneWidget);
    });

    testWidgets('Analyses > Budget affiche une icône par catégorie', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final SimulationAkibaStore store = SimulationAkibaStore();
      final AkibaDataRevision revision = AkibaDataRevision();
      addTearDown(revision.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AkibaTheme.light(),
          home: Scaffold(
            body: AnalysisScreen(store: store, revision: revision),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Budget'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.restaurant_rounded), findsWidgets);
    });
  });
}
