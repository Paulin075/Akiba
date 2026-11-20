import 'dart:math';

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

/// Jeu de données fictives **complètes**, en mémoire et isolées.
///
/// Le mode simulation ne touche jamais la base réelle : ce magasin vit dans un
/// objet séparé, avec ses propres comptes, mouvements, budgets, coffres,
/// créances et dettes en FCFA. Quitter le mode simulation suffit à retrouver
/// les vraies données intactes.
class SimulationAkibaStore implements AkibaStore {
  SimulationAkibaStore({DateTime? now}) : _now = now ?? DateTime.now() {
    _seed(_now);
  }

  final DateTime _now;

  final List<Account> _accounts = <Account>[];
  final List<TransactionRecord> _transactions = <TransactionRecord>[];
  final List<SavingsPot> _pots = <SavingsPot>[];
  final List<ThirdParty> _parties = <ThirdParty>[];
  final List<Debt> _debts = <Debt>[];
  final List<Budget> _budgets = <Budget>[];
  final List<Need> _needs = <Need>[];
  final Map<String, String> _settings = <String, String>{
    'simulation_mode': '1',
    'first_name': 'Akouvi',
    'last_name': 'Kossi',
    'currency': 'FCFA',
    'reserve_securite': '50000',
    'savings_goal_percent': '15',
  };

  int _counter = 0;

  String _id(String prefix) => '$prefix-sim-${_counter++}';

  void _add(
    DateTime when,
    Account account,
    int amount,
    TransactionKind kind, {
    String? category,
    String? note,
    bool neutral = false,
    String? thirdPartyId,
    String? transferAccountId,
    String? savingsPotId,
  }) {
    _transactions.add(
      TransactionRecord(
        id: _id('tx'),
        accountId: account.id,
        amount: amount,
        kind: kind,
        category: category,
        note: note,
        occurredAt: when,
        createdAt: when,
        isNeutral: neutral,
        thirdPartyId: thirdPartyId,
        transferAccountId: transferAccountId,
        savingsPotId: savingsPotId,
      ),
    );
  }

  void _seed(DateTime now) {
    final DateTime start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 80));

    _accounts.addAll(<Account>[
      Account(
        id: 'sim-liquide',
        name: 'Liquide',
        brand: AccountBrand.liquide,
        createdAt: start,
      ),
      Account(
        id: 'sim-flooz',
        name: 'Flooz',
        brand: AccountBrand.flooz,
        createdAt: start,
      ),
      Account(
        id: 'sim-mixx',
        name: 'Mixx by Yas',
        brand: AccountBrand.mixxByYas,
        createdAt: start,
      ),
      Account(
        id: 'sim-orabank',
        name: 'Orabank',
        brand: AccountBrand.orabank,
        createdAt: start,
      ),
    ]);

    final Account cash = _accounts[0];
    final Account flooz = _accounts[1];
    final Account mixx = _accounts[2];
    final Account bank = _accounts[3];

    // Soldes d'ouverture (aucun solde n'est stocké ailleurs).
    _add(start, cash, 60000, TransactionKind.opening, note: 'Solde de départ');
    _add(start, flooz, 95000, TransactionKind.opening, note: 'Solde de départ');
    _add(start, mixx, 40000, TransactionKind.opening, note: 'Solde de départ');
    _add(start, bank, 480000, TransactionKind.opening, note: 'Solde de départ');

    final ThirdParty client = ThirdParty(
      id: 'sim-client',
      name: 'Client Kafui',
      note: 'Argent à reverser',
      createdAt: start,
    );
    final ThirdParty tontine = ThirdParty(
      id: 'sim-tontine',
      name: 'Tontine du quartier',
      createdAt: start,
    );
    _parties.addAll(<ThirdParty>[client, tontine]);

    final SavingsPot urgence = SavingsPot(
      id: 'sim-pot-urgence',
      name: 'Fonds d’urgence',
      kind: SavingsKind.emergency,
      targetAmount: 300000,
      createdAt: start,
    );
    final SavingsPot moto = SavingsPot(
      id: 'sim-pot-moto',
      name: 'Moto',
      kind: SavingsKind.goal,
      targetAmount: 450000,
      targetDate: DateTime(now.year + 1, 3, 1),
      createdAt: start,
    );
    final SavingsPot ecran = SavingsPot(
      id: 'sim-pot-ecran',
      name: 'Moniteur pour le bureau',
      kind: SavingsKind.goal,
      targetAmount: 120000,
      createdAt: start,
    );
    _pots.addAll(<SavingsPot>[urgence, moto, ecran]);

    final Random random = Random(20261120);
    const List<String> food = <String>[
      'Provisions au marché',
      'Déjeuner au maquis',
      'Petit-déjeuner',
      'Riz et huile',
      'Poisson chez la vendeuse',
    ];
    const List<String> transport = <String>[
      'Zémidjan',
      'Taxi',
      'Carburant',
      'Trajet Cotonou',
    ];

    for (int day = 1; day <= 78; day++) {
      final DateTime when = start.add(Duration(days: day));
      final bool sunday = when.weekday == DateTime.sunday;

      _add(
        when.add(const Duration(hours: 7, minutes: 40)),
        cash,
        -(1200 + random.nextInt(2800)),
        TransactionKind.expense,
        category: 'Alimentation',
        note: food[random.nextInt(food.length)],
      );
      if (!sunday) {
        _add(
          when.add(const Duration(hours: 8, minutes: 10)),
          random.nextBool() ? cash : flooz,
          -(500 + random.nextInt(1200)),
          TransactionKind.expense,
          category: 'Transport',
          note: transport[random.nextInt(transport.length)],
        );
      }
      if (day % 7 == 3) {
        _add(
          when.add(const Duration(hours: 18)),
          flooz,
          -25000,
          TransactionKind.transfer,
          note: 'Flooz vers Mixx',
          transferAccountId: mixx.id,
        );
        _add(
          when.add(const Duration(hours: 18)),
          mixx,
          25000,
          TransactionKind.transfer,
          note: 'Flooz vers Mixx',
          transferAccountId: flooz.id,
        );
      }
      if (day % 10 == 0) {
        _add(
          when.add(const Duration(hours: 19)),
          cash,
          -15000,
          TransactionKind.expense,
          category: 'Tontine',
          note: 'Cotisation tontine',
        );
      }
      if (day % 15 == 0) {
        // Argent d'un client, conservé pour être reversé : neutre.
        _add(
          when.add(const Duration(hours: 11)),
          flooz,
          45000,
          TransactionKind.income,
          note: 'Avance pour un client',
          neutral: true,
          thirdPartyId: client.id,
        );
        _add(
          when.add(const Duration(hours: 16)),
          flooz,
          -30000,
          TransactionKind.expense,
          note: 'Reversement au client',
          neutral: true,
          thirdPartyId: client.id,
        );
      }
      if (day % 12 == 0) {
        _add(
          when,
          flooz,
          -20000,
          TransactionKind.savings,
          note: 'Versement épargne',
          savingsPotId: urgence.id,
        );
        _add(
          when,
          flooz,
          -10000,
          TransactionKind.savings,
          note: 'Versement pour la moto',
          savingsPotId: moto.id,
        );
      }
    }

    // Mois courant : revenus et charges fixes.
    final DateTime monthStart = DateTime(now.year, now.month, 1);
    _add(
      monthStart.add(const Duration(days: 1, hours: 8)),
      bank,
      350000,
      TransactionKind.income,
      category: 'Salaire',
      note: 'Salaire du mois',
    );
    _add(
      monthStart.add(const Duration(days: 2, hours: 9)),
      bank,
      -75000,
      TransactionKind.expense,
      category: 'Loyer',
      note: 'Loyer de la maison',
    );
    _add(
      monthStart.add(const Duration(days: 3, hours: 10)),
      cash,
      -13500,
      TransactionKind.expense,
      category: 'Électricité',
      note: 'Facture électricité',
    );
    _add(
      monthStart.add(const Duration(days: 4, hours: 11)),
      flooz,
      -4500,
      TransactionKind.expense,
      category: 'Loyer',
      note: 'Forfait internet',
    );
    _add(
      monthStart.add(const Duration(days: 5, hours: 12)),
      bank,
      -35000,
      TransactionKind.income,
      category: 'Vente',
      note: 'Vente de tissus',
    );
    _add(
      now.subtract(const Duration(days: 2)),
      flooz,
      -18000,
      TransactionKind.savings,
      note: 'Versement pour le moniteur',
      savingsPotId: ecran.id,
    );

    _budgets.addAll(<Budget>[
      Budget(
        id: 'sim-budget-1',
        category: 'Alimentation',
        monthlyLimit: 90000,
        createdAt: start,
      ),
      Budget(
        id: 'sim-budget-2',
        category: 'Transport',
        monthlyLimit: 30000,
        createdAt: start,
      ),
      Budget(
        id: 'sim-budget-3',
        category: 'Loyer',
        monthlyLimit: 90000,
        createdAt: start,
      ),
      Budget(
        id: 'sim-budget-4',
        category: 'Tontine',
        monthlyLimit: 45000,
        createdAt: start,
      ),
    ]);

    _debts.addAll(<Debt>[
      Debt(
        id: 'sim-debt-1',
        direction: DebtDirection.owedToMe,
        counterparty: 'Afi',
        principal: 40000,
        settledAmount: 10000,
        dueDate: now.add(const Duration(days: 12)),
        note: 'Prêt pour ses fournitures',
        createdAt: start,
      ),
      Debt(
        id: 'sim-debt-2',
        direction: DebtDirection.iOwe,
        counterparty: 'Boutique Adjo',
        principal: 25000,
        dueDate: now.add(const Duration(days: 6)),
        note: 'Provisions à crédit',
        createdAt: start,
      ),
      Debt(
        id: 'sim-debt-3',
        direction: DebtDirection.owedToMe,
        counterparty: 'Kodjo',
        principal: 15000,
        settledAmount: 15000,
        note: 'Remboursé',
        createdAt: start,
      ),
    ]);

    _needs.addAll(<Need>[
      Need(
        id: 'sim-need-1',
        label: 'Moniteur pour le bureau',
        amount: 120000,
        priority: NeedPriority.high,
        dueDate: now.add(const Duration(days: 40)),
        createdAt: start,
      ),
      Need(
        id: 'sim-need-2',
        label: 'Assurance moto',
        amount: 45000,
        priority: NeedPriority.medium,
        dueDate: now.add(const Duration(days: 20)),
        createdAt: start,
      ),
      Need(
        id: 'sim-need-3',
        label: 'Frais de scolarité',
        amount: 180000,
        priority: NeedPriority.high,
        createdAt: start,
      ),
    ]);
  }

  // ----------------------------------------------------------------- Lectures

  List<Account> get _active =>
      _accounts.where((Account a) => !a.archived).toList(growable: false);

  int _balanceOf(String accountId) => _transactions
      .where((TransactionRecord t) => t.accountId == accountId)
      .fold<int>(0, (int sum, TransactionRecord t) => sum + t.amount);

  Account? _accountById(String id) {
    for (final Account account in _accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  String _partyName(String? id) {
    for (final ThirdParty party in _parties) {
      if (party.id == id) return party.name;
    }
    return 'Sans nom';
  }

  @override
  Future<DashboardSnapshot> loadDashboard({int recentLimit = 5}) async {
    final List<AccountBalance> balances = <AccountBalance>[
      for (final Account account in _active)
        AccountBalance(account: account, balance: _balanceOf(account.id)),
    ];
    final int accountsTotal = balances.fold<int>(
      0,
      (int sum, AccountBalance item) => sum + item.balance,
    );
    final int savingsSum = _transactions
        .where((TransactionRecord t) => t.kind == TransactionKind.savings)
        .fold<int>(0, (int sum, TransactionRecord t) => sum + t.amount);
    final int neutralSum = _transactions
        .where((TransactionRecord t) => t.isNeutral)
        .fold<int>(0, (int sum, TransactionRecord t) => sum + t.amount);

    final DateTime monthStart = DateTime(_now.year, _now.month);
    final DateTime monthEnd = DateTime(_now.year, _now.month + 1);
    int income = 0;
    int expense = 0;
    for (final TransactionRecord t in _transactions) {
      if (t.isNeutral) continue;
      if (t.kind != TransactionKind.income &&
          t.kind != TransactionKind.expense) {
        continue;
      }
      if (t.occurredAt.isBefore(monthStart) ||
          !t.occurredAt.isBefore(monthEnd)) {
        continue;
      }
      if (t.amount > 0) {
        income += t.amount;
      } else {
        expense += -t.amount;
      }
    }

    return DashboardSnapshot(
      balance: BalanceSummary.fromSums(
        accountsTotal: accountsTotal,
        savingsTransfersSum: savingsSum,
        neutralSum: neutralSum,
        monthIncome: income,
        monthExpense: expense,
      ),
      accounts: balances,
      recent: (await movements(limit: recentLimit)),
    );
  }

  @override
  Future<List<Account>> accounts() async => _active;

  @override
  Future<List<AccountBalance>> accountBalances() async => <AccountBalance>[
    for (final Account account in _active)
      AccountBalance(account: account, balance: _balanceOf(account.id)),
  ];

  @override
  Future<List<TransactionRecord>> transactions({int limit = 50}) async {
    final List<TransactionRecord> sorted =
        List<TransactionRecord>.of(_transactions)..sort(
          (TransactionRecord a, TransactionRecord b) =>
              b.occurredAt.compareTo(a.occurredAt),
        );
    return sorted.take(limit).toList(growable: false);
  }

  @override
  Future<List<SavingsPot>> savingsPots() async =>
      _pots.where((SavingsPot p) => !p.archived).toList(growable: false);

  @override
  Future<List<ThirdParty>> thirdParties() async => _parties;

  @override
  Future<List<Debt>> debts() async => _debts;

  @override
  Future<List<SavingsPotBalance>> savingsBalances() async {
    return <SavingsPotBalance>[
      for (final SavingsPot pot in _pots)
        if (!pot.archived)
          SavingsPotBalance(
            pot: pot,
            held: _transactions
                .where(
                  (TransactionRecord t) =>
                      t.savingsPotId == pot.id &&
                      t.kind == TransactionKind.savings,
                )
                .fold<int>(0, (int sum, TransactionRecord t) => sum - t.amount),
          ),
    ];
  }

  @override
  Future<List<ThirdPartyBalance>> thirdPartyBalances() async {
    final Map<String, int> held = <String, int>{};
    for (final TransactionRecord t in _transactions) {
      if (!t.isNeutral) continue;
      final String key = t.thirdPartyId ?? 'sans-tiers';
      held[key] = (held[key] ?? 0) + t.amount;
    }
    return <ThirdPartyBalance>[
      for (final MapEntry<String, int> entry in held.entries)
        ThirdPartyBalance(
          id: entry.key == 'sans-tiers' ? null : entry.key,
          name: _partyName(entry.key),
          held: entry.value,
        ),
    ];
  }

  @override
  Future<List<TransactionLine>> movements({
    int limit = 200,
    DateTime? from,
    DateTime? to,
  }) async {
    final List<TransactionLine> lines = <TransactionLine>[];
    for (final TransactionRecord t in _transactions) {
      if (t.kind == TransactionKind.opening) continue;
      if (from != null && t.occurredAt.isBefore(from)) continue;
      if (to != null && !t.occurredAt.isBefore(to)) continue;
      final Account? account = _accountById(t.accountId);
      if (account == null) continue;
      lines.add(TransactionLine(transaction: t, account: account));
    }
    lines.sort(
      (TransactionLine a, TransactionLine b) =>
          b.transaction.occurredAt.compareTo(a.transaction.occurredAt),
    );
    return lines.take(limit).toList(growable: false);
  }

  @override
  Future<List<CategoryTotal>> categoryTotals({
    required DateTime from,
    required DateTime to,
    bool expenses = true,
  }) async {
    final Map<String, int> totals = <String, int>{};
    for (final TransactionRecord t in _transactions) {
      if (t.isNeutral) continue;
      if (t.kind !=
          (expenses ? TransactionKind.expense : TransactionKind.income)) {
        continue;
      }
      if (t.occurredAt.isBefore(from) || !t.occurredAt.isBefore(to)) continue;
      final int value = expenses ? -t.amount : t.amount;
      if (value <= 0) continue;
      final String label = (t.category == null || t.category!.trim().isEmpty)
          ? 'Sans catégorie'
          : t.category!;
      totals[label] = (totals[label] ?? 0) + value;
    }
    final List<CategoryTotal> list = <CategoryTotal>[
      for (final MapEntry<String, int> entry in totals.entries)
        CategoryTotal(label: entry.key, amount: entry.value),
    ]..sort((CategoryTotal a, CategoryTotal b) => b.amount.compareTo(a.amount));
    return list;
  }

  @override
  Future<List<AccountPeriodTotal>> accountTotals({
    required DateTime from,
    required DateTime to,
  }) async {
    return <AccountPeriodTotal>[
      for (final Account account in _active)
        AccountPeriodTotal(
          account: account,
          income: _transactions
              .where(
                (TransactionRecord t) =>
                    t.accountId == account.id &&
                    !t.isNeutral &&
                    t.kind == TransactionKind.income &&
                    !t.occurredAt.isBefore(from) &&
                    t.occurredAt.isBefore(to),
              )
              .fold<int>(0, (int sum, TransactionRecord t) => sum + t.amount),
          expense: _transactions
              .where(
                (TransactionRecord t) =>
                    t.accountId == account.id &&
                    !t.isNeutral &&
                    t.kind == TransactionKind.expense &&
                    !t.occurredAt.isBefore(from) &&
                    t.occurredAt.isBefore(to),
              )
              .fold<int>(0, (int sum, TransactionRecord t) => sum - t.amount),
        ),
    ];
  }

  @override
  Future<List<MonthTotal>> monthlyTotals({
    int months = 6,
    DateTime? reference,
  }) async {
    final DateTime anchor = reference ?? _now;
    final List<MonthTotal> totals = <MonthTotal>[];
    for (int index = 0; index < months; index++) {
      final DateTime start = DateTime(anchor.year, anchor.month - index);
      final DateTime end = DateTime(anchor.year, anchor.month - index + 1);
      int income = 0;
      int expense = 0;
      int neutralIn = 0;
      int neutralOut = 0;
      for (final TransactionRecord t in _transactions) {
        if (t.occurredAt.isBefore(start) || !t.occurredAt.isBefore(end)) {
          continue;
        }
        if (t.isNeutral) {
          if (t.amount > 0) {
            neutralIn += t.amount;
          } else {
            neutralOut += -t.amount;
          }
          continue;
        }
        if (t.kind == TransactionKind.income) income += t.amount;
        if (t.kind == TransactionKind.expense) expense += -t.amount;
      }
      totals.add(
        MonthTotal(
          year: start.year,
          month: start.month,
          income: income,
          expense: expense,
          neutralIn: neutralIn,
          neutralOut: neutralOut,
        ),
      );
    }
    return totals;
  }

  @override
  Future<List<Need>> needs() async => List<Need>.of(_needs);

  @override
  Future<List<BudgetStatus>> budgets({DateTime? month}) async {
    final DateTime anchor = month ?? _now;
    final DateTime start = DateTime(anchor.year, anchor.month);
    final DateTime end = DateTime(anchor.year, anchor.month + 1);
    return <BudgetStatus>[
      for (final Budget budget in _budgets)
        BudgetStatus(
          budget: budget,
          spent: _transactions
              .where(
                (TransactionRecord t) =>
                    !t.isNeutral &&
                    t.kind == TransactionKind.expense &&
                    t.category == budget.category &&
                    !t.occurredAt.isBefore(start) &&
                    t.occurredAt.isBefore(end),
              )
              .fold<int>(0, (int sum, TransactionRecord t) => sum - t.amount),
        ),
    ];
  }

  // ------------------------------------------------------------------ Écritures

  @override
  Future<void> saveAccount(Account account) async {
    final int index = _accounts.indexWhere((Account a) => a.id == account.id);
    if (index >= 0) {
      _accounts[index] = account;
    } else {
      _accounts.add(account);
    }
  }

  @override
  Future<void> saveTransaction(TransactionRecord transaction) async {
    final int index = _transactions.indexWhere(
      (TransactionRecord t) => t.id == transaction.id,
    );
    if (index >= 0) {
      _transactions[index] = transaction;
    } else {
      _transactions.add(transaction);
    }
  }

  @override
  Future<void> saveSavingsPot(SavingsPot pot) async {
    final int index = _pots.indexWhere((SavingsPot p) => p.id == pot.id);
    if (index >= 0) {
      _pots[index] = pot;
    } else {
      _pots.add(pot);
    }
  }

  @override
  Future<void> saveThirdParty(ThirdParty thirdParty) async {
    final int index = _parties.indexWhere(
      (ThirdParty p) => p.id == thirdParty.id,
    );
    if (index >= 0) {
      _parties[index] = thirdParty;
    } else {
      _parties.add(thirdParty);
    }
  }

  @override
  Future<void> saveDebt(Debt debt) async {
    final int index = _debts.indexWhere((Debt d) => d.id == debt.id);
    if (index >= 0) {
      _debts[index] = debt;
    } else {
      _debts.add(debt);
    }
  }

  @override
  Future<void> deleteDebt(String id) async =>
      _debts.removeWhere((Debt d) => d.id == id);

  @override
  Future<void> saveBudget(Budget budget) async {
    _budgets.removeWhere((Budget b) => b.category == budget.category);
    _budgets.add(budget);
  }

  @override
  Future<void> deleteBudget(String id) async =>
      _budgets.removeWhere((Budget b) => b.id == id);

  @override
  Future<void> deleteTransaction(TransactionRecord transaction) async {
    if (transaction.kind == TransactionKind.transfer) {
      _transactions.removeWhere(
        (TransactionRecord t) =>
            t.id == transaction.id ||
            (t.transferAccountId == transaction.accountId &&
                t.amount == -transaction.amount &&
                t.kind == TransactionKind.transfer),
      );
      return;
    }
    _transactions.removeWhere((TransactionRecord t) => t.id == transaction.id);
  }

  @override
  Future<void> ensureDefaultAccounts() async {
    // Les comptes de démonstration existent déjà.
  }

  @override
  Future<String?> setting(String key) async => _settings[key];

  @override
  Future<int> settingInt(String key, {int fallback = 0}) async =>
      int.tryParse(_settings[key] ?? '') ?? fallback;

  @override
  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
  }

  @override
  Future<void> saveNeed(Need need) async {
    final int index = _needs.indexWhere((Need n) => n.id == need.id);
    if (index >= 0) {
      _needs[index] = need;
    } else {
      _needs.add(need);
    }
  }

  @override
  Future<void> deleteNeed(String id) async =>
      _needs.removeWhere((Need n) => n.id == id);
}
