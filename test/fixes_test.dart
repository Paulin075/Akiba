import 'dart:io';

import 'package:akiba/core/database/akiba_database.dart';
import 'package:akiba/core/database/akiba_secure_key.dart';
import 'package:akiba/core/format/akiba_date.dart';
import 'package:akiba/core/format/akiba_money.dart';
import 'package:akiba/core/state/akiba_data_revision.dart';
import 'package:akiba/core/state/akiba_l10n.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/core/state/masked_amounts.dart';
import 'package:akiba/core/theme/akiba_theme.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:akiba/data/models/account.dart';
import 'package:akiba/data/models/debt.dart';
import 'package:akiba/data/models/transaction_record.dart';
import 'package:akiba/data/sqlite_akiba_store.dart';
import 'package:akiba/features/dashboard/dashboard_screen.dart';
import 'package:akiba/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Correctifs ciblés : langue de l'onboarding, règlement des créances et
/// dettes, et réactivité du solde de l'accueil.
void main() {
  late Directory directory;
  late Database db;
  late SqliteAkibaStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('akiba_fixes');
    final String keyHex = AkibaSecureKey.generateHexKey();
    db = AkibaDatabase.openEncrypted(
      p.join(directory.path, 'akiba.db'),
      keyHex: keyHex,
    );
    store = SqliteAkibaStore(db);
  });

  tearDown(() {
    db.close();
    directory.deleteSync(recursive: true);
  });

  group('Langue', () {
    test(
      'changer la langue met à jour les globales avant de notifier',
      () async {
        final AkibaSettings settings = AkibaSettings(const EmptyAkibaStore());
        await settings.load();
        int notifications = 0;
        settings.addListener(() => notifications++);

        await settings.setLanguage('en');

        expect(settings.language, 'en');
        expect(AkibaL10n.isEnglish, isTrue);
        expect(AkibaDate.english, isTrue);
        expect(notifications, greaterThan(0));

        await settings.setLanguage('fr');
        expect(AkibaL10n.isEnglish, isFalse);
        expect(AkibaDate.english, isFalse);
      },
    );

    testWidgets('choisir English dans l’onboarding bascule l’interface', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() {
        AkibaL10n.setLanguage('fr');
        AkibaDate.english = false;
      });

      final AkibaSettings settings = AkibaSettings(const EmptyAkibaStore());
      await settings.load();
      await tester.pumpWidget(AkibaApp(settings: settings));
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 400));

      // E1 : la langue se choisit tout de suite, sans finir le parcours.
      expect(find.text('Votre langue'), findsOneWidget);
      await tester.ensureVisible(find.text('English'));
      await tester.pump();
      await tester.tap(find.text('English'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(settings.language, 'en');
      expect(AkibaL10n.isEnglish, isTrue);
      // Le parcours lui-même est traduit, preuve que l'arbre a bien notifié.
      expect(find.text('Your language'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Votre langue'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Règlement des créances et dettes', () {
    test('une créance encaissée augmente le solde disponible', () async {
      await store.ensureDefaultAccounts();
      final List<Account> accounts = await store.accounts();
      final Account account = accounts.first;
      final DateTime now = DateTime.now();
      await store.saveTransaction(
        TransactionRecord(
          id: 'opening',
          accountId: account.id,
          amount: 10000,
          kind: TransactionKind.opening,
          occurredAt: now,
          createdAt: now,
        ),
      );
      final Debt debt = Debt(
        id: 'debt-owed',
        direction: DebtDirection.owedToMe,
        counterparty: 'Koffi',
        principal: 5000,
        createdAt: now,
      );
      await store.saveDebt(debt);

      // Tant qu'elle n'est pas réglée, elle reste hors du solde.
      expect((await store.loadDashboard()).balance.available, 10000);

      final TransactionRecord movement = await store.settleDebt(
        debt,
        amount: 5000,
        accountId: account.id,
      );

      expect(movement.amount, 5000);
      expect(movement.kind, TransactionKind.income);
      expect(movement.isNeutral, isFalse);
      expect((await store.loadDashboard()).balance.available, 15000);
      expect((await store.debts()).single.isSettled, isTrue);
    });

    test('une dette payée retire le montant du compte choisi', () async {
      await store.ensureDefaultAccounts();
      final List<Account> accounts = await store.accounts();
      final Account payer = accounts.first;
      final Account other = accounts[1];
      final DateTime now = DateTime.now();
      await store.saveTransaction(
        TransactionRecord(
          id: 'opening-a',
          accountId: payer.id,
          amount: 8000,
          kind: TransactionKind.opening,
          occurredAt: now,
          createdAt: now,
        ),
      );
      await store.saveTransaction(
        TransactionRecord(
          id: 'opening-b',
          accountId: other.id,
          amount: 2000,
          kind: TransactionKind.opening,
          occurredAt: now,
          createdAt: now,
        ),
      );
      final Debt debt = Debt(
        id: 'debt-owe',
        direction: DebtDirection.iOwe,
        counterparty: 'Ama',
        principal: 3000,
        createdAt: now,
      );
      await store.saveDebt(debt);

      final TransactionRecord movement = await store.settleDebt(
        debt,
        amount: 2000,
        accountId: payer.id,
      );

      expect(movement.amount, -2000);
      expect(movement.kind, TransactionKind.expense);
      expect((await store.loadDashboard()).balance.available, 8000);
      final Debt after = (await store.debts()).single;
      expect(after.remaining, 1000);
      expect(after.isSettled, isFalse);

      // Annulation : le mouvement disparaît et le reste dû revient.
      await store.deleteTransaction(movement);
      await store.saveDebt(debt);
      expect((await store.loadDashboard()).balance.available, 10000);
      expect((await store.debts()).single.remaining, 3000);
    });

    test('le montant du règlement est borné au reste dû', () async {
      await store.ensureDefaultAccounts();
      final Account account = (await store.accounts()).first;
      final DateTime now = DateTime.now();
      final Debt debt = Debt(
        id: 'debt-cap',
        direction: DebtDirection.owedToMe,
        counterparty: 'Yao',
        principal: 4000,
        createdAt: now,
      );
      await store.saveDebt(debt);

      final TransactionRecord movement = await store.settleDebt(
        debt,
        amount: 9000,
        accountId: account.id,
      );

      expect(movement.amount, 4000);
      expect((await store.debts()).single.isSettled, isTrue);
    });
  });

  testWidgets(
    'le solde de l’accueil suit chaque écriture sans changer d’onglet',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AkibaMoney.currency = 'FCFA';

      await store.ensureDefaultAccounts();
      final List<Account> accounts = await store.accounts();
      final Account account = accounts.first;
      final AkibaSettings settings = AkibaSettings(const EmptyAkibaStore());
      await settings.load();
      final AkibaDataRevision revision = AkibaDataRevision();
      final ValueNotifier<bool> masked = ValueNotifier<bool>(false);
      addTearDown(masked.dispose);

      await tester.pumpWidget(
        AkibaSettingsScope(
          settings: settings,
          child: MaterialApp(
            theme: AkibaTheme.light(),
            home: MaskedAmounts(
              notifier: masked,
              child: Scaffold(
                body: DashboardScreen(
                  store: store,
                  revision: revision,
                  themeId: AkibaThemeId.blanc,
                  onThemeChanged: (AkibaThemeId _) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final DateTime now = DateTime.now();
      await store.saveTransaction(
        TransactionRecord(
          id: 'in-1',
          accountId: account.id,
          amount: 12000,
          kind: TransactionKind.income,
          category: 'Salaire',
          occurredAt: now,
          createdAt: now,
        ),
      );
      revision.bump();
      await tester.pumpAndSettle();
      expect(find.text(AkibaMoney.format(12000)), findsWidgets);

      // Une dépense met le solde à jour immédiatement, sans changer d'onglet.
      await store.saveTransaction(
        TransactionRecord(
          id: 'out-1',
          accountId: account.id,
          amount: -5000,
          kind: TransactionKind.expense,
          category: 'Transport',
          occurredAt: now,
          createdAt: now,
        ),
      );
      revision.bump();
      await tester.pumpAndSettle();
      expect(find.text(AkibaMoney.format(7000)), findsWidgets);
      expect(find.text(AkibaMoney.format(12000)), findsNothing);

      // Règlement d'une créance : le solde augmente aussitôt.
      final Debt debt = Debt(
        id: 'debt-live',
        direction: DebtDirection.owedToMe,
        counterparty: 'Koffi',
        principal: 3000,
        createdAt: now,
      );
      await store.saveDebt(debt);
      await store.settleDebt(debt, amount: 3000, accountId: account.id);
      revision.bump();
      await tester.pumpAndSettle();
      expect(find.text(AkibaMoney.format(10000)), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
