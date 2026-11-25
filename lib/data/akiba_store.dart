import 'models/account.dart';
import 'models/analysis.dart';
import 'models/budget.dart';
import 'models/debt.dart';
import 'models/need.dart';
import 'models/savings_pot.dart';
import 'models/third_party.dart';
import 'models/transaction_record.dart';
import 'balance_summary.dart';

/// Un mouvement accompagné de son compte, prêt à être affiché.
class TransactionLine {
  const TransactionLine({required this.transaction, required this.account});

  final TransactionRecord transaction;
  final Account account;
}

/// Tout ce dont l'écran d'accueil a besoin en une lecture.
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.balance,
    required this.accounts,
    required this.recent,
  });

  final BalanceSummary balance;
  final List<AccountBalance> accounts;
  final List<TransactionLine> recent;

  bool get isEmpty => accounts.isEmpty && recent.isEmpty;

  static const DashboardSnapshot empty = DashboardSnapshot(
    balance: BalanceSummary.empty,
    accounts: <AccountBalance>[],
    recent: <TransactionLine>[],
  );
}

/// Accès aux données locales d'AKIBA.
///
/// Les soldes ne sont jamais écrits : seules les transactions le sont, et les
/// totaux sont recalculés à chaque lecture.
abstract interface class AkibaStore {
  Future<DashboardSnapshot> loadDashboard({int recentLimit = 5});

  Future<List<Account>> accounts();
  Future<List<AccountBalance>> accountBalances();
  Future<List<TransactionRecord>> transactions({int limit = 50});
  Future<List<SavingsPot>> savingsPots();
  Future<List<ThirdParty>> thirdParties();
  Future<List<Debt>> debts();

  /// Coffres avec leur montant épargné.
  Future<List<SavingsPotBalance>> savingsBalances();

  /// Tiers avec le montant détenu pour chacun.
  Future<List<ThirdPartyBalance>> thirdPartyBalances();

  /// Mouvements (hors soldes d'ouverture), filtrables par période.
  Future<List<TransactionLine>> movements({
    int limit = 200,
    DateTime? from,
    DateTime? to,
  });

  /// Totaux par catégorie sur une période, hors argent de tiers et épargne.
  Future<List<CategoryTotal>> categoryTotals({
    required DateTime from,
    required DateTime to,
    bool expenses = true,
  });

  /// Entrées et sorties par compte sur une période.
  Future<List<AccountPeriodTotal>> accountTotals({
    required DateTime from,
    required DateTime to,
  });

  /// Bilans des [months] derniers mois (le plus récent en premier).
  Future<List<MonthTotal>> monthlyTotals({int months = 6, DateTime? reference});

  /// Besoins priorisés.
  Future<List<Need>> needs();
  Future<void> saveNeed(Need need);
  Future<void> deleteNeed(String id);

  /// Budgets du mois, avec la dépense réelle de chaque catégorie.
  Future<List<BudgetStatus>> budgets({DateTime? month});

  Future<void> saveAccount(Account account);
  Future<void> saveTransaction(TransactionRecord transaction);
  Future<void> saveSavingsPot(SavingsPot pot);
  Future<void> saveThirdParty(ThirdParty thirdParty);
  Future<void> saveDebt(Debt debt);

  /// Enregistre le règlement d'une créance ou d'une dette **avec** le
  /// mouvement de trésorerie correspondant, sur le compte choisi.
  ///
  /// - créance (« on me doit ») encaissée : entrée `+montant` sur le compte,
  ///   le solde disponible augmente réellement ;
  /// - dette (« je dois ») payée : sortie `-montant` depuis le compte choisi.
  ///
  /// Le montant est borné au reste dû, et le reste dû est mis à jour dans la
  /// même opération. Renvoie le mouvement créé (pour l'annulation).
  Future<TransactionRecord> settleDebt(
    Debt debt, {
    required int amount,
    required String accountId,
  });

  /// Supprime une créance ou une dette (utilisé par « Annuler »).
  Future<void> deleteDebt(String id);
  Future<void> saveBudget(Budget budget);
  Future<void> deleteBudget(String id);

  /// Supprime un mouvement ; un transfert entraîne son écriture jumelle.
  Future<void> deleteTransaction(TransactionRecord transaction);

  /// Crée les quatre comptes par défaut si la base n'en contient aucun.
  Future<void> ensureDefaultAccounts();

  Future<String?> setting(String key);
  Future<int> settingInt(String key, {int fallback = 0});
  Future<void> setSetting(String key, String value);
}

/// Magasin sans base locale (repli de démarrage et tests).
///
/// Il ne stocke rien et renvoie toujours des totaux à zéro : l'interface reste
/// utilisable même si le stockage sécurisé ou le fichier chiffré est
/// indisponible.
class EmptyAkibaStore implements AkibaStore {
  const EmptyAkibaStore();

  @override
  Future<DashboardSnapshot> loadDashboard({int recentLimit = 5}) async =>
      DashboardSnapshot.empty;

  @override
  Future<List<Account>> accounts() async => const <Account>[];

  @override
  Future<List<AccountBalance>> accountBalances() async =>
      const <AccountBalance>[];

  @override
  Future<List<TransactionRecord>> transactions({int limit = 50}) async =>
      const <TransactionRecord>[];

  @override
  Future<List<SavingsPot>> savingsPots() async => const <SavingsPot>[];

  @override
  Future<List<ThirdParty>> thirdParties() async => const <ThirdParty>[];

  @override
  Future<List<Debt>> debts() async => const <Debt>[];

  @override
  Future<List<BudgetStatus>> budgets({DateTime? month}) async =>
      const <BudgetStatus>[];

  @override
  Future<List<SavingsPotBalance>> savingsBalances() async =>
      const <SavingsPotBalance>[];

  @override
  Future<List<ThirdPartyBalance>> thirdPartyBalances() async =>
      const <ThirdPartyBalance>[];

  @override
  Future<List<TransactionLine>> movements({
    int limit = 200,
    DateTime? from,
    DateTime? to,
  }) async => const <TransactionLine>[];

  @override
  Future<List<CategoryTotal>> categoryTotals({
    required DateTime from,
    required DateTime to,
    bool expenses = true,
  }) async => const <CategoryTotal>[];

  @override
  Future<List<AccountPeriodTotal>> accountTotals({
    required DateTime from,
    required DateTime to,
  }) async => const <AccountPeriodTotal>[];

  @override
  Future<List<MonthTotal>> monthlyTotals({
    int months = 6,
    DateTime? reference,
  }) async => const <MonthTotal>[];

  @override
  Future<List<Need>> needs() async => const <Need>[];

  @override
  Future<void> saveNeed(Need need) async =>
      throw StateError('Aucune base locale ouverte');

  @override
  Future<void> deleteNeed(String id) async =>
      throw StateError('Aucune base locale ouverte');

  @override
  Future<void> saveAccount(Account account) async =>
      throw StateError('Aucune base locale ouverte');

  @override
  Future<void> saveTransaction(TransactionRecord transaction) async =>
      throw StateError('Aucune base locale ouverte');

  @override
  Future<void> saveSavingsPot(SavingsPot pot) async =>
      throw StateError('Aucune base locale ouverte');

  @override
  Future<void> saveThirdParty(ThirdParty thirdParty) async =>
      throw StateError('Aucune base locale ouverte');

  @override
  Future<void> saveDebt(Debt debt) async =>
      throw StateError('Aucune base locale ouverte');

  @override
  Future<TransactionRecord> settleDebt(
    Debt debt, {
    required int amount,
    required String accountId,
  }) async => throw StateError('Aucune base locale ouverte');

  @override
  Future<void> deleteDebt(String id) async =>
      throw StateError('Aucune base locale ouverte');

  @override
  Future<void> saveBudget(Budget budget) async =>
      throw StateError('Aucune base locale ouverte');

  @override
  Future<void> deleteBudget(String id) async =>
      throw StateError('Aucune base locale ouverte');

  @override
  Future<void> deleteTransaction(TransactionRecord transaction) async =>
      throw StateError('Aucune base locale ouverte');

  @override
  Future<void> ensureDefaultAccounts() async {}

  @override
  Future<String?> setting(String key) async => null;

  @override
  Future<int> settingInt(String key, {int fallback = 0}) async => fallback;

  @override
  Future<void> setSetting(String key, String value) async =>
      throw StateError('Aucune base locale ouverte');
}
