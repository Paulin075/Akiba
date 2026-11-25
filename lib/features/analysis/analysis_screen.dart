import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/akiba_date.dart';
import '../../core/format/akiba_money.dart';
import '../../core/format/label_icons.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/state/masked_amounts.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/akiba_surface_card.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/icon_circle_button.dart';
import '../../core/widgets/segmented_control.dart';
import '../../data/akiba_store.dart';
import '../../data/balance_summary.dart';
import '../../data/models/analysis.dart';
import '../../data/models/budget.dart';
import '../../data/models/need.dart';
import '../../data/models/transaction_record.dart';

const List<String> _monthNames = <String>[
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// Écran Analyses : statistiques, budgets, besoins priorisés et bilans
/// mensuels. L'argent de tiers et l'épargne sont exclus de tous les calculs.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({
    super.key,
    required this.store,
    required this.revision,
  });

  final AkibaStore store;
  final AkibaDataRevision revision;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  int _segment = 0;
  int _period = 1;
  late Future<_AnalysisData> _future = _load();

  @override
  void initState() {
    super.initState();
    widget.revision.addListener(_reload);
  }

  @override
  void didUpdateWidget(covariant AnalysisScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Bascule réel / simulation : le magasin change d'instance.
    if (!identical(oldWidget.store, widget.store)) {
      _reload();
    }
  }

  @override
  void dispose() {
    widget.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    // Future créé hors de `setState` : un callback qui rend un Future est
    // rejeté par Flutter (« returned a Future ») et la vue restait figée.
    final Future<_AnalysisData> next = _load();
    setState(() {
      _future = next;
    });
  }

  Future<void> _refresh() async {
    final Future<_AnalysisData> next = _load();
    if (mounted) {
      setState(() {
        _future = next;
      });
    }
    await next;
  }

  (DateTime, DateTime) _periodBounds() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      0 => (
        today.subtract(const Duration(days: 6)),
        today.add(const Duration(days: 1)),
      ),
      1 => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
      2 => (DateTime(now.year), DateTime(now.year + 1)),
      // « Tout » couvre réellement l'historique. Les agrégats sont calculés en
      // SQL (période bornée à l'époque Unix pour éviter toute date invalide) et
      // aucun mouvement n'est chargé ligne par ligne : l'écran ne gèle plus.
      _ => (DateTime.utc(1970), today.add(const Duration(days: 1))),
    };
  }

  Future<_AnalysisData> _load() async {
    final (DateTime from, DateTime to) = _periodBounds();
    final DashboardSnapshot dashboard = await widget.store.loadDashboard(
      recentLimit: 1,
    );
    final List<CategoryTotal> expenses = await widget.store.categoryTotals(
      from: from,
      to: to,
    );
    final List<CategoryTotal> incomes = await widget.store.categoryTotals(
      from: from,
      to: to,
      expenses: false,
    );
    final List<AccountPeriodTotal> accounts = await widget.store.accountTotals(
      from: from,
      to: to,
    );
    // Nombre de mois borné (24) : un historique très long ne doit jamais
    // produire des milliers de barres ni bloquer l'interface.
    final int monthCount = switch (_period) {
      2 => 12,
      3 => 24,
      _ => 6,
    };
    final List<MonthTotal> months = await widget.store.monthlyTotals(
      months: monthCount,
    );
    final List<BudgetStatus> budgets = await widget.store.budgets();
    final List<Need> needs = await widget.store.needs();
    final int reserve = await widget.store.settingInt('reserve_securite');
    // Les barres quotidiennes n'existent que pour Semaine / Mois. Pour Année et
    // Tout, seuls les agrégats mensuels sont utiles : charger 2 000 mouvements
    // était la cause du gel sur « Tout ».
    final int movementLimit = switch (_period) {
      0 => 400,
      1 => 1200,
      _ => 0,
    };
    final List<TransactionLine> movements = movementLimit == 0
        ? const <TransactionLine>[]
        : await widget.store.movements(
            from: from,
            to: to,
            limit: movementLimit,
          );

    return _AnalysisData(
      balance: dashboard.balance,
      expenses: expenses,
      incomes: incomes,
      accounts: accounts,
      months: months,
      budgets: budgets,
      needs: needs,
      reserve: reserve,
      movements: movements,
      from: from,
      to: to,
    );
  }

  void _toast(String message) {
    final AkibaColors c = AkibaColors.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: c.textPrimary,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final bool masked = MaskedAmounts.of(context);

    return FutureBuilder<_AnalysisData>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<_AnalysisData> async) {
        final _AnalysisData? data = async.data;
        return RefreshIndicator(
          color: AkibaColors.of(context).terracotta,
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AkibaSpacing.screen,
              AkibaSpacing.lg,
              AkibaSpacing.screen,
              160,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _Header(
                      masked: masked,
                      onToggleMasked: () => MaskedAmounts.toggle(context),
                    ),
                    const SizedBox(height: AkibaSpacing.xxl),
                    SegmentedControl(
                      segments: const <String>[
                        'Statistiques',
                        'Budget',
                        'Besoins',
                        'Bilans',
                      ],
                      selectedIndex: _segment,
                      onChanged: (int index) =>
                          setState(() => _segment = index),
                    ),
                    const SizedBox(height: AkibaSpacing.xl),
                    if (async.hasError)
                      Text(
                        'Les analyses n’ont pas pu être calculées.',
                        style: AkibaTypography.body.copyWith(
                          color: AkibaColors.of(context).danger,
                        ),
                      )
                    else if (data == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: AkibaSpacing.xxxl,
                        ),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...<Widget>[
                      if (_segment == 0) _statisticsTab(data, masked),
                      if (_segment == 1) _budgetTab(data, masked),
                      if (_segment == 2) _needsTab(data, masked),
                      if (_segment == 3) _balancesTab(data, masked),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------- Statistiques

  Widget _statisticsTab(_AnalysisData data, bool masked) {
    final AkibaColors c = AkibaColors.of(context);
    final int totalExpense = data.expenses.fold<int>(
      0,
      (int sum, CategoryTotal item) => sum + item.amount,
    );
    final int totalIncome = data.incomes.fold<int>(
      0,
      (int sum, CategoryTotal item) => sum + item.amount,
    );
    final List<({String label, int value})> bars = _bars(data);
    final int maxValue = bars.fold<int>(
      0,
      (int max, ({String label, int value}) bar) =>
          bar.value > max ? bar.value : max,
    );
    final int budgetDaily = data.budgets.isEmpty
        ? 0
        : (data.budgets.fold<int>(
                    0,
                    (int sum, BudgetStatus b) => sum + b.limit,
                  ) /
                  (bars.isEmpty ? 1 : bars.length))
              .round();
    final int cap = budgetDaily > 0 ? budgetDaily : maxValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SegmentedControl(
          segments: const <String>['Semaine', 'Mois', 'Année', 'Tout'],
          selectedIndex: _period,
          onChanged: (int index) {
            if (index == _period) return;
            // Une seule requête par changement : l'index est mémorisé avant
            // de relancer la lecture, sans reconstruire en boucle.
            setState(() {
              _period = index;
              _future = _load();
            });
          },
        ),
        const SizedBox(height: AkibaSpacing.lg),
        AkibaSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'DÉPENSES SUR LA PÉRIODE',
                style: AkibaTypography.label.copyWith(
                  color: c.textMuted,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: AkibaSpacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  AkibaMoney.format(totalExpense, masked: masked),
                  style: AkibaTypography.money(30, color: c.textPrimary),
                ),
              ),
              const SizedBox(height: AkibaSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _MiniMetric(
                      label: 'Revenus',
                      value: AkibaMoney.format(totalIncome, masked: masked),
                      color: c.success,
                    ),
                  ),
                  Expanded(
                    child: _MiniMetric(
                      label: 'Net',
                      value: AkibaMoney.format(
                        totalIncome - totalExpense,
                        masked: masked,
                      ),
                      color: totalIncome - totalExpense < 0
                          ? c.danger
                          : c.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                'Argent de tiers et épargne exclus de ces totaux.',
                style: AkibaTypography.legend.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: AkibaSpacing.xl),
        const _SectionTitle('Rythme des dépenses'),
        const SizedBox(height: AkibaSpacing.md),
        AkibaSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: 130,
                child: _MiniBars(bars: bars, cap: cap),
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Wrap(
                spacing: AkibaSpacing.lg,
                runSpacing: AkibaSpacing.xs,
                children: <Widget>[
                  _LegendDot(color: c.terracotta, label: 'Dépensé'),
                  _LegendDot(
                    color: c.sand,
                    label: budgetDaily > 0 ? 'Plafond budget' : 'Échelle',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AkibaSpacing.xl),
        const _SectionTitle('Par catégorie'),
        const SizedBox(height: AkibaSpacing.md),
        if (data.expenses.isEmpty)
          const _EmptyCard(
            icon: Icons.pie_chart_outline_rounded,
            title: 'Aucune dépense sur la période',
            detail: 'Les catégories apparaîtront dès la première sortie.',
          )
        else
          AkibaSurfaceCard(
            child: Column(
              children: <Widget>[
                for (final CategoryTotal item in data.expenses)
                  _BreakdownRow(
                    label: item.label,
                    amount: item.amount,
                    total: totalExpense,
                    masked: masked,
                  ),
              ],
            ),
          ),
        const SizedBox(height: AkibaSpacing.xl),
        const _SectionTitle('Par compte'),
        const SizedBox(height: AkibaSpacing.md),
        if (data.accounts.isEmpty)
          const _EmptyCard(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Aucun compte',
            detail: 'Ajoutez un compte dans le portefeuille.',
          )
        else
          AkibaSurfaceCard(
            child: Column(
              children: <Widget>[
                for (final AccountPeriodTotal item in data.accounts)
                  _AccountRow(item: item, masked: masked),
              ],
            ),
          ),
      ],
    );
  }

  List<({String label, int value})> _bars(_AnalysisData data) {
    if (_period <= 1) {
      final Map<DateTime, int> perDay = <DateTime, int>{};
      for (final TransactionLine line in data.movements) {
        final DateTime local = line.transaction.occurredAt.toLocal();
        if (line.transaction.isNeutral) continue;
        if (line.transaction.kind != TransactionKind.expense) continue;
        if (line.transaction.amount >= 0) continue;
        final DateTime key = DateTime(local.year, local.month, local.day);
        perDay[key] = (perDay[key] ?? 0) - line.transaction.amount;
      }

      // Garde-fou : jamais plus de 62 barres quotidiennes, même si la période
      // venait à être élargie par erreur (source du gel de l'écran).
      final int days = data.to
          .difference(data.from)
          .inDays
          .clamp(0, 62)
          .toInt();
      final List<({String label, int value})> daily =
          <({String label, int value})>[];
      for (int index = 0; index < days; index++) {
        final DateTime day = data.from.add(Duration(days: index));
        daily.add((
          label: '${day.day}',
          value: perDay[DateTime(day.year, day.month, day.day)] ?? 0,
        ));
      }
      return daily;
    }

    final List<MonthTotal> chronological = data.months.reversed.toList(
      growable: false,
    );
    // Plafond dur à 24 barres : au-delà, la lisibilité et la fluidité sont
    // dégradées pour rien.
    final List<MonthTotal> bounded = chronological.length > 24
        ? chronological.sublist(chronological.length - 24)
        : chronological;
    return <({String label, int value})>[
      for (final MonthTotal month in bounded)
        (
          label: _monthNames[(month.month - 1).clamp(0, 11).toInt()].substring(
            0,
            3,
          ),
          value: month.expense.isNegative ? 0 : month.expense,
        ),
    ];
  }

  // ------------------------------------------------------------------ Budget

  Widget _budgetTab(_AnalysisData data, bool masked) {
    final AkibaColors c = AkibaColors.of(context);
    final int totalLimit = data.budgets.fold<int>(
      0,
      (int sum, BudgetStatus item) => sum + item.limit,
    );
    final int totalSpent = data.budgets.fold<int>(
      0,
      (int sum, BudgetStatus item) => sum + item.spent,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AkibaSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'BUDGET DU MOIS',
                style: AkibaTypography.label.copyWith(
                  color: c.textMuted,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                '${AkibaMoney.format(totalSpent, masked: masked)} '
                'sur ${AkibaMoney.format(totalLimit, masked: masked)}',
                style: AkibaTypography.money(22, color: c.textPrimary),
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                'Vert < 80 %, orange de 80 % à 100 %, rouge au-delà.',
                style: AkibaTypography.legend.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: AkibaSpacing.xl),
        const _SectionTitle('Plafonds par catégorie'),
        const SizedBox(height: AkibaSpacing.md),
        if (data.budgets.isEmpty)
          const _EmptyCard(
            icon: Icons.speed_rounded,
            title: 'Aucun budget',
            detail:
                'Définissez un plafond mensuel par catégorie pour suivre vos '
                'jauges.',
          )
        else
          for (final BudgetStatus status in data.budgets)
            Padding(
              padding: const EdgeInsets.only(bottom: AkibaSpacing.md),
              child: _BudgetCard(
                status: status,
                masked: masked,
                onEdit: () => _editBudget(status),
                onDelete: () => _deleteBudget(status),
              ),
            ),
        const SizedBox(height: AkibaSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => _editBudget(null),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Ajouter un plafond'),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- Besoins

  Widget _needsTab(_AnalysisData data, bool masked) {
    final AkibaColors c = AkibaColors.of(context);
    final int capacity = data.balance.available - data.reserve;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AkibaSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'CAPACITÉ D’ACHAT',
                      style: AkibaTypography.label.copyWith(
                        color: c.textMuted,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _editReserve(data.reserve),
                    child: const Text('Réserve'),
                  ),
                ],
              ),
              const SizedBox(height: AkibaSpacing.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  AkibaMoney.format(capacity, masked: masked),
                  style: AkibaTypography.money(
                    26,
                    color: capacity < 0 ? c.danger : c.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                'Solde disponible − réserve de sécurité '
                '(${AkibaMoney.format(data.reserve, masked: masked)}). '
                'Un besoin est « payable bientôt » si son montant tient dans '
                'cette capacité.',
                style: AkibaTypography.legend.copyWith(
                  color: c.textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AkibaSpacing.xl),
        const _SectionTitle('Besoins priorisés'),
        const SizedBox(height: AkibaSpacing.md),
        if (data.needs.isEmpty)
          const _EmptyCard(
            icon: Icons.playlist_add_check_rounded,
            title: 'Aucun besoin',
            detail:
                'Ajoutez un besoin et son montant pour savoir ce qui est '
                'payable maintenant.',
          )
        else
          for (final Need need in data.needs)
            Padding(
              padding: const EdgeInsets.only(bottom: AkibaSpacing.md),
              child: _NeedCard(
                need: need,
                capacity: capacity,
                masked: masked,
                onToggle: () => _toggleNeed(need),
                onDelete: () => _deleteNeed(need),
              ),
            ),
        const SizedBox(height: AkibaSpacing.sm),
        OutlinedButton.icon(
          onPressed: _addNeed,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Ajouter un besoin'),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- Bilans

  Widget _balancesTab(_AnalysisData data, bool masked) {
    if (data.months.isEmpty) {
      return const _EmptyCard(
        icon: Icons.calendar_month_outlined,
        title: 'Aucun bilan',
        detail: 'Les bilans apparaîtront après le premier mois d’utilisation.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionTitle('Bilans mensuels'),
        const SizedBox(height: AkibaSpacing.xs),
        Text(
          'Comparaison avec le mois précédent. L’argent de tiers est isolé et '
          'n’entre ni dans les revenus ni dans les dépenses.',
          style: AkibaTypography.legend.copyWith(
            color: AkibaColors.of(context).textMuted,
          ),
        ),
        const SizedBox(height: AkibaSpacing.md),
        for (int index = 0; index < data.months.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: AkibaSpacing.md),
            child: _MonthCard(
              month: data.months[index],
              previous: index + 1 < data.months.length
                  ? data.months[index + 1]
                  : null,
              masked: masked,
            ),
          ),
      ],
    );
  }

  // ----------------------------------------------------------- Interactions

  Future<void> _editBudget(BudgetStatus? status) async {
    final ({String category, int limit})? draft =
        await showDialog<({String category, int limit})>(
          context: context,
          builder: (BuildContext context) =>
              _BudgetDialog(existing: status?.budget),
        );
    if (draft == null || !mounted) return;

    await widget.store.saveBudget(
      Budget(
        id:
            status?.budget.id ??
            'budget-${DateTime.now().microsecondsSinceEpoch}',
        category: draft.category,
        monthlyLimit: draft.limit,
        createdAt: status?.budget.createdAt ?? DateTime.now(),
      ),
    );
    widget.revision.bump();
  }

  Future<void> _deleteBudget(BudgetStatus status) async {
    await widget.store.deleteBudget(status.budget.id);
    widget.revision.bump();
    _toast('Plafond supprimé.');
  }

  Future<void> _editReserve(int current) async {
    final int? value = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => _ReserveDialog(current: current),
    );
    if (value == null || !mounted) return;

    await widget.store.setSetting('reserve_securite', '$value');
    widget.revision.bump();
  }

  Future<void> _addNeed() async {
    final _NeedDraft? draft = await showDialog<_NeedDraft>(
      context: context,
      builder: (BuildContext context) => const _NeedDialog(),
    );
    if (draft == null || !mounted) return;

    final DateTime now = DateTime.now();
    await widget.store.saveNeed(
      Need(
        id: 'need-${now.microsecondsSinceEpoch}',
        label: draft.label,
        amount: draft.amount,
        priority: draft.priority,
        dueDate: draft.dueDate,
        createdAt: now,
      ),
    );
    widget.revision.bump();
  }

  Future<void> _toggleNeed(Need need) async {
    await widget.store.saveNeed(need.copyWith(isSettled: !need.isSettled));
    widget.revision.bump();
  }

  Future<void> _deleteNeed(Need need) async {
    await widget.store.deleteNeed(need.id);
    widget.revision.bump();
  }
}

class _AnalysisData {
  const _AnalysisData({
    required this.balance,
    required this.expenses,
    required this.incomes,
    required this.accounts,
    required this.months,
    required this.budgets,
    required this.needs,
    required this.reserve,
    required this.movements,
    required this.from,
    required this.to,
  });

  final BalanceSummary balance;
  final List<CategoryTotal> expenses;
  final List<CategoryTotal> incomes;
  final List<AccountPeriodTotal> accounts;
  final List<MonthTotal> months;
  final List<BudgetStatus> budgets;
  final List<Need> needs;
  final int reserve;
  final List<TransactionLine> movements;
  final DateTime from;
  final DateTime to;
}

class _Header extends StatelessWidget {
  const _Header({required this.masked, required this.onToggleMasked});

  final bool masked;
  final VoidCallback onToggleMasked;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'ANALYSES',
                style: AkibaTypography.label.copyWith(
                  color: c.textMuted,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: AkibaSpacing.xs),
              Text(
                'Mes tendances',
                style: AkibaTypography.screenTitle.copyWith(
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
        IconCircleButton(
          icon: masked
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          tooltip: masked ? 'Afficher les montants' : 'Masquer les montants',
          onTap: onToggleMasked,
        ),
      ],
    );
  }
}

class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.bars, required this.cap});

  final List<({String label, int value})> bars;
  final int cap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final int maxValue = bars.fold<int>(
      cap,
      (int max, ({String label, int value}) bar) =>
          bar.value > max ? bar.value : max,
    );
    final double scale = maxValue == 0 ? 1 : maxValue.toDouble();
    // Une valeur non finie (division impossible en amont) ne doit jamais
    // atteindre `FractionallySizedBox`, qui lèverait une exception de rendu.
    double heightOf(int value) {
      final double factor = value / scale;
      if (!factor.isFinite) return 0;
      return factor.clamp(0.0, 1.0).toDouble();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (int index = 0; index < bars.length; index++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: <Widget>[
                        FractionallySizedBox(
                          heightFactor: cap <= 0
                              ? 0
                              : (cap / scale).clamp(0.0, 1.0).toDouble(),
                          widthFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.sand.withValues(alpha: 0.55),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        FractionallySizedBox(
                          heightFactor: heightOf(bars[index].value),
                          widthFactor: 0.55,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.terracotta,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    bars.length <= 8 || index % 5 == 0 ? bars[index].label : '',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 9,
                      color: c.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AkibaSpacing.xs),
        Text(label, style: AkibaTypography.legend.copyWith(color: c.textMuted)),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AkibaTypography.legend.copyWith(color: c.textMuted)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: AkibaTypography.money(
              15,
              weight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.amount,
    required this.total,
    required this.masked,
  });

  final String label;
  final int amount;
  final int total;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final double ratio = total <= 0 ? 0 : amount / total;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AkibaSpacing.sm),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              // Une icône par catégorie : lecture immédiate de la ventilation.
              Icon(
                LabelIcons.forCategory(label),
                size: 17,
                color: c.terracottaDeep,
              ),
              const SizedBox(width: AkibaSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AkibaSpacing.sm),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    AkibaMoney.format(amount, masked: masked),
                    maxLines: 1,
                    style: AkibaTypography.money(14, color: c.textPrimary),
                  ),
                ),
              ),
              const SizedBox(width: AkibaSpacing.sm),
              SizedBox(
                width: 44,
                child: Text(
                  masked ? '••• %' : AkibaMoney.percent(ratio * 100),
                  textAlign: TextAlign.right,
                  style: AkibaTypography.money(
                    12,
                    weight: FontWeight.w600,
                    color: c.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AkibaRadii.pill),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: c.surfaceElevated,
              valueColor: AlwaysStoppedAnimation<Color>(c.terracotta),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.item, required this.masked});

  final AccountPeriodTotal item;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AkibaSpacing.sm),
      child: Row(
        children: <Widget>[
          BrandLogo(brand: item.account.brand, size: BrandLogoSize.compact),
          const SizedBox(width: AkibaSpacing.md),
          Expanded(
            child: Text(
              item.account.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AkibaSpacing.sm),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '− ${AkibaMoney.format(item.expense, masked: masked)}',
                    maxLines: 1,
                    style: AkibaTypography.money(13, color: c.danger),
                  ),
                  Text(
                    '+ ${AkibaMoney.format(item.income, masked: masked)}',
                    maxLines: 1,
                    style: AkibaTypography.money(
                      12,
                      weight: FontWeight.w500,
                      color: c.success,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.status,
    required this.masked,
    required this.onEdit,
    required this.onDelete,
  });

  final BudgetStatus status;
  final bool masked;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final Color gauge = switch (status.level) {
      BudgetLevel.safe => c.success,
      BudgetLevel.warning => c.warning,
      BudgetLevel.exceeded => c.danger,
    };
    final String levelLabel = switch (status.level) {
      BudgetLevel.safe => 'Sous contrôle',
      BudgetLevel.warning => 'Presque atteint',
      BudgetLevel.exceeded => 'Dépassé',
    };

    return AkibaSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.iconTile,
                  borderRadius: BorderRadius.circular(AkibaRadii.iconTile),
                ),
                child: Icon(
                  LabelIcons.forCategory(status.budget.category),
                  size: 17,
                  color: c.terracottaDeep,
                ),
              ),
              const SizedBox(width: AkibaSpacing.sm),
              // Nom et pastille empilés : aucune largeur minimale imposée à la
              // ligne, donc aucun débordement à 320 px.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      status.budget.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _LevelPill(label: levelLabel, color: gauge),
                  ],
                ),
              ),
              // Un seul menu plutôt que deux boutons : la ligne tient sur 320 px
              // même avec une pastille « Presque atteint ».
              PopupMenuButton<String>(
                tooltip: 'Actions du plafond',
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: c.textMuted,
                ),
                padding: EdgeInsets.zero,
                onSelected: (String value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (BuildContext context) =>
                    const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Text('Modifier'),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Supprimer'),
                      ),
                    ],
              ),
            ],
          ),
          const SizedBox(height: AkibaSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${AkibaMoney.format(status.spent, masked: masked)} '
                    'sur ${AkibaMoney.format(status.limit, masked: masked)}',
                    maxLines: 1,
                    style: AkibaTypography.money(14, color: c.textPrimary),
                  ),
                ),
              ),
              Text(
                masked ? '••• %' : AkibaMoney.percent(status.ratio * 100),
                style: AkibaTypography.money(
                  13,
                  weight: FontWeight.w700,
                  color: gauge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AkibaSpacing.sm),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: status.progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, double value, Widget? child) =>
                ClipRRect(
                  borderRadius: BorderRadius.circular(AkibaRadii.pill),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 10,
                    backgroundColor: c.surfaceElevated,
                    valueColor: AlwaysStoppedAnimation<Color>(gauge),
                  ),
                ),
          ),
          const SizedBox(height: AkibaSpacing.xs),
          Text(
            status.isExceeded
                ? 'Plafond dépassé : les dépenses de la catégorie continuent '
                      'd’être enregistrées.'
                : 'Reste ${AkibaMoney.format(status.remaining, masked: masked)}',
            style: AkibaTypography.legend.copyWith(
              color: status.isExceeded ? c.danger : c.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AkibaSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AkibaRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _NeedCard extends StatelessWidget {
  const _NeedCard({
    required this.need,
    required this.capacity,
    required this.masked,
    required this.onToggle,
    required this.onDelete,
  });

  final Need need;
  final int capacity;
  final bool masked;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final bool affordable = need.isAffordable(capacity);
    final Color statusColor = need.isSettled
        ? c.textMuted
        : affordable
        ? c.success
        : c.danger;
    final String statusLabel = need.isSettled
        ? 'Soldé'
        : affordable
        ? 'Payable bientôt'
        : 'Hors de portée';

    return AkibaSurfaceCard(
      padding: const EdgeInsets.all(AkibaSpacing.lg),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  need.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                    decoration: need.isSettled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    'Priorité ${need.priority.label.toLowerCase()}',
                    if (need.dueDate != null)
                      'échéance ${AkibaDate.short(need.dueDate!)}',
                  ].join(' · '),
                  style: AkibaTypography.legend.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  statusLabel,
                  style: AkibaTypography.label.copyWith(
                    color: statusColor,
                    letterSpacing: 0.3,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AkibaSpacing.sm),
          Text(
            AkibaMoney.format(need.amount, masked: masked),
            style: AkibaTypography.money(
              15,
              weight: FontWeight.w600,
              color: need.isSettled ? c.textMuted : c.textPrimary,
            ),
          ),
          IconButton(
            tooltip: need.isSettled ? 'Rouvrir' : 'Marquer comme soldé',
            onPressed: onToggle,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              need.isSettled
                  ? Icons.undo_rounded
                  : Icons.check_circle_outline_rounded,
              size: 18,
              color: need.isSettled ? c.textMuted : c.success,
            ),
          ),
          IconButton(
            tooltip: 'Supprimer',
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: c.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.month,
    required this.previous,
    required this.masked,
  });

  final MonthTotal month;
  final MonthTotal? previous;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final MonthTotal? before = previous;
    final double? change = before == null || before.expense == 0
        ? null
        : (month.expense - before.expense) / before.expense;
    final String rawMonth = _monthNames[(month.month - 1).clamp(0, 11).toInt()];
    final String monthLabel =
        '${rawMonth[0].toUpperCase()}${rawMonth.substring(1)} ${month.year}';

    return AkibaSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  monthLabel,
                  style: AkibaTypography.sectionTitle.copyWith(
                    fontSize: 15,
                    color: c.textPrimary,
                  ),
                ),
              ),
              if (change != null)
                _LevelPill(
                  label:
                      '${change > 0 ? '+' : '−'}'
                      '${(change.abs() * 100).round()} % vs mois précédent',
                  color: change > 0 ? c.danger : c.success,
                ),
            ],
          ),
          const SizedBox(height: AkibaSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: _MiniMetric(
                  label: 'Revenus',
                  value: AkibaMoney.format(month.income, masked: masked),
                  color: c.success,
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: 'Dépenses',
                  value: AkibaMoney.format(month.expense, masked: masked),
                  color: c.danger,
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: 'Net',
                  value: AkibaMoney.format(month.net, masked: masked),
                  color: month.net < 0 ? c.danger : c.textPrimary,
                ),
              ),
            ],
          ),
          if (month.hasNeutral) ...<Widget>[
            const SizedBox(height: AkibaSpacing.sm),
            Text(
              'Argent de tiers exclu : '
              '+${AkibaMoney.format(month.neutralIn, masked: masked)} reçus, '
              '−${AkibaMoney.format(month.neutralOut, masked: masked)} '
              'reversés.',
              style: AkibaTypography.legend.copyWith(color: c.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    return Text(
      title,
      style: AkibaTypography.sectionTitle.copyWith(color: c.textPrimary),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return AkibaSurfaceCard(
      child: Column(
        children: <Widget>[
          Icon(icon, size: 26, color: c.terracotta),
          const SizedBox(height: AkibaSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: AkibaSpacing.xs),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: AkibaTypography.legend.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Dialogues

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({this.existing});

  final Budget? existing;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final TextEditingController _category = TextEditingController(
    text: widget.existing?.category ?? '',
  );
  late final TextEditingController _limit = TextEditingController(
    text: widget.existing?.monthlyLimit.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _category.dispose();
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AkibaRadii.card),
      ),
      title: Text(
        widget.existing == null ? 'Nouveau plafond' : 'Modifier le plafond',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _category,
              textCapitalization: TextCapitalization.sentences,
              decoration: _input(c, 'Catégorie (ex. Transport)'),
            ),
            const SizedBox(height: AkibaSpacing.md),
            TextField(
              controller: _limit,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: _input(c, 'Plafond mensuel en FCFA'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                _error!,
                style: AkibaTypography.legend.copyWith(color: c.danger),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final String category = _category.text.trim();
            final int limit = int.tryParse(_limit.text) ?? 0;
            if (category.length < 2) {
              setState(() => _error = 'Indiquez une catégorie.');
              return;
            }
            if (limit <= 0) {
              setState(() => _error = 'Le plafond doit dépasser 0 FCFA.');
              return;
            }
            Navigator.of(context).pop((category: category, limit: limit));
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _ReserveDialog extends StatefulWidget {
  const _ReserveDialog({required this.current});

  final int current;

  @override
  State<_ReserveDialog> createState() => _ReserveDialogState();
}

class _ReserveDialogState extends State<_ReserveDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.current == 0 ? '' : widget.current.toString(),
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AkibaRadii.card),
      ),
      title: Text(
        'Réserve de sécurité',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Montant conservé avant de considérer un besoin comme payable.',
            style: AkibaTypography.legend.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: AkibaSpacing.md),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            decoration: _input(c, 'Réserve en FCFA'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(int.tryParse(_amount.text) ?? 0),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _NeedDraft {
  const _NeedDraft({
    required this.label,
    required this.amount,
    required this.priority,
    this.dueDate,
  });

  final String label;
  final int amount;
  final NeedPriority priority;
  final DateTime? dueDate;
}

class _NeedDialog extends StatefulWidget {
  const _NeedDialog();

  @override
  State<_NeedDialog> createState() => _NeedDialogState();
}

class _NeedDialogState extends State<_NeedDialog> {
  final TextEditingController _label = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  NeedPriority _priority = NeedPriority.medium;
  DateTime? _dueDate;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AkibaRadii.card),
      ),
      title: Text(
        'Nouveau besoin',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _label,
              textCapitalization: TextCapitalization.sentences,
              decoration: _input(c, 'Intitulé (ex. Loyer octobre)'),
            ),
            const SizedBox(height: AkibaSpacing.md),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: _input(c, 'Montant en FCFA'),
            ),
            const SizedBox(height: AkibaSpacing.md),
            DropdownButtonFormField<NeedPriority>(
              initialValue: _priority,
              decoration: _input(c, 'Priorité'),
              items: <DropdownMenuItem<NeedPriority>>[
                for (final NeedPriority priority in NeedPriority.values)
                  DropdownMenuItem<NeedPriority>(
                    value: priority,
                    child: Text(priority.label),
                  ),
              ],
              onChanged: (NeedPriority? value) {
                if (value != null) setState(() => _priority = value);
              },
            ),
            const SizedBox(height: AkibaSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  _dueDate == null
                      ? 'Échéance (facultatif)'
                      : 'Échéance : ${AkibaDate.short(_dueDate!)}',
                ),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: AkibaTypography.legend.copyWith(color: c.danger),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final String label = _label.text.trim();
            final int amount = int.tryParse(_amount.text) ?? 0;
            if (label.length < 2) {
              setState(() => _error = 'Donnez un intitulé au besoin.');
              return;
            }
            if (amount <= 0) {
              setState(() => _error = 'Le montant doit dépasser 0 FCFA.');
              return;
            }
            Navigator.of(context).pop(
              _NeedDraft(
                label: label,
                amount: amount,
                priority: _priority,
                dueDate: _dueDate,
              ),
            );
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }
}

InputDecoration _input(AkibaColors c, String hint) => InputDecoration(
  hintText: hint,
  hintStyle: AkibaTypography.body.copyWith(color: c.textMuted),
  filled: true,
  fillColor: c.surfaceElevated,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AkibaSpacing.lg,
    vertical: AkibaSpacing.md,
  ),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AkibaRadii.field),
    borderSide: BorderSide.none,
  ),
);
