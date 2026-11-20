import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:akiba/core/database/akiba_database.dart';
import 'package:akiba/core/database/akiba_schema.dart';
import 'package:akiba/core/database/akiba_secure_key.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:akiba/data/models/account.dart';
import 'package:akiba/data/models/account_brand.dart';
import 'package:akiba/data/models/analysis.dart';
import 'package:akiba/data/models/budget.dart';
import 'package:akiba/data/models/debt.dart';
import 'package:akiba/data/models/need.dart';
import 'package:akiba/data/models/savings_pot.dart';
import 'package:akiba/data/models/third_party.dart';
import 'package:akiba/data/models/transaction_record.dart';
import 'package:akiba/data/sqlite_akiba_store.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 19, 10, 15);

  group('Base chiffrée', () {
    late Directory directory;
    late String path;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('akiba_db');
      path = p.join(directory.path, 'akiba.db');
    });

    tearDown(() {
      directory.deleteSync(recursive: true);
    });

    test('le fichier reste illisible sans la clé', () {
      final String keyHex = AkibaSecureKey.generateHexKey();
      final Database db = AkibaDatabase.openEncrypted(path, keyHex: keyHex);
      db
        ..execute(
          'INSERT INTO accounts (id, name, brand, created_at) '
          "VALUES ('a', 'Flooz', 'flooz', '2026-11-19T08:00:00.000Z')",
        )
        ..close();

      final Database locked = sqlite3.open(path);
      try {
        expect(
          () => locked.select('SELECT * FROM accounts'),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        locked.close();
      }

      final Database reopened = AkibaDatabase.openEncrypted(
        path,
        keyHex: keyHex,
      );
      expect(
        reopened.select('SELECT name FROM accounts').first['name'],
        'Flooz',
      );
      reopened.close();
    });

    test('la migration est idempotente', () {
      final Database db = AkibaDatabase.openEncrypted(
        path,
        keyHex: AkibaSecureKey.generateHexKey(),
      );
      AkibaSchema.migrate(db);
      AkibaSchema.migrate(db);

      final ResultSet version = db.select('PRAGMA user_version');
      expect(version.first.values.first, AkibaSchema.version);
      db.close();
    });

    test('une clé invalide est refusée', () {
      expect(
        () => AkibaDatabase.openEncrypted(path, keyHex: 'trop-court'),
        throwsArgumentError,
      );
    });
  });

  group('Magasin SQLite', () {
    late Directory directory;
    late Database db;
    late SqliteAkibaStore store;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('akiba_store');
      db = AkibaDatabase.openEncrypted(
        p.join(directory.path, 'akiba.db'),
        keyHex: AkibaSecureKey.generateHexKey(),
      );
      store = SqliteAkibaStore(db);
    });

    tearDown(() {
      db.close();
      directory.deleteSync(recursive: true);
    });

    test('les soldes sont dérivés des transactions', () async {
      await store.saveAccount(
        Account(
          id: 'flooz',
          name: 'Flooz',
          brand: AccountBrand.flooz,
          createdAt: now,
        ),
      );
      await store.saveAccount(
        Account(
          id: 'cash',
          name: 'Liquide',
          brand: AccountBrand.liquide,
          createdAt: now,
        ),
      );

      await store.saveTransaction(
        _tx('open-flooz', 'flooz', 25000, TransactionKind.opening, now),
      );
      await store.saveTransaction(
        _tx('open-cash', 'cash', 8000, TransactionKind.opening, now),
      );
      await store.saveTransaction(
        _tx('income', 'flooz', 10000, TransactionKind.income, now),
      );
      await store.saveTransaction(
        _tx(
          'expense',
          'flooz',
          -3500,
          TransactionKind.expense,
          now,
          category: 'Transport',
        ),
      );

      final DashboardSnapshot snapshot = await store.loadDashboard();

      expect(snapshot.balance.totalAccounts, 39500);
      expect(snapshot.accounts.length, 2);
      // Les soldes d'ouverture ne polluent pas la liste des mouvements.
      expect(snapshot.recent.length, 2);
      expect(snapshot.recent.first.transaction.category, 'Transport');
    });

    test('l’argent de tiers est isolé du solde disponible', () async {
      await store.saveAccount(
        Account(
          id: 'flooz',
          name: 'Flooz',
          brand: AccountBrand.flooz,
          createdAt: now,
        ),
      );
      await store.saveThirdParty(
        ThirdParty(id: 'client', name: 'Client Ama', createdAt: now),
      );
      await store.saveTransaction(
        _tx('open', 'flooz', 20000, TransactionKind.opening, now),
      );
      await store.saveTransaction(
        _tx(
          'tiers-in',
          'flooz',
          50000,
          TransactionKind.income,
          now,
          neutral: true,
          thirdPartyId: 'client',
        ),
      );
      await store.saveTransaction(
        _tx(
          'tiers-out',
          'flooz',
          -20000,
          TransactionKind.expense,
          now,
          neutral: true,
          thirdPartyId: 'client',
        ),
      );

      final DashboardSnapshot snapshot = await store.loadDashboard();

      expect(snapshot.balance.thirdPartyHeld, 30000);
      expect(snapshot.balance.totalAccounts, 50000);
      expect(snapshot.balance.available, 20000);
      // La dépense neutre reste hors du budget du mois.
      expect(snapshot.balance.monthExpense, 0);
    });

    test('un versement au coffre ne change pas le solde disponible', () async {
      await store.saveAccount(
        Account(
          id: 'flooz',
          name: 'Flooz',
          brand: AccountBrand.flooz,
          createdAt: now,
        ),
      );
      await store.saveSavingsPot(
        SavingsPot(
          id: 'pot',
          name: 'Fonds d’urgence',
          kind: SavingsKind.emergency,
          createdAt: now,
        ),
      );
      await store.saveTransaction(
        _tx('open', 'flooz', 30000, TransactionKind.opening, now),
      );
      await store.saveTransaction(
        _tx(
          'versement',
          'flooz',
          -10000,
          TransactionKind.savings,
          now,
          savingsPotId: 'pot',
        ),
      );

      final DashboardSnapshot snapshot = await store.loadDashboard();

      expect(snapshot.balance.totalAccounts, 20000);
      expect(snapshot.balance.savingsHeld, 10000);
      expect(snapshot.balance.available, 30000);
    });

    test('les quatre comptes par défaut ne sont créés qu’une fois', () async {
      await store.ensureDefaultAccounts();
      await store.ensureDefaultAccounts();

      final List<Account> accounts = await store.accounts();
      expect(accounts.length, 4);
      expect(
        accounts.map((Account a) => a.brand).toSet(),
        AccountBrand.values.toSet(),
      );
    });

    test('le budget suit les seuils et ignore l’argent de tiers', () async {
      await store.saveAccount(
        Account(
          id: 'flooz',
          name: 'Flooz',
          brand: AccountBrand.flooz,
          createdAt: now,
        ),
      );
      await store.saveBudget(
        Budget(
          id: 'b1',
          category: 'Transport',
          monthlyLimit: 10000,
          createdAt: now,
        ),
      );
      await store.saveTransaction(
        _tx(
          'expense',
          'flooz',
          -8500,
          TransactionKind.expense,
          now,
          category: 'Transport',
        ),
      );
      await store.saveTransaction(
        _tx(
          'neutral',
          'flooz',
          -9000,
          TransactionKind.expense,
          now,
          category: 'Transport',
          neutral: true,
        ),
      );

      final List<BudgetStatus> statuses = await store.budgets(month: now);

      expect(statuses.single.spent, 8500);
      expect(statuses.single.level, BudgetLevel.warning);
      expect(statuses.single.isExceeded, isFalse);
    });

    test('supprimer un transfert retire ses deux écritures', () async {
      for (final String id in <String>['a', 'b']) {
        await store.saveAccount(
          Account(
            id: id,
            name: id.toUpperCase(),
            brand: AccountBrand.liquide,
            createdAt: now,
          ),
        );
      }
      await store.saveTransaction(
        _tx('open', 'a', 20000, TransactionKind.opening, now),
      );
      final TransactionRecord out = TransactionRecord(
        id: 'tr-out',
        accountId: 'a',
        amount: -5000,
        kind: TransactionKind.transfer,
        occurredAt: now,
        createdAt: now,
        transferAccountId: 'b',
      );
      await store.saveTransaction(out);
      await store.saveTransaction(
        TransactionRecord(
          id: 'tr-in',
          accountId: 'b',
          amount: 5000,
          kind: TransactionKind.transfer,
          occurredAt: now,
          createdAt: now,
          transferAccountId: 'a',
        ),
      );

      await store.deleteTransaction(out);

      final List<TransactionRecord> left = await store.transactions();
      expect(
        left.where((TransactionRecord t) => t.kind == TransactionKind.transfer),
        isEmpty,
      );
      final List<AccountBalance> balances = await store.accountBalances();
      expect(
        balances.firstWhere((AccountBalance b) => b.account.id == 'b').balance,
        0,
      );
    });

    test('les coffres et les tiers exposent leurs montants', () async {
      await store.saveAccount(
        Account(
          id: 'flooz',
          name: 'Flooz',
          brand: AccountBrand.flooz,
          createdAt: now,
        ),
      );
      await store.saveSavingsPot(
        SavingsPot(
          id: 'pot',
          name: 'Voyage',
          kind: SavingsKind.goal,
          targetAmount: 100000,
          createdAt: now,
        ),
      );
      await store.saveThirdParty(
        ThirdParty(id: 'client', name: 'Client Ama', createdAt: now),
      );
      await store.saveTransaction(
        _tx(
          'versement',
          'flooz',
          -5000,
          TransactionKind.savings,
          now,
          savingsPotId: 'pot',
        ),
      );
      await store.saveTransaction(
        _tx(
          'avance',
          'flooz',
          30000,
          TransactionKind.income,
          now,
          neutral: true,
          thirdPartyId: 'client',
        ),
      );
      await store.saveTransaction(
        _tx(
          'reversement',
          'flooz',
          -10000,
          TransactionKind.expense,
          now,
          neutral: true,
          thirdPartyId: 'client',
        ),
      );

      final List<SavingsPotBalance> pots = await store.savingsBalances();
      final List<ThirdPartyBalance> parties = await store.thirdPartyBalances();

      expect(pots.single.held, 5000);
      expect(pots.single.ratio, closeTo(0.05, 0.0001));
      expect(parties.single.name, 'Client Ama');
      expect(parties.single.held, 20000);
    });

    test('les mouvements se filtrent par période', () async {
      await store.saveAccount(
        Account(
          id: 'flooz',
          name: 'Flooz',
          brand: AccountBrand.flooz,
          createdAt: now,
        ),
      );
      await store.saveTransaction(
        _tx(
          'octobre',
          'flooz',
          -1000,
          TransactionKind.expense,
          DateTime(2026, 10, 5),
        ),
      );
      await store.saveTransaction(
        _tx(
          'novembre',
          'flooz',
          -2000,
          TransactionKind.expense,
          DateTime(2026, 11, 5),
        ),
      );

      final List<TransactionLine> october = await store.movements(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 11, 1),
      );
      final List<TransactionLine> november = await store.movements(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 12, 1),
      );

      expect(october.length, 1);
      expect(october.single.transaction.id, 'octobre');
      expect(november.length, 1);
      expect(november.single.transaction.id, 'novembre');
    });

    test('les statistiques excluent l’argent de tiers et l’épargne', () async {
      await store.saveAccount(
        Account(
          id: 'flooz',
          name: 'Flooz',
          brand: AccountBrand.flooz,
          createdAt: now,
        ),
      );
      await store.saveSavingsPot(
        SavingsPot(
          id: 'pot',
          name: 'Coffre',
          kind: SavingsKind.free,
          createdAt: now,
        ),
      );
      await store.saveTransaction(
        _tx(
          'depense',
          'flooz',
          -3000,
          TransactionKind.expense,
          now,
          category: 'Transport',
        ),
      );
      await store.saveTransaction(
        _tx(
          'salaire',
          'flooz',
          10000,
          TransactionKind.income,
          now,
          category: 'Salaire',
        ),
      );
      await store.saveTransaction(
        _tx(
          'tiers',
          'flooz',
          -5000,
          TransactionKind.expense,
          now,
          neutral: true,
        ),
      );
      await store.saveTransaction(
        _tx(
          'epargne',
          'flooz',
          -2000,
          TransactionKind.savings,
          now,
          savingsPotId: 'pot',
        ),
      );

      final List<CategoryTotal> expenses = await store.categoryTotals(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 12, 1),
      );
      final List<CategoryTotal> incomes = await store.categoryTotals(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 12, 1),
        expenses: false,
      );
      final List<AccountPeriodTotal> accounts = await store.accountTotals(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 12, 1),
      );

      expect(expenses.single.label, 'Transport');
      expect(expenses.single.amount, 3000);
      expect(incomes.single.amount, 10000);
      expect(accounts.single.expense, 3000);
      expect(accounts.single.income, 10000);
    });

    test('les bilans mensuels isolent l’argent de tiers', () async {
      await store.saveAccount(
        Account(
          id: 'flooz',
          name: 'Flooz',
          brand: AccountBrand.flooz,
          createdAt: now,
        ),
      );
      await store.saveTransaction(
        _tx(
          'depense',
          'flooz',
          -4000,
          TransactionKind.expense,
          now,
          category: 'Transport',
        ),
      );
      await store.saveTransaction(
        _tx(
          'tiers-in',
          'flooz',
          50000,
          TransactionKind.income,
          now,
          neutral: true,
        ),
      );
      await store.saveTransaction(
        _tx(
          'tiers-out',
          'flooz',
          -20000,
          TransactionKind.expense,
          now,
          neutral: true,
        ),
      );

      final List<MonthTotal> months = await store.monthlyTotals(
        months: 2,
        reference: now,
      );

      expect(months.first.expense, 4000);
      expect(months.first.income, 0);
      expect(months.first.neutralIn, 50000);
      expect(months.first.neutralOut, 20000);
      expect(months.first.hasNeutral, isTrue);
    });

    test('les besoins se gèrent et la réserve se lit', () async {
      await store.saveNeed(
        Need(
          id: 'n1',
          label: 'Loyer',
          amount: 75000,
          priority: NeedPriority.high,
          createdAt: now,
        ),
      );
      await store.setSetting('reserve_securite', '25000');

      final List<Need> needs = await store.needs();
      expect(needs.single.label, 'Loyer');
      expect(needs.single.priority, NeedPriority.high);
      expect(await store.settingInt('reserve_securite'), 25000);
      expect(await store.settingInt('inconnu', fallback: 1000), 1000);

      await store.saveNeed(needs.single.copyWith(isSettled: true));
      expect((await store.needs()).single.isSettled, isTrue);

      await store.deleteNeed('n1');
      expect(await store.needs(), isEmpty);
    });

    test('créances, dettes et réglages sont persistés', () async {
      await store.saveDebt(
        Debt(
          id: 'd1',
          direction: DebtDirection.owedToMe,
          counterparty: 'Ama',
          principal: 20000,
          settledAmount: 5000,
          createdAt: now,
        ),
      );
      await store.setSetting('montants_masques', '1');

      final List<Debt> debts = await store.debts();
      expect(debts.single.remaining, 15000);
      expect(await store.setting('montants_masques'), '1');
      expect(await store.setting('inconnu'), isNull);
    });
  });
}

TransactionRecord _tx(
  String id,
  String accountId,
  int amount,
  TransactionKind kind,
  DateTime at, {
  String? category,
  bool neutral = false,
  String? thirdPartyId,
  String? savingsPotId,
}) {
  return TransactionRecord(
    id: id,
    accountId: accountId,
    amount: amount,
    kind: kind,
    category: category,
    occurredAt: at,
    createdAt: at,
    isNeutral: neutral,
    thirdPartyId: thirdPartyId,
    savingsPotId: savingsPotId,
  );
}
