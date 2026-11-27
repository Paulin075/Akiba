import 'dart:async';

import '../../data/akiba_store.dart';
import '../../data/models/account.dart';
import '../../data/models/analysis.dart';
import '../../data/models/budget.dart';
import '../../data/models/debt.dart';
import '../../data/models/need.dart';
import '../../data/models/savings_pot.dart';
import '../../data/models/third_party.dart';
import '../../data/models/transaction_record.dart';
import '../state/akiba_settings.dart';
import 'backup_service.dart';
import 'google_account.dart';
import 'google_drive_backup.dart';
import 'home_lab_setup.dart';

/// Cible d'une sauvegarde automatique.
enum AutoBackupChannel { googleDrive, localServer }

/// Résultat d'une passe de sauvegarde automatique.
class AutoBackupResult {
  const AutoBackupResult({
    this.attempted = false,
    this.succeeded = const <AutoBackupChannel>[],
    this.failed = const <AutoBackupChannel>[],
  });

  final bool attempted;
  final List<AutoBackupChannel> succeeded;
  final List<AutoBackupChannel> failed;

  bool get ok => failed.isEmpty;
  bool get pending => failed.isNotEmpty;
}

/// Déclenche une sauvegarde après chaque écriture métier.
///
/// Les canaux sont **indépendants** : Google Drive (API ou dossier
/// synchronisé) et le serveur local (Home Lab). Un canal non configuré est
/// simplement ignoré. Un échec réseau marque la sauvegarde « en attente » et
/// un nouvel essai est programmé, puis retenté à la reprise de l'application.
class AutoBackupCoordinator {
  AutoBackupCoordinator({
    required this.store,
    required this.settings,
    BackupService? service,
    GoogleDriveService? google,
    LabTokenStore? tokens,
    this.debounce = const Duration(seconds: 3),
    this.retryInterval = const Duration(seconds: 45),
  }) : _service = service ?? BackupService(store),
       _google = google ?? GoogleDriveService(),
       _tokens = tokens ?? const SecureLabTokenStore();

  final AkibaStore store;
  final AkibaSettings settings;
  final BackupService _service;
  final GoogleDriveService _google;
  final LabTokenStore _tokens;

  /// Regroupe les modifications rapprochées en une seule sauvegarde.
  final Duration debounce;

  /// Réessaie une sauvegarde en attente ; `null` désactive les reprises
  /// automatiques (utile aux tests).
  final Duration? retryInterval;

  Timer? _debounceTimer;
  Timer? _retryTimer;
  bool _running = false;
  bool _dirty = false;
  bool _disposed = false;

  /// Vrai si une sauvegarde a échoué et attend une reprise.
  bool get pending => settings.raw('auto_backup_pending_at').isNotEmpty;

  /// Vrai quand au moins un canal est connecté/configuré.
  bool get hasGoogleDrive =>
      settings.googleLinked || settings.driveFolder.trim().isNotEmpty;

  bool get hasLocalServer =>
      settings.labAutoBackup && settings.labUrl.trim().isNotEmpty;

  bool get configured => hasGoogleDrive || hasLocalServer;

  /// À appeler après une écriture métier : anti-rebond, puis sauvegarde.
  void schedule() {
    if (_disposed || !configured) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      unawaited(flush());
    });
  }

  /// Lance immédiatement une sauvegarde (si un canal est configuré).
  Future<AutoBackupResult> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_disposed || !configured) return const AutoBackupResult();
    if (_running) {
      // Une écriture est arrivée pendant l'envoi : une seconde passe suivra.
      _dirty = true;
      return const AutoBackupResult();
    }
    _running = true;
    try {
      final List<AutoBackupChannel> targets = <AutoBackupChannel>[
        if (hasGoogleDrive) AutoBackupChannel.googleDrive,
        if (hasLocalServer) AutoBackupChannel.localServer,
      ];
      final List<AutoBackupChannel> succeeded = <AutoBackupChannel>[];
      final List<AutoBackupChannel> failed = <AutoBackupChannel>[];

      final Map<String, dynamic> envelope;
      try {
        final GoogleAccount account = await _google.currentAccount();
        envelope = await _service.createEnvelope(
          deviceId: 'akiba-${settings.timezone}',
          account: account,
        );
      } catch (_) {
        // Clé de sauvegarde indisponible : les deux canaux sont en attente.
        await _markPending();
        return AutoBackupResult(
          attempted: true,
          failed: List<AutoBackupChannel>.unmodifiable(targets),
        );
      }

      for (final AutoBackupChannel channel in targets) {
        try {
          switch (channel) {
            case AutoBackupChannel.googleDrive:
              final String folder = settings.driveFolder.trim();
              if (folder.isNotEmpty) {
                await _service.saveToFolder(envelope, folder);
              } else {
                await _google.upload(envelope);
              }
            case AutoBackupChannel.localServer:
              final String token = await _tokens.read();
              if (token.isEmpty) {
                throw const BackupException('Jeton Home Lab absent.');
              }
              await _service.putRemote(
                url: settings.labUrl.trim(),
                token: token,
                envelope: envelope,
              );
          }
          succeeded.add(channel);
        } catch (_) {
          // Aucun détail technique (URL, corps, jeton) n'est remonté ici.
          failed.add(channel);
        }
      }

      if (succeeded.isNotEmpty) {
        await settings.set(
          'last_backup_at',
          DateTime.now().toUtc().toIso8601String(),
        );
        await settings.set(
          'last_backup_target',
          succeeded.contains(AutoBackupChannel.localServer)
              ? 'homeLab'
              : 'googleDrive',
        );
      }
      if (failed.isEmpty) {
        await _clearPending();
      } else {
        await _markPending();
      }
      return AutoBackupResult(
        attempted: true,
        succeeded: List<AutoBackupChannel>.unmodifiable(succeeded),
        failed: List<AutoBackupChannel>.unmodifiable(failed),
      );
    } finally {
      _running = false;
      if (_dirty && !_disposed) {
        _dirty = false;
        schedule();
      }
    }
  }

  /// Retente une sauvegarde marquée en attente (reprise de l'application,
  /// retour du réseau).
  Future<AutoBackupResult> retryIfPending() async {
    if (!pending) return const AutoBackupResult();
    return flush();
  }

  Future<void> _markPending() async {
    await settings.set(
      'auto_backup_pending_at',
      DateTime.now().toUtc().toIso8601String(),
    );
    _armRetry();
  }

  Future<void> _clearPending() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (pending) await settings.set('auto_backup_pending_at', '');
  }

  void _armRetry() {
    final Duration? interval = retryInterval;
    if (_disposed || interval == null || _retryTimer != null) return;
    _retryTimer = Timer(interval, () {
      _retryTimer = null;
      if (!_disposed && pending) unawaited(flush());
    });
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _debounceTimer = null;
    _retryTimer = null;
  }
}

/// Enveloppe un magasin : toute écriture métier notifie le coordinateur.
///
/// Les réglages ne déclenchent **pas** de sauvegarde (sinon la sauvegarde
/// elle-même, qui met à jour sa date, provoquerait une boucle).
class AutoBackupStore implements AkibaStore {
  AutoBackupStore(this._inner, {required this.onChanged});

  final AkibaStore _inner;
  final void Function() onChanged;

  void _changed() {
    try {
      onChanged();
    } catch (_) {
      // Une sauvegarde ne doit jamais faire échouer une écriture métier.
    }
  }

  @override
  Future<DashboardSnapshot> loadDashboard({int recentLimit = 5}) =>
      _inner.loadDashboard(recentLimit: recentLimit);

  @override
  Future<List<Account>> accounts() => _inner.accounts();

  @override
  Future<List<AccountBalance>> accountBalances() => _inner.accountBalances();

  @override
  Future<List<TransactionRecord>> transactions({int limit = 50}) =>
      _inner.transactions(limit: limit);

  @override
  Future<List<SavingsPot>> savingsPots() => _inner.savingsPots();

  @override
  Future<List<ThirdParty>> thirdParties() => _inner.thirdParties();

  @override
  Future<List<Debt>> debts() => _inner.debts();

  @override
  Future<List<SavingsPotBalance>> savingsBalances() => _inner.savingsBalances();

  @override
  Future<List<ThirdPartyBalance>> thirdPartyBalances() =>
      _inner.thirdPartyBalances();

  @override
  Future<List<TransactionLine>> movements({
    int limit = 200,
    DateTime? from,
    DateTime? to,
  }) => _inner.movements(limit: limit, from: from, to: to);

  @override
  Future<List<CategoryTotal>> categoryTotals({
    required DateTime from,
    required DateTime to,
    bool expenses = true,
  }) => _inner.categoryTotals(from: from, to: to, expenses: expenses);

  @override
  Future<List<AccountPeriodTotal>> accountTotals({
    required DateTime from,
    required DateTime to,
  }) => _inner.accountTotals(from: from, to: to);

  @override
  Future<List<MonthTotal>> monthlyTotals({
    int months = 6,
    DateTime? reference,
  }) => _inner.monthlyTotals(months: months, reference: reference);

  @override
  Future<List<Need>> needs() => _inner.needs();

  @override
  Future<void> saveNeed(Need need) async {
    await _inner.saveNeed(need);
    _changed();
  }

  @override
  Future<void> deleteNeed(String id) async {
    await _inner.deleteNeed(id);
    _changed();
  }

  @override
  Future<List<BudgetStatus>> budgets({DateTime? month}) =>
      _inner.budgets(month: month);

  @override
  Future<void> saveAccount(Account account) async {
    await _inner.saveAccount(account);
    _changed();
  }

  @override
  Future<void> saveTransaction(TransactionRecord transaction) async {
    await _inner.saveTransaction(transaction);
    _changed();
  }

  @override
  Future<void> saveSavingsPot(SavingsPot pot) async {
    await _inner.saveSavingsPot(pot);
    _changed();
  }

  @override
  Future<void> saveThirdParty(ThirdParty thirdParty) async {
    await _inner.saveThirdParty(thirdParty);
    _changed();
  }

  @override
  Future<void> saveDebt(Debt debt) async {
    await _inner.saveDebt(debt);
    _changed();
  }

  @override
  Future<TransactionRecord> settleDebt(
    Debt debt, {
    required int amount,
    required String accountId,
  }) async {
    final TransactionRecord record = await _inner.settleDebt(
      debt,
      amount: amount,
      accountId: accountId,
    );
    _changed();
    return record;
  }

  @override
  Future<void> deleteDebt(String id) async {
    await _inner.deleteDebt(id);
    _changed();
  }

  @override
  Future<void> saveBudget(Budget budget) async {
    await _inner.saveBudget(budget);
    _changed();
  }

  @override
  Future<void> deleteBudget(String id) async {
    await _inner.deleteBudget(id);
    _changed();
  }

  @override
  Future<void> deleteTransaction(TransactionRecord transaction) async {
    await _inner.deleteTransaction(transaction);
    _changed();
  }

  @override
  Future<void> ensureDefaultAccounts() async {
    await _inner.ensureDefaultAccounts();
    _changed();
  }

  @override
  Future<String?> setting(String key) => _inner.setting(key);

  @override
  Future<int> settingInt(String key, {int fallback = 0}) =>
      _inner.settingInt(key, fallback: fallback);

  @override
  Future<void> setSetting(String key, String value) =>
      _inner.setSetting(key, value);
}
