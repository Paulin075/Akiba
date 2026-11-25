import 'package:sqlite3/sqlite3.dart';

import 'akiba_store.dart';
import 'balance_summary.dart';
import 'models/account.dart';
import 'models/account_brand.dart';
import 'models/analysis.dart';
import 'models/budget.dart';
import 'models/debt.dart';
import 'models/need.dart';
import 'models/savings_pot.dart';
import 'models/third_party.dart';
import 'models/transaction_record.dart';

/// Implémentation SQLite (base chiffrée) du magasin AKIBA.
///
/// Aucun solde n'est écrit : la vue `v_account_balances` et les sommes de
/// transactions produisent tous les totaux à la lecture.
class SqliteAkibaStore implements AkibaStore {
  SqliteAkibaStore(this._db);

  final Database _db;

  static const String _accountColumns =
      'id, name, brand, is_archived, created_at';

  @override
  Future<DashboardSnapshot> loadDashboard({int recentLimit = 5}) async {
    final List<AccountBalance> balances = await _accountBalances();

    final int accountsTotal = balances.fold<int>(
      0,
      (int sum, AccountBalance item) => sum + item.balance,
    );

    final int savingsSum = _sum(
      'SELECT COALESCE(SUM(amount), 0) AS v FROM transactions '
      "WHERE kind = 'savings'",
    );
    final int neutralSum = _sum(
      'SELECT COALESCE(SUM(amount), 0) AS v FROM transactions '
      'WHERE is_neutral = 1',
    );

    final (String start, String end) = _monthBounds(DateTime.now());
    final Row month = _db
        .select(
          '''
          SELECT
            COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) AS income,
            COALESCE(SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END), 0) AS expense
          FROM transactions
          WHERE is_neutral = 0
            AND kind IN ('income', 'expense')
            AND occurred_at >= ?
            AND occurred_at < ?
          ''',
          <Object?>[start, end],
        )
        .first;

    return DashboardSnapshot(
      balance: BalanceSummary.fromSums(
        accountsTotal: accountsTotal,
        savingsTransfersSum: savingsSum,
        neutralSum: neutralSum,
        monthIncome: _int(month['income']),
        monthExpense: _int(month['expense']),
      ),
      accounts: balances,
      recent: await _recent(recentLimit),
    );
  }

  @override
  Future<List<AccountBalance>> accountBalances() => _accountBalances();

  @override
  Future<List<Account>> accounts() async {
    final ResultSet rows = _db.select(
      'SELECT $_accountColumns FROM accounts '
      'WHERE is_archived = 0 ORDER BY name COLLATE NOCASE',
    );
    return rows.map(_accountFrom).toList(growable: false);
  }

  @override
  Future<List<TransactionRecord>> transactions({int limit = 50}) async {
    final ResultSet rows = _db.select(
      'SELECT * FROM transactions ORDER BY occurred_at DESC, created_at DESC '
      'LIMIT ?',
      <Object?>[limit],
    );
    return rows.map(_transactionFrom).toList(growable: false);
  }

  @override
  Future<List<SavingsPot>> savingsPots() async {
    final ResultSet rows = _db.select(
      'SELECT * FROM savings_pots WHERE is_archived = 0 '
      'ORDER BY created_at',
    );
    return rows
        .map((Row row) => SavingsPot.fromRow(_map(row)))
        .toList(growable: false);
  }

  @override
  Future<List<ThirdParty>> thirdParties() async {
    final ResultSet rows = _db.select(
      'SELECT * FROM third_parties ORDER BY name COLLATE NOCASE',
    );
    return rows
        .map((Row row) => ThirdParty.fromRow(_map(row)))
        .toList(growable: false);
  }

  @override
  Future<List<SavingsPotBalance>> savingsBalances() async {
    final ResultSet rows = _db.select('''
      SELECT
        p.*,
        COALESCE(
          SUM(CASE WHEN t.kind = 'savings' THEN -t.amount ELSE 0 END),
          0
        ) AS held
      FROM savings_pots p
      LEFT JOIN transactions t ON t.savings_pot_id = p.id
      WHERE p.is_archived = 0
      GROUP BY p.id
      ORDER BY p.created_at
    ''');
    return rows
        .map(
          (Row row) => SavingsPotBalance(
            pot: SavingsPot.fromRow(_map(row)),
            held: _int(row['held']),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ThirdPartyBalance>> thirdPartyBalances() async {
    final ResultSet rows = _db.select('''
      SELECT
        tp.id AS id,
        COALESCE(tp.name, 'Sans nom') AS name,
        COALESCE(SUM(t.amount), 0) AS held
      FROM transactions t
      LEFT JOIN third_parties tp ON tp.id = t.third_party_id
      WHERE t.is_neutral = 1
      GROUP BY tp.id
      ORDER BY held DESC
    ''');
    return rows
        .map(
          (Row row) => ThirdPartyBalance(
            id: row['id'] as String?,
            name: row['name']! as String,
            held: _int(row['held']),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<TransactionLine>> movements({
    int limit = 200,
    DateTime? from,
    DateTime? to,
  }) async {
    final StringBuffer sql = StringBuffer('''
      SELECT
        t.*,
        a.id AS a_id,
        a.name AS a_name,
        a.brand AS a_brand,
        a.is_archived AS a_is_archived,
        a.created_at AS a_created_at
      FROM transactions t
      JOIN accounts a ON a.id = t.account_id
      WHERE t.kind <> 'opening'
    ''');
    final List<Object?> arguments = <Object?>[];

    if (from != null) {
      sql.write('AND t.occurred_at >= ? ');
      arguments.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      sql.write('AND t.occurred_at < ? ');
      arguments.add(to.toUtc().toIso8601String());
    }

    sql.write('ORDER BY t.occurred_at DESC, t.created_at DESC, t.id LIMIT ?');
    arguments.add(limit);

    return _db
        .select(sql.toString(), arguments)
        .map(_lineFrom)
        .toList(growable: false);
  }

  @override
  Future<List<CategoryTotal>> categoryTotals({
    required DateTime from,
    required DateTime to,
    bool expenses = true,
  }) async {
    final String aggregate = expenses ? 'SUM(-amount)' : 'SUM(amount)';
    final String signFilter = expenses ? 'amount < 0' : 'amount > 0';

    final ResultSet rows = _db.select(
      '''
      SELECT
        COALESCE(NULLIF(TRIM(category), ''), 'Sans catégorie') AS label,
        COALESCE($aggregate, 0) AS total
      FROM transactions
      WHERE is_neutral = 0
        AND kind = ?
        AND $signFilter
        AND occurred_at >= ?
        AND occurred_at < ?
      GROUP BY label
      ORDER BY total DESC
      ''',
      <Object?>[expenses ? 'expense' : 'income', _iso(from), _iso(to)],
    );
    return rows
        .map(
          (Row row) => CategoryTotal(
            label: row['label']! as String,
            amount: _int(row['total']),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<AccountPeriodTotal>> accountTotals({
    required DateTime from,
    required DateTime to,
  }) async {
    final ResultSet rows = _db.select(
      '''
      SELECT
        a.id AS id,
        a.name AS name,
        a.brand AS brand,
        a.is_archived AS is_archived,
        a.created_at AS created_at,
        COALESCE(
          SUM(CASE WHEN t.amount > 0 THEN t.amount ELSE 0 END),
          0
        ) AS income,
        COALESCE(
          SUM(CASE WHEN t.amount < 0 THEN -t.amount ELSE 0 END),
          0
        ) AS expense
      FROM accounts a
      LEFT JOIN transactions t ON t.account_id = a.id
        AND t.is_neutral = 0
        AND t.kind IN ('income', 'expense')
        AND t.occurred_at >= ?
        AND t.occurred_at < ?
      WHERE a.is_archived = 0
      GROUP BY a.id
      ORDER BY a.name COLLATE NOCASE
      ''',
      <Object?>[_iso(from), _iso(to)],
    );

    return rows
        .map(
          (Row row) => AccountPeriodTotal(
            account: _accountFrom(row),
            income: _int(row['income']),
            expense: _int(row['expense']),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<MonthTotal>> monthlyTotals({
    int months = 6,
    DateTime? reference,
  }) async {
    final DateTime anchor = reference ?? DateTime.now();
    final List<MonthTotal> totals = <MonthTotal>[];

    for (int index = 0; index < months; index++) {
      final DateTime start = DateTime(anchor.year, anchor.month - index);
      final DateTime end = DateTime(anchor.year, anchor.month - index + 1);
      final Row row = _db
          .select(
            '''
            SELECT
              COALESCE(SUM(CASE WHEN is_neutral = 0 AND kind = 'income'
                THEN amount ELSE 0 END), 0) AS income,
              COALESCE(SUM(CASE WHEN is_neutral = 0 AND kind = 'expense'
                THEN -amount ELSE 0 END), 0) AS expense,
              COALESCE(SUM(CASE WHEN is_neutral = 1 AND amount > 0
                THEN amount ELSE 0 END), 0) AS neutral_in,
              COALESCE(SUM(CASE WHEN is_neutral = 1 AND amount < 0
                THEN -amount ELSE 0 END), 0) AS neutral_out
            FROM transactions
            WHERE occurred_at >= ?
              AND occurred_at < ?
            ''',
            <Object?>[_iso(start), _iso(end)],
          )
          .first;

      totals.add(
        MonthTotal(
          year: start.year,
          month: start.month,
          income: _int(row['income']),
          expense: _int(row['expense']),
          neutralIn: _int(row['neutral_in']),
          neutralOut: _int(row['neutral_out']),
        ),
      );
    }

    return totals;
  }

  @override
  Future<List<Need>> needs() async {
    final ResultSet rows = _db.select('''
      SELECT * FROM needs
      ORDER BY is_settled, priority, created_at DESC
    ''');
    return rows
        .map((Row row) => Need.fromRow(_map(row)))
        .toList(growable: false);
  }

  @override
  Future<void> saveNeed(Need need) async {
    _db.execute(
      '''
      INSERT INTO needs (
        id, label, amount, priority, due_date, is_settled, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        label = excluded.label,
        amount = excluded.amount,
        priority = excluded.priority,
        due_date = excluded.due_date,
        is_settled = excluded.is_settled
      ''',
      <Object?>[
        need.id,
        need.label,
        need.amount,
        need.priority.value,
        need.dueDate == null ? null : _iso(need.dueDate!),
        need.isSettled ? 1 : 0,
        _iso(need.createdAt),
      ],
    );
  }

  @override
  Future<void> deleteNeed(String id) async {
    _db.execute('DELETE FROM needs WHERE id = ?', <Object?>[id]);
  }

  @override
  Future<List<Debt>> debts() async {
    final ResultSet rows = _db.select(
      'SELECT * FROM debts ORDER BY created_at DESC',
    );
    return rows
        .map((Row row) => Debt.fromRow(_map(row)))
        .toList(growable: false);
  }

  @override
  Future<void> saveAccount(Account account) async {
    _db.execute(
      '''
      INSERT INTO accounts ($_accountColumns)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        brand = excluded.brand,
        is_archived = excluded.is_archived
      ''',
      <Object?>[
        account.id,
        account.name,
        account.brand.name,
        account.archived ? 1 : 0,
        account.createdAt.toUtc().toIso8601String(),
      ],
    );
  }

  @override
  Future<void> saveTransaction(TransactionRecord transaction) async {
    _db.execute(
      '''
      INSERT INTO transactions (
        id, account_id, amount, kind, category, note, occurred_at,
        is_neutral, third_party_id, transfer_account_id, savings_pot_id,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        account_id = excluded.account_id,
        amount = excluded.amount,
        kind = excluded.kind,
        category = excluded.category,
        note = excluded.note,
        occurred_at = excluded.occurred_at,
        is_neutral = excluded.is_neutral,
        third_party_id = excluded.third_party_id,
        transfer_account_id = excluded.transfer_account_id,
        savings_pot_id = excluded.savings_pot_id
      ''',
      <Object?>[
        transaction.id,
        transaction.accountId,
        transaction.amount,
        transaction.kind.name,
        transaction.category,
        transaction.note,
        transaction.occurredAt.toUtc().toIso8601String(),
        transaction.isNeutral ? 1 : 0,
        transaction.thirdPartyId,
        transaction.transferAccountId,
        transaction.savingsPotId,
        transaction.createdAt.toUtc().toIso8601String(),
      ],
    );
  }

  @override
  Future<void> saveSavingsPot(SavingsPot pot) async {
    _db.execute(
      '''
      INSERT INTO savings_pots (
        id, name, kind, target_amount, target_date, is_archived, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        kind = excluded.kind,
        target_amount = excluded.target_amount,
        target_date = excluded.target_date,
        is_archived = excluded.is_archived
      ''',
      <Object?>[
        pot.id,
        pot.name,
        pot.kind.name,
        pot.targetAmount,
        pot.targetDate?.toUtc().toIso8601String(),
        pot.archived ? 1 : 0,
        pot.createdAt.toUtc().toIso8601String(),
      ],
    );
  }

  @override
  Future<void> saveThirdParty(ThirdParty thirdParty) async {
    _db.execute(
      '''
      INSERT INTO third_parties (id, name, note, created_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        note = excluded.note
      ''',
      <Object?>[
        thirdParty.id,
        thirdParty.name,
        thirdParty.note,
        thirdParty.createdAt.toUtc().toIso8601String(),
      ],
    );
  }

  @override
  Future<void> saveDebt(Debt debt) async {
    _db.execute(
      '''
      INSERT INTO debts (
        id, direction, counterparty, principal, settled_amount,
        due_date, note, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        direction = excluded.direction,
        counterparty = excluded.counterparty,
        principal = excluded.principal,
        settled_amount = excluded.settled_amount,
        due_date = excluded.due_date,
        note = excluded.note
      ''',
      <Object?>[
        debt.id,
        debt.direction.name,
        debt.counterparty,
        debt.principal,
        debt.settledAmount,
        debt.dueDate?.toUtc().toIso8601String(),
        debt.note,
        debt.createdAt.toUtc().toIso8601String(),
      ],
    );
  }

  @override
  Future<TransactionRecord> settleDebt(
    Debt debt, {
    required int amount,
    required String accountId,
  }) async {
    final int remaining = debt.remaining;
    if (remaining <= 0) {
      throw StateError('Cette créance ou dette est déjà soldée.');
    }
    final int settled = amount < remaining ? amount : remaining;
    if (settled <= 0) {
      throw StateError('Le montant du règlement doit être supérieur à zéro.');
    }
    final bool received = debt.direction == DebtDirection.owedToMe;
    final DateTime now = DateTime.now();
    final TransactionRecord movement = TransactionRecord(
      id: 'debt-${debt.id}-${now.microsecondsSinceEpoch}',
      accountId: accountId,
      amount: received ? settled : -settled,
      kind: received ? TransactionKind.income : TransactionKind.expense,
      // Catégorie explicite : le règlement apparaît dans les analyses sans
      // être confondu avec un salaire ou une dépense de la vie courante.
      category: received ? 'Créance' : 'Dette',
      note: received
          ? 'Créance encaissée · ${debt.counterparty}'
          : 'Dette remboursée · ${debt.counterparty}',
      isNeutral: false,
      occurredAt: now,
      createdAt: now,
    );
    await saveTransaction(movement);
    await saveDebt(
      Debt(
        id: debt.id,
        direction: debt.direction,
        counterparty: debt.counterparty,
        principal: debt.principal,
        settledAmount: debt.settledAmount + settled,
        dueDate: debt.dueDate,
        note: debt.note,
        createdAt: debt.createdAt,
      ),
    );
    return movement;
  }

  @override
  Future<void> deleteDebt(String id) async {
    _db.execute('DELETE FROM debts WHERE id = ?', <Object?>[id]);
  }

  @override
  Future<List<BudgetStatus>> budgets({DateTime? month}) async {
    final (String start, String end) = _monthBounds(month ?? DateTime.now());
    final ResultSet rows = _db.select(
      'SELECT * FROM budgets ORDER BY category COLLATE NOCASE',
    );

    final List<BudgetStatus> statuses = <BudgetStatus>[];
    for (final Row row in rows) {
      final Budget budget = Budget.fromRow(_map(row));
      final int spent = _int(
        _db
            .select(
              '''
                  SELECT COALESCE(SUM(-amount), 0) AS v
                  FROM transactions
                  WHERE category = ?
                    AND amount < 0
                    AND is_neutral = 0
                    AND kind = 'expense'
                    AND occurred_at >= ?
                    AND occurred_at < ?
                  ''',
              <Object?>[budget.category, start, end],
            )
            .first['v'],
      );
      statuses.add(BudgetStatus(budget: budget, spent: spent));
    }
    return statuses;
  }

  @override
  Future<void> saveBudget(Budget budget) async {
    _db.execute('DELETE FROM budgets WHERE category = ?', <Object?>[
      budget.category,
    ]);
    _db.execute(
      '''
      INSERT INTO budgets (id, category, monthly_limit, created_at)
      VALUES (?, ?, ?, ?)
      ''',
      <Object?>[
        budget.id,
        budget.category,
        budget.monthlyLimit,
        budget.createdAt.toUtc().toIso8601String(),
      ],
    );
  }

  @override
  Future<void> deleteBudget(String id) async {
    _db.execute('DELETE FROM budgets WHERE id = ?', <Object?>[id]);
  }

  @override
  Future<void> deleteTransaction(TransactionRecord transaction) async {
    _db.execute('DELETE FROM transactions WHERE id = ?', <Object?>[
      transaction.id,
    ]);

    if (transaction.kind == TransactionKind.transfer &&
        transaction.transferAccountId != null) {
      // Le transfert est écrit en deux lignes symétriques : la suppression de
      // l'une doit retirer l'autre, sinon le total des comptes dérive.
      _db.execute(
        '''
        DELETE FROM transactions
        WHERE kind = 'transfer'
          AND account_id = ?
          AND transfer_account_id = ?
          AND occurred_at = ?
        ''',
        <Object?>[
          transaction.transferAccountId,
          transaction.accountId,
          transaction.occurredAt.toUtc().toIso8601String(),
        ],
      );
    }
  }

  @override
  Future<void> ensureDefaultAccounts() async {
    final ResultSet rows = _db.select('SELECT COUNT(*) AS v FROM accounts');
    if (_int(rows.first['v']) > 0) return;

    final DateTime now = DateTime.now();
    for (final (String id, String name, AccountBrand brand)
        in _defaultAccounts) {
      await saveAccount(
        Account(id: id, name: name, brand: brand, createdAt: now),
      );
    }
  }

  @override
  Future<int> settingInt(String key, {int fallback = 0}) async {
    final String? value = await setting(key);
    if (value == null) return fallback;
    return int.tryParse(value) ?? fallback;
  }

  @override
  Future<String?> setting(String key) async {
    final ResultSet rows = _db.select(
      'SELECT value FROM settings WHERE key = ?',
      <Object?>[key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value']! as String;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    _db.execute(
      '''
      INSERT INTO settings (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''',
      <Object?>[key, value],
    );
  }

  Future<List<AccountBalance>> _accountBalances() async {
    final ResultSet rows = _db.select(
      'SELECT * FROM v_account_balances WHERE is_archived = 0 '
      'ORDER BY name COLLATE NOCASE',
    );
    return rows
        .map(
          (Row row) => AccountBalance(
            account: _accountFrom(row),
            balance: _int(row['balance']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<TransactionLine>> _recent(int limit) => movements(limit: limit);

  static TransactionLine _lineFrom(Row row) => TransactionLine(
    transaction: _transactionFrom(row),
    account: Account(
      id: row['a_id']! as String,
      name: row['a_name']! as String,
      brand: AccountBrand.fromStorage(row['a_brand']! as String),
      archived: (row['a_is_archived']! as int) != 0,
      createdAt: DateTime.parse(row['a_created_at']! as String),
    ),
  );

  static const List<(String, String, AccountBrand)> _defaultAccounts =
      <(String, String, AccountBrand)>[
        ('liquide', 'Liquide', AccountBrand.liquide),
        ('flooz', 'Flooz', AccountBrand.flooz),
        ('mixx', 'Mixx by Yas', AccountBrand.mixxByYas),
        ('orabank', 'Orabank', AccountBrand.orabank),
      ];

  int _sum(String sql) {
    final ResultSet rows = _db.select(sql);
    if (rows.isEmpty) return 0;
    return _int(rows.first['v']);
  }

  static Account _accountFrom(Row row) => Account(
    id: row['id']! as String,
    name: row['name']! as String,
    brand: AccountBrand.fromStorage(row['brand']! as String),
    archived: (row['is_archived']! as int) != 0,
    createdAt: DateTime.parse(row['created_at']! as String),
  );

  static TransactionRecord _transactionFrom(Row row) =>
      TransactionRecord.fromRow(_map(row));

  static Map<String, Object?> _map(Row row) => Map<String, Object?>.from(row);

  static int _int(Object? value) => value is int ? value : 0;

  static String _iso(DateTime date) => date.toUtc().toIso8601String();

  /// Bornes ISO du mois calendaire courant, converties en UTC.
  static (String, String) _monthBounds(DateTime now) {
    final DateTime start = DateTime(now.year, now.month);
    final DateTime end = DateTime(now.year, now.month + 1);
    return (start.toUtc().toIso8601String(), end.toUtc().toIso8601String());
  }
}
