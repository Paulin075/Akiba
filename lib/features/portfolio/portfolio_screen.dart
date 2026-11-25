import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/akiba_date.dart';
import '../../core/format/akiba_money.dart';
import '../../core/format/label_icons.dart';
import '../../core/format/transaction_display.dart';
import '../../core/savings/savings_messages.dart';
import '../../core/savings/savings_projection.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/state/masked_amounts.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/account_pill.dart';
import '../../core/widgets/akiba_surface_card.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/icon_circle_button.dart';
import '../../core/widgets/savings_celebration.dart';
import '../../core/widgets/segmented_control.dart';
import '../../core/widgets/transaction_row.dart';
import '../../data/akiba_store.dart';
import '../../data/models/account.dart';
import '../../data/models/debt.dart';
import '../../data/models/savings_pot.dart';
import '../../data/models/third_party.dart';
import '../../data/models/transaction_record.dart';
import '../quick_entry/quick_entry.dart';
import 'movement_detail_sheet.dart';

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

/// Écran Portefeuille : comptes, mouvements et calendrier, épargne, argent de
/// tiers, créances et dettes. Les montants suivent le masquage global.
class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({
    super.key,
    required this.store,
    required this.revision,
    this.segmentRequest,
  });

  final AkibaStore store;
  final AkibaDataRevision revision;

  /// Demande externe de segment (0 comptes, 1 mouvements, 2 épargne,
  /// 3 tiers). L'accueil s'en sert pour ouvrir directement les coffres.
  final ValueNotifier<int>? segmentRequest;

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  int _segment = 0;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _day;
  late Future<_PortfolioData> _future = _load();

  /// Catalogue de messages d'épargne, mémorisé pour éviter la répétition
  /// immédiate et recréé si la langue change.
  SavingsMessages? _savingsMessages;
  String? _savingsLanguage;

  SavingsMessages _messagesFor(AkibaSettings settings) {
    if (_savingsMessages == null || _savingsLanguage != settings.language) {
      _savingsMessages = SavingsMessages(language: settings.language);
      _savingsLanguage = settings.language;
    }
    return _savingsMessages!;
  }

  @override
  void initState() {
    super.initState();
    widget.revision.addListener(_reload);
    widget.segmentRequest?.addListener(_applySegmentRequest);
    _applySegmentRequest();
  }

  @override
  void didUpdateWidget(covariant PortfolioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) _reload();
    if (!identical(oldWidget.segmentRequest, widget.segmentRequest)) {
      oldWidget.segmentRequest?.removeListener(_applySegmentRequest);
      widget.segmentRequest?.addListener(_applySegmentRequest);
      _applySegmentRequest();
    }
  }

  /// Applique le segment demandé depuis l'accueil (Épargne, Mouvements).
  void _applySegmentRequest() {
    final int? requested = widget.segmentRequest?.value;
    if (requested == null || !mounted) return;
    final int next = requested.clamp(0, 3).toInt();
    if (next == _segment) return;
    // Le notifier est modifié depuis un geste (accueil → Épargne), jamais
    // pendant une construction : setState est donc immédiat et fiable.
    setState(() => _segment = next);
  }

  @override
  void dispose() {
    widget.revision.removeListener(_reload);
    widget.segmentRequest?.removeListener(_applySegmentRequest);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    // Future créé hors de `setState` : un callback qui rend un Future est
    // rejeté par Flutter (« returned a Future ») et le portefeuille restait
    // figé après une écriture.
    final Future<_PortfolioData> next = _load();
    setState(() {
      _future = next;
    });
  }

  Future<void> _refresh() async {
    final Future<_PortfolioData> next = _load();
    if (mounted) {
      setState(() {
        _future = next;
      });
    }
    await next;
  }

  Future<_PortfolioData> _load() async {
    final List<AccountBalance> accounts = await widget.store.accountBalances();
    final List<SavingsPotBalance> pots = await widget.store.savingsBalances();
    final List<ThirdPartyBalance> parties = await widget.store
        .thirdPartyBalances();
    final List<Debt> debts = await widget.store.debts();
    final List<TransactionLine> movements = await widget.store.movements(
      from: DateTime(_month.year, _month.month),
      to: DateTime(_month.year, _month.month + 1),
      limit: 500,
    );
    return _PortfolioData(
      accounts: accounts,
      pots: pots,
      parties: parties,
      debts: debts,
      movements: movements,
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

  /// Bandeau de 5 secondes avec retour arrière, sans écriture implicite.
  void _toastUndo(String message, Future<void> Function() undo) {
    final AkibaColors c = AkibaColors.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: c.textPrimary,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Annuler',
            textColor: c.terracottaDeep,
            onPressed: () async {
              await undo();
              widget.revision.bump();
            },
          ),
        ),
      );
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _day = null;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool masked = MaskedAmounts.of(context);

    return FutureBuilder<_PortfolioData>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<_PortfolioData> async) {
        if (async.hasError) {
          return _centeredMessage(
            icon: Icons.lock_outline_rounded,
            title: 'Portefeuille indisponible',
            detail: 'La base locale n’a pas pu être lue.',
          );
        }

        final _PortfolioData? data = async.data;
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
                        'Comptes',
                        'Mouvements',
                        'Épargne',
                        'Tiers',
                      ],
                      selectedIndex: _segment,
                      onChanged: (int index) =>
                          setState(() => _segment = index),
                    ),
                    const SizedBox(height: AkibaSpacing.xl),
                    if (data == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: AkibaSpacing.xxxl,
                        ),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...<Widget>[
                      if (_segment == 0) _accountsTab(data, masked),
                      if (_segment == 1) _movementsTab(data, masked),
                      if (_segment == 2) _savingsTab(data, masked),
                      if (_segment == 3) _tiersTab(data, masked),
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

  // ---------------------------------------------------------------- Comptes

  Widget _accountsTab(_PortfolioData data, bool masked) {
    final int total = data.accounts.fold<int>(
      0,
      (int sum, AccountBalance item) => sum + item.balance,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TotalCard(
          label: 'TOTAL DES COMPTES',
          amount: total,
          masked: masked,
          caption: 'Chaque solde est recalculé depuis vos mouvements.',
        ),
        const SizedBox(height: AkibaSpacing.xl),
        const _SectionTitle('Vos comptes'),
        const SizedBox(height: AkibaSpacing.md),
        if (data.accounts.isEmpty)
          const _EmptyCard(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Aucun compte',
            detail: 'Ajoutez Liquide, Flooz, Mixx by Yas ou Orabank.',
          )
        else
          for (final AccountBalance item in data.accounts)
            Padding(
              padding: const EdgeInsets.only(bottom: AkibaSpacing.md),
              child: AkibaSurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AkibaSpacing.lg,
                  vertical: AkibaSpacing.sm,
                ),
                child: AccountBadge(
                  brand: item.account.brand,
                  name: item.account.name,
                  subtitle: item.account.brand.label,
                  amountLabel: AkibaMoney.format(item.balance, masked: masked),
                  onTap: () => _editAccount(item),
                ),
              ),
            ),
        const SizedBox(height: AkibaSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => _editAccount(null),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Ajouter un compte'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- Mouvements

  Widget _movementsTab(_PortfolioData data, bool masked) {
    final Set<int> marked = <int>{
      for (final TransactionLine line in data.movements)
        if (_sameMonth(line.transaction.occurredAt.toLocal(), _month))
          line.transaction.occurredAt.toLocal().day,
    };

    final List<TransactionLine> visible = _day == null
        ? data.movements
        : data.movements
              .where(
                (TransactionLine line) =>
                    _sameDay(line.transaction.occurredAt.toLocal(), _day!),
              )
              .toList(growable: false);

    final Map<DateTime, List<TransactionLine>> groups =
        <DateTime, List<TransactionLine>>{};
    for (final TransactionLine line in visible) {
      final DateTime local = line.transaction.occurredAt.toLocal();
      final DateTime key = DateTime(local.year, local.month, local.day);
      groups.putIfAbsent(key, () => <TransactionLine>[]).add(line);
    }

    final AkibaColors c = AkibaColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              tooltip: 'Mois précédent',
              onPressed: () => _shiftMonth(-1),
              icon: Icon(Icons.chevron_left_rounded, color: c.textPrimary),
            ),
            Expanded(
              child: Text(
                '${_capitalize(_monthNames[_month.month - 1])} ${_month.year}',
                textAlign: TextAlign.center,
                style: AkibaTypography.sectionTitle.copyWith(
                  color: c.textPrimary,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Mois suivant',
              onPressed: () => _shiftMonth(1),
              icon: Icon(Icons.chevron_right_rounded, color: c.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: AkibaSpacing.sm),
        AkibaSurfaceCard(
          padding: const EdgeInsets.all(AkibaSpacing.md),
          child: _MonthCalendar(
            month: _month,
            markedDays: marked,
            selectedDay: _day,
            onSelect: (DateTime? day) => setState(() => _day = day),
          ),
        ),
        const SizedBox(height: AkibaSpacing.lg),
        Row(
          children: <Widget>[
            Expanded(
              child: _SectionTitle(
                _day == null
                    ? 'Mouvements du mois'
                    : 'Mouvements du ${AkibaDate.short(_day!)}',
              ),
            ),
            if (_day != null)
              TextButton(
                onPressed: () => setState(() => _day = null),
                child: const Text('Tout afficher'),
              ),
          ],
        ),
        const SizedBox(height: AkibaSpacing.sm),
        if (visible.isEmpty)
          const _EmptyCard(
            icon: Icons.event_note_rounded,
            title: 'Aucun mouvement',
            detail: 'Rien n’a été enregistré sur cette période.',
          )
        else
          for (final MapEntry<DateTime, List<TransactionLine>> group
              in groups.entries) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(
                top: AkibaSpacing.md,
                bottom: AkibaSpacing.xs,
              ),
              child: Text(
                AkibaDate.dayLabel(group.key),
                style: AkibaTypography.label.copyWith(
                  color: c.textMuted,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            AkibaSurfaceCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AkibaSpacing.lg,
                vertical: AkibaSpacing.xs,
              ),
              child: Column(
                children: <Widget>[
                  for (final TransactionLine line in group.value)
                    TransactionRow(
                      icon: TransactionDisplay.iconFor(line.transaction),
                      title: TransactionDisplay.titleFor(line.transaction),
                      subtitle: TransactionDisplay.subtitleFor(
                        line.transaction,
                      ),
                      amountLabel: AkibaMoney.formatSigned(
                        line.transaction.amount,
                        masked: masked,
                      ),
                      amountColor: TransactionDisplay.amountColor(
                        line.transaction,
                        c,
                      ),
                      badge: line.transaction.isNeutral ? 'Tiers' : null,
                      onTap: () => _openMovement(line, masked: masked),
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }

  // ----------------------------------------------------------------- Épargne

  Widget _savingsTab(_PortfolioData data, bool masked) {
    final AkibaColors c = AkibaColors.of(context);
    final AkibaSettings settings = AkibaSettingsScope.of(context);
    final int total = data.pots.fold<int>(
      0,
      (int sum, SavingsPotBalance pot) => sum + pot.held,
    );
    final int goalPercent = settings.savingsGoalPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TotalCard(
          label: 'ÉPARGNE TOTALE',
          amount: total,
          masked: masked,
          caption:
              'Un versement sort du compte mais reste à vous : le solde '
              'disponible ne change pas.',
        ),
        const SizedBox(height: AkibaSpacing.xl),
        AkibaSurfaceCard(
          padding: const EdgeInsets.all(AkibaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'PROPOSITION DE VERSEMENT',
                style: AkibaTypography.label.copyWith(
                  color: c.textMuted,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                'Au moment de verser, AKIBA propose cette part du solde du '
                'compte choisi. Aucun versement n’est automatique : vous '
                'relisez le montant.',
                style: AkibaTypography.legend.copyWith(
                  color: c.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AkibaSpacing.md),
              SegmentedControl(
                segments: const <String>['0 %', '10 %', '20 %', '30 %'],
                selectedIndex: (goalPercent ~/ 10).clamp(0, 3),
                onChanged: (int index) =>
                    settings.set('savings_goal_percent', '${index * 10}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AkibaSpacing.xl),
        const _SectionTitle('Coffres et objectifs'),
        const SizedBox(height: AkibaSpacing.md),
        if (data.pots.isEmpty)
          const _EmptyCard(
            icon: Icons.savings_outlined,
            title: 'Aucun coffre',
            detail:
                'Créez un fonds d’urgence ou un objectif pour commencer à '
                'épargner.',
          )
        else
          for (final SavingsPotBalance pot in data.pots)
            Padding(
              padding: const EdgeInsets.only(bottom: AkibaSpacing.md),
              child: _SavingsCard(
                pot: pot,
                masked: masked,
                onDeposit: () => _moveSavings(pot, deposit: true),
                onWithdraw: () => _moveSavings(pot, deposit: false),
              ),
            ),
        const SizedBox(height: AkibaSpacing.sm),
        OutlinedButton.icon(
          onPressed: _addSavings,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Créer un coffre'),
        ),
      ],
    );
  }

  // ------------------------------------------------------- Tiers et dettes

  Widget _tiersTab(_PortfolioData data, bool masked) {
    final AkibaColors c = AkibaColors.of(context);
    final int held = data.parties.fold<int>(
      0,
      (int sum, ThirdPartyBalance party) => sum + party.held,
    );
    final int owedToMe = data.debts
        .where((Debt d) => d.direction == DebtDirection.owedToMe)
        .fold<int>(0, (int sum, Debt d) => sum + d.remaining);
    final int iOwe = data.debts
        .where((Debt d) => d.direction == DebtDirection.iOwe)
        .fold<int>(0, (int sum, Debt d) => sum + d.remaining);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TotalCard(
          label: 'ARGENT DE TIERS DÉTENU',
          amount: held,
          masked: masked,
          caption:
              'Cet argent n’est pas à vous : il est exclu du solde '
              'disponible, du budget et des statistiques.',
        ),
        const SizedBox(height: AkibaSpacing.xl),
        const _SectionTitle('Tiers'),
        const SizedBox(height: AkibaSpacing.md),
        if (data.parties.isEmpty)
          const _EmptyCard(
            icon: Icons.groups_outlined,
            title: 'Aucun tiers',
            detail:
                'Une entrée « Tiers » (cotisation, avance client) apparaîtra '
                'ici.',
          )
        else
          for (final ThirdPartyBalance party in data.parties)
            Padding(
              padding: const EdgeInsets.only(bottom: AkibaSpacing.md),
              child: AkibaSurfaceCard(
                padding: const EdgeInsets.all(AkibaSpacing.lg),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            party.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AkibaMoney.format(party.held, masked: masked),
                            style: AkibaTypography.money(
                              14,
                              weight: FontWeight.w600,
                              color: c.terracotta,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (party.held > 0)
                      TextButton(
                        onPressed: () => _reverse(party),
                        child: const Text('Reverser'),
                      ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: AkibaSpacing.xl),
        const _SectionTitle('Créances et dettes'),
        const SizedBox(height: AkibaSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: _MetricCard(
                label: 'On me doit',
                amount: owedToMe,
                masked: masked,
                color: c.success,
                icon: Icons.call_received_rounded,
              ),
            ),
            const SizedBox(width: AkibaSpacing.md),
            Expanded(
              child: _MetricCard(
                label: 'Je dois',
                amount: iOwe,
                masked: masked,
                color: c.danger,
                icon: Icons.call_made_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: AkibaSpacing.md),
        if (data.debts.isEmpty)
          const _EmptyCard(
            icon: Icons.handshake_outlined,
            title: 'Aucune créance ni dette',
            detail: 'Ces montants restent distincts du solde disponible.',
          )
        else
          ..._debtGroups(c, data.debts, masked),
        const SizedBox(height: AkibaSpacing.sm),
        OutlinedButton.icon(
          onPressed: _addDebt,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Ajouter une créance ou une dette'),
        ),
        const SizedBox(height: AkibaSpacing.md),
        Text(
          'Tant qu’elles ne sont pas réglées, les créances et dettes restent '
          'hors du solde disponible. Au règlement, l’encaissement entre sur le '
          'compte choisi, et le paiement en sort.',
          style: AkibaTypography.legend.copyWith(color: c.textMuted),
        ),
      ],
    );
  }

  /// Regroupe les créances et dettes par contact (nom, casse ignorée).
  List<Widget> _debtGroups(AkibaColors c, List<Debt> debts, bool masked) {
    final Map<String, List<Debt>> groups = <String, List<Debt>>{};
    for (final Debt debt in debts) {
      final String key = debt.counterparty.trim().toLowerCase();
      groups.putIfAbsent(key, () => <Debt>[]).add(debt);
    }
    final List<String> keys = groups.keys.toList()..sort();

    return <Widget>[
      for (final String key in keys)
        Padding(
          padding: const EdgeInsets.only(bottom: AkibaSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      groups[key]!.first.counterparty,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AkibaSpacing.sm),
                  Flexible(
                    child: Text(
                      _groupSummary(groups[key]!, masked),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: AkibaTypography.legend.copyWith(
                        color: c.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AkibaSpacing.xs),
              for (final Debt debt in groups[key]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: AkibaSpacing.xs),
                  child: _DebtTile(
                    debt: debt,
                    masked: masked,
                    showCounterparty: false,
                    onSettle: debt.isSettled
                        ? null
                        : () => _settleDebt(debt, masked: masked),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  String _groupSummary(List<Debt> debts, bool masked) {
    int owedToMe = 0;
    int iOwe = 0;
    for (final Debt debt in debts) {
      if (debt.direction == DebtDirection.owedToMe) {
        owedToMe += debt.remaining;
      } else {
        iOwe += debt.remaining;
      }
    }
    if (owedToMe == 0 && iOwe == 0) return 'soldé';
    return <String>[
      if (owedToMe > 0)
        'On me doit ${AkibaMoney.format(owedToMe, masked: masked)}',
      if (iOwe > 0) 'Je dois ${AkibaMoney.format(iOwe, masked: masked)}',
    ].join(' · ');
  }

  // ----------------------------------------------------------- Interactions

  /// Fiche de détail : reclassement sur place, puis éventuellement la saisie
  /// complète si la personne choisit « Modifier ».
  Future<void> _openMovement(
    TransactionLine line, {
    required bool masked,
  }) async {
    final MovementDetailAction? action = await showMovementDetail(
      context,
      line: line,
      store: widget.store,
      revision: widget.revision,
      masked: masked,
    );
    if (!mounted || action == null) return;
    if (action == MovementDetailAction.edit) await _editMovement(line);
  }

  Future<void> _editMovement(TransactionLine line) async {
    final QuickEntryMode? mode = quickEntryModeFor(line.transaction);
    if (mode == null) {
      _toast('Un mouvement d’épargne se gère depuis l’onglet Épargne.');
      return;
    }
    await openQuickEntry(
      context,
      store: widget.store,
      revision: widget.revision,
      mode: mode,
      editing: line,
    );
  }

  Future<void> _editAccount(AccountBalance? existing) async {
    final _AccountDraft? draft = await showDialog<_AccountDraft>(
      context: context,
      builder: (BuildContext context) => _AccountDialog(
        initialName: existing?.account.name,
        initialBrand: existing?.account.brand,
      ),
    );
    if (draft == null || !mounted) return;

    final DateTime now = DateTime.now();
    await widget.store.saveAccount(
      Account(
        id: existing?.account.id ?? 'acc-${now.microsecondsSinceEpoch}',
        name: draft.name,
        brand: draft.brand,
        createdAt: existing?.account.createdAt ?? now,
      ),
    );
    widget.revision.bump();
  }

  Future<void> _addSavings() async {
    final _SavingsDraft? draft = await showDialog<_SavingsDraft>(
      context: context,
      builder: (BuildContext context) => const _SavingsDialog(),
    );
    if (draft == null || !mounted) return;

    final DateTime now = DateTime.now();
    await widget.store.saveSavingsPot(
      SavingsPot(
        id: 'pot-${now.microsecondsSinceEpoch}',
        name: draft.name,
        kind: draft.kind,
        targetAmount: draft.target,
        createdAt: now,
      ),
    );
    widget.revision.bump();
  }

  Future<void> _moveSavings(
    SavingsPotBalance pot, {
    required bool deposit,
  }) async {
    final bool masked = MaskedAmounts.of(context);
    final AkibaSettings settings = AkibaSettingsScope.of(context);
    final int suggestPercent = settings.savingsGoalPercent;
    final List<AccountBalance> accounts = await widget.store.accountBalances();
    if (!mounted) return;
    if (accounts.isEmpty) {
      _toast('Ajoutez d’abord un compte dans l’onglet Comptes.');
      return;
    }
    if (!deposit && pot.held <= 0) {
      _toast('Ce coffre est vide : rien à retirer.');
      return;
    }

    final ({int amount, String accountId})? result = await _askAmount(
      context,
      title: deposit ? 'Verser au coffre' : 'Retirer du coffre',
      accounts: accounts,
      maxAmount: deposit ? null : pot.held,
      initialAmount: deposit ? null : pot.held,
      suggestPercent: deposit ? suggestPercent : null,
      helper: deposit
          ? 'Le montant sort du compte et reste à vous dans le coffre. La '
                'proposition suit la part choisie dans l’onglet Épargne '
                '(0 à 30 %).'
          : 'Le retrait revient sur le compte choisi.',
      confirmLabel: deposit ? 'Verser' : 'Retirer',
    );
    if (result == null || !mounted) return;

    final DateTime now = DateTime.now();
    await widget.store.saveTransaction(
      TransactionRecord(
        id: 'tx-${now.microsecondsSinceEpoch}',
        accountId: result.accountId,
        amount: deposit ? -result.amount : result.amount,
        kind: TransactionKind.savings,
        savingsPotId: pot.pot.id,
        note: deposit ? 'Versement épargne' : 'Retrait épargne',
        occurredAt: now,
        createdAt: now,
      ),
    );
    widget.revision.bump();
    if (deposit && mounted) {
      final int percent = pot.pot.targetAmount > 0
          ? ((pot.held + result.amount) * 100 / pot.pot.targetAmount)
                .clamp(0, 999)
                .round()
          : 0;
      final SavingsMessages messages = _messagesFor(settings);
      final String local = messages.next(
        SavingsMessageKind.encouragement,
        potName: pot.pot.name,
      );
      // Enrichissement optionnel : si l'IA est configurée et joignable, sa
      // phrase remplace le message local ; sinon le local reste affiché.
      final Future<String?>? ai = settings.aiRemoteEnabled
          ? SavingsCoach()
                .enrich(
                  settings: settings,
                  kind: SavingsMessageKind.encouragement,
                  localMessage: local,
                  potName: pot.pot.name,
                )
                .then((SavingsCoachResult r) => r.fromAi ? r.message : null)
          : null;
      await showSavingsCelebration(
        context,
        potName: pot.pot.name,
        progressPercent: masked ? 0 : percent,
        cauriCount: SavingsProjection.cauriCountForAmount(result.amount),
        message: local,
        aiMessage: ai,
      );
      return;
    }
    if (!deposit) {
      // Taquinerie locale immédiate, sans montant (donc compatible avec le
      // masquage) et sans bloquer l'écriture déjà enregistrée.
      final String taunt = _messagesFor(
        settings,
      ).next(SavingsMessageKind.withdrawal, potName: pot.pot.name);
      _toast(taunt);
      return;
    }
    _toast('Versement enregistré.');
  }

  Future<void> _reverse(ThirdPartyBalance party) async {
    if (party.held <= 0) {
      _toast('Rien à reverser pour ce tiers.');
      return;
    }
    final List<AccountBalance> accounts = await widget.store.accountBalances();
    if (!mounted) return;
    if (accounts.isEmpty) {
      _toast('Ajoutez d’abord un compte dans l’onglet Comptes.');
      return;
    }

    final ({int amount, String accountId})? result = await _askAmount(
      context,
      title: 'Reverser à ${party.name}',
      accounts: accounts,
      maxAmount: party.held,
      initialAmount: party.held,
      helper: 'Le reversement ne peut pas dépasser l’argent détenu.',
      confirmLabel: 'Reverser',
    );
    if (result == null || !mounted) return;

    final DateTime now = DateTime.now();
    await widget.store.saveTransaction(
      TransactionRecord(
        id: 'tx-${now.microsecondsSinceEpoch}',
        accountId: result.accountId,
        amount: -result.amount,
        kind: TransactionKind.expense,
        note: 'Reversement ${party.name}',
        occurredAt: now,
        createdAt: now,
        isNeutral: true,
        thirdPartyId: party.id,
      ),
    );
    widget.revision.bump();
    _toast('Reversement enregistré.');
  }

  Future<void> _settleDebt(Debt debt, {required bool masked}) async {
    final List<AccountBalance> accounts = await widget.store.accountBalances();
    if (!mounted) return;
    if (accounts.isEmpty) {
      _toast('Ajoutez d’abord un compte dans l’onglet Comptes.');
      return;
    }
    final bool received = debt.direction == DebtDirection.owedToMe;
    final ({int amount, String accountId})? result = await _askAmount(
      context,
      title: 'Régler ${debt.counterparty}',
      accounts: accounts,
      maxAmount: debt.remaining,
      initialAmount: debt.remaining,
      helper: received
          ? 'Reste dû : ${AkibaMoney.format(debt.remaining, masked: masked)}. '
                'L’encaissement entre sur le compte choisi et augmente le '
                'solde disponible.'
          : 'Reste dû : ${AkibaMoney.format(debt.remaining, masked: masked)}. '
                'Le paiement sort du compte choisi.',
      confirmLabel: received ? 'Encaisser' : 'Payer',
    );
    if (result == null || !mounted) return;

    try {
      final TransactionRecord movement = await widget.store.settleDebt(
        debt,
        amount: result.amount,
        accountId: result.accountId,
      );
      widget.revision.bump();
      _toastUndo(
        received
            ? 'Créance encaissée : le solde disponible a été augmenté.'
            : 'Dette payée : le montant a été retiré du compte choisi.',
        () async {
          // Annulation complète : le mouvement de trésorerie disparaît et le
          // reste dû revient à son état précédent.
          await widget.store.deleteTransaction(movement);
          await widget.store.saveDebt(debt);
          widget.revision.bump();
        },
      );
    } catch (_) {
      _toast('Règlement impossible : vérifiez le montant et le compte.');
    }
  }

  Future<void> _addDebt() async {
    final List<AccountBalance> accounts = await widget.store.accountBalances();
    if (!mounted) return;
    final _DebtDraft? draft = await showDialog<_DebtDraft>(
      context: context,
      builder: (BuildContext context) => _DebtDialog(accounts: accounts),
    );
    if (draft == null || !mounted) return;

    final DateTime now = DateTime.now();
    final Debt debt = Debt(
      id: 'debt-${now.microsecondsSinceEpoch}',
      direction: draft.direction,
      counterparty: draft.counterparty,
      principal: draft.amount,
      dueDate: draft.dueDate,
      createdAt: now,
    );
    await widget.store.saveDebt(debt);

    TransactionRecord? movement;
    final String? accountId = draft.accountId;
    if (draft.withMovement && accountId != null && accountId.isNotEmpty) {
      final bool borrowed = draft.direction == DebtDirection.iOwe;
      movement = TransactionRecord(
        id: 'tx-${now.microsecondsSinceEpoch}',
        accountId: accountId,
        amount: borrowed ? draft.amount : -draft.amount,
        kind: borrowed ? TransactionKind.income : TransactionKind.expense,
        note: borrowed
            ? 'Emprunt reçu · ${draft.counterparty}'
            : 'Prêt accordé · ${draft.counterparty}',
        // Argent emprunté : présent sur le compte, mais dû. La marque neutre
        // l'exclut du solde disponible, du budget et des statistiques.
        isNeutral: borrowed,
        occurredAt: now,
        createdAt: now,
      );
      await widget.store.saveTransaction(movement);
    }
    widget.revision.bump();

    final TransactionRecord? savedMovement = movement;
    _toastUndo(
      savedMovement == null
          ? 'Créance enregistrée.'
          : 'Créance enregistrée avec son mouvement.',
      () async {
        await widget.store.deleteDebt(debt.id);
        if (savedMovement != null) {
          await widget.store.deleteTransaction(savedMovement);
        }
      },
    );
  }

  Widget _centeredMessage({
    required IconData icon,
    required String title,
    required String detail,
  }) {
    final AkibaColors c = AkibaColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AkibaSpacing.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 30, color: c.danger),
            const SizedBox(height: AkibaSpacing.md),
            Text(
              title,
              style: AkibaTypography.sectionTitle.copyWith(
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AkibaSpacing.xs),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: AkibaTypography.body.copyWith(color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}

class _PortfolioData {
  const _PortfolioData({
    required this.accounts,
    required this.pots,
    required this.parties,
    required this.debts,
    required this.movements,
  });

  final List<AccountBalance> accounts;
  final List<SavingsPotBalance> pots;
  final List<ThirdPartyBalance> parties;
  final List<Debt> debts;
  final List<TransactionLine> movements;
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
                'PORTEFEUILLE',
                style: AkibaTypography.label.copyWith(
                  color: c.textMuted,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: AkibaSpacing.xs),
              Text(
                'Mes comptes',
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

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.amount,
    required this.masked,
    required this.caption,
  });

  final String label;
  final int amount;
  final bool masked;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return AkibaSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
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
              AkibaMoney.format(amount, masked: masked),
              style: AkibaTypography.money(30, color: c.textPrimary),
            ),
          ),
          const SizedBox(height: AkibaSpacing.sm),
          Text(
            caption,
            style: AkibaTypography.legend.copyWith(
              color: c.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Jauge d'épargne avec repères 25/50/75/100 % et retour haptique quand un
/// palier est franchi. La durée tombe à zéro si « Réduire les animations »
/// est actif.
class _SavingsGauge extends StatefulWidget {
  const _SavingsGauge({
    required this.value,
    required this.color,
    required this.track,
  });

  final double value;
  final Color color;
  final Color track;

  @override
  State<_SavingsGauge> createState() => _SavingsGaugeState();
}

class _SavingsGaugeState extends State<_SavingsGauge> {
  int _lastTier = 0;

  static int _tierOf(double ratio) {
    if (ratio >= 1) return 4;
    if (ratio >= 0.75) return 3;
    if (ratio >= 0.5) return 2;
    if (ratio >= 0.25) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final int tier = _tierOf(widget.value);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: widget.value),
      duration: Duration(milliseconds: reduced ? 0 : 600),
      curve: reduced ? Curves.linear : Curves.easeOutBack,
      onEnd: () {
        if (tier > _lastTier && tier > 0) HapticFeedback.lightImpact();
        _lastTier = tier;
      },
      builder: (BuildContext context, double value, Widget? child) {
        return Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(AkibaRadii.pill),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 10,
                backgroundColor: widget.track,
                valueColor: AlwaysStoppedAnimation<Color>(widget.color),
              ),
            ),
            for (final double marker in const <double>[0.25, 0.5, 0.75])
              Align(
                alignment: Alignment(marker * 2 - 1, 0),
                child: Container(
                  width: 2,
                  height: 12,
                  color: value >= marker
                      ? widget.color.withValues(alpha: 0.9)
                      : widget.track,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SavingsCard extends StatelessWidget {
  const _SavingsCard({
    required this.pot,
    required this.masked,
    required this.onDeposit,
    required this.onWithdraw,
  });

  final SavingsPotBalance pot;
  final bool masked;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final Color gauge = pot.isReached ? c.success : c.terracotta;
    final bool hasTarget = pot.pot.targetAmount > 0;
    // Date d'atteinte dynamique : rythme observé depuis la création du coffre.
    final DateTime? eta = hasTarget
        ? SavingsProjection.estimateTargetDate(
            held: pot.held,
            target: pot.pot.targetAmount,
            createdAt: pot.pot.createdAt,
            now: DateTime.now(),
          )
        : null;

    return AkibaSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.iconTile,
                  borderRadius: BorderRadius.circular(AkibaRadii.iconTile),
                ),
                child: Icon(
                  LabelIcons.forText(pot.pot.name),
                  size: 18,
                  color: c.terracottaDeep,
                ),
              ),
              const SizedBox(width: AkibaSpacing.sm),
              Expanded(
                child: Text(
                  pot.pot.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ),
              _KindPill(label: _kindLabel(pot.pot.kind)),
            ],
          ),
          const SizedBox(height: AkibaSpacing.md),
          // Montants longs (« 1 250 000 FCFA sur 3 000 000 FCFA ») : le texte
          // réduit son corps au lieu de déborder sur petit écran.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    hasTarget
                        ? '${AkibaMoney.format(pot.held, masked: masked)} '
                              'sur ${AkibaMoney.format(pot.pot.targetAmount, masked: masked)}'
                        : AkibaMoney.format(pot.held, masked: masked),
                    maxLines: 1,
                    style: AkibaTypography.money(17, color: c.textPrimary),
                  ),
                ),
              ),
              if (hasTarget) ...<Widget>[
                const SizedBox(width: AkibaSpacing.sm),
                Text(
                  masked ? '••• %' : AkibaMoney.percent(pot.ratio * 100),
                  style: AkibaTypography.money(
                    14,
                    weight: FontWeight.w600,
                    color: gauge,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AkibaSpacing.sm),
          _SavingsGauge(
            value: hasTarget ? pot.progress : 0,
            color: gauge,
            track: c.surfaceElevated,
          ),
          const SizedBox(height: AkibaSpacing.sm),
          // `Wrap` évite le RenderFlex overflow : les boutons passent à la
          // ligne suivante au lieu de déborder sur 320-360 px.
          Wrap(
            spacing: AkibaSpacing.sm,
            runSpacing: AkibaSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TextButton.icon(
                onPressed: onDeposit,
                style: TextButton.styleFrom(foregroundColor: c.terracottaDeep),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Verser'),
              ),
              TextButton.icon(
                onPressed: onWithdraw,
                style: TextButton.styleFrom(foregroundColor: c.textMuted),
                icon: const Icon(Icons.remove_rounded, size: 18),
                label: const Text('Retirer'),
              ),
              if (pot.pot.targetDate != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AkibaSpacing.xs,
                  ),
                  child: Text(
                    'Jusqu’au ${AkibaDate.short(pot.pot.targetDate!)}',
                    style: AkibaTypography.legend.copyWith(
                      color: c.textMuted,
                      fontSize: 11,
                    ),
                  ),
                )
              else if (eta != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AkibaSpacing.xs,
                  ),
                  child: Text(
                    'À ce rythme : ${AkibaDate.short(eta)}',
                    style: AkibaTypography.legend.copyWith(
                      color: c.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Libellés courts : la pastille ne doit jamais pousser le nom du coffre
  /// hors de la carte sur un écran de 320 px.
  static String _kindLabel(SavingsKind kind) => switch (kind) {
    SavingsKind.emergency => 'Urgence',
    SavingsKind.goal => 'Objectif',
    SavingsKind.free => 'Libre',
  };
}

class _DebtTile extends StatelessWidget {
  const _DebtTile({
    required this.debt,
    required this.masked,
    this.onSettle,
    this.showCounterparty = true,
  });

  final Debt debt;
  final bool masked;
  final VoidCallback? onSettle;
  final bool showCounterparty;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final bool owedToMe = debt.direction == DebtDirection.owedToMe;
    final DebtStatus status = debt.statusAt(DateTime.now());

    return AkibaSurfaceCard(
      padding: const EdgeInsets.all(AkibaSpacing.lg),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.iconTile,
              borderRadius: BorderRadius.circular(AkibaRadii.iconTile),
            ),
            child: Icon(
              owedToMe ? Icons.call_received_rounded : Icons.call_made_rounded,
              size: 18,
              color: owedToMe ? c.success : c.danger,
            ),
          ),
          const SizedBox(width: AkibaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  showCounterparty
                      ? debt.counterparty
                      : (owedToMe ? 'On me doit' : 'Je dois'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    if (showCounterparty) (owedToMe ? 'On me doit' : 'Je dois'),
                    status.label,
                    if (debt.settledAmount > 0 && !debt.isSettled)
                      '${debt.progressPercent} % réglé',
                    if (debt.dueDate != null)
                      'échéance ${AkibaDate.short(debt.dueDate!)}',
                  ].join(' · '),
                  style: AkibaTypography.legend.copyWith(
                    color: status == DebtStatus.overdue
                        ? c.danger
                        : c.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AkibaSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                AkibaMoney.format(debt.remaining, masked: masked),
                style: AkibaTypography.money(
                  15,
                  weight: FontWeight.w600,
                  color: debt.isSettled ? c.textMuted : c.textPrimary,
                ),
              ),
              if (onSettle != null)
                TextButton(
                  onPressed: onSettle,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    foregroundColor: c.terracottaDeep,
                  ),
                  child: const Text('Régler'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.amount,
    required this.masked,
    required this.color,
    required this.icon,
  });

  final String label;
  final int amount;
  final bool masked;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return AkibaSurfaceCard(
      padding: const EdgeInsets.all(AkibaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(height: AkibaSpacing.sm),
          Text(
            label,
            style: AkibaTypography.legend.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              AkibaMoney.format(amount, masked: masked),
              style: AkibaTypography.money(17, color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AkibaSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: c.iconTile,
        borderRadius: BorderRadius.circular(AkibaRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: c.terracottaDeep,
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.markedDays,
    required this.selectedDay,
    required this.onSelect,
  });

  final DateTime month;
  final Set<int> markedDays;
  final DateTime? selectedDay;
  final ValueChanged<DateTime?> onSelect;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final int days = DateTime(month.year, month.month + 1, 0).day;
    final int leading = DateTime(month.year, month.month, 1).weekday - 1;
    const List<String> weekdays = <String>['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    final List<Widget> cells = <Widget>[
      for (final String day in weekdays)
        Expanded(
          child: Center(
            child: Text(
              day,
              style: AkibaTypography.label.copyWith(
                color: c.textMuted,
                fontSize: 10,
              ),
            ),
          ),
        ),
    ];

    final List<Widget?> slots = <Widget?>[
      for (int i = 0; i < leading; i++) null,
      for (int day = 1; day <= days; day++)
        _CalendarDay(
          day: day,
          marked: markedDays.contains(day),
          selected:
              selectedDay != null &&
              selectedDay!.year == month.year &&
              selectedDay!.month == month.month &&
              selectedDay!.day == day,
          onTap: () {
            final bool same =
                selectedDay != null &&
                selectedDay!.year == month.year &&
                selectedDay!.month == month.month &&
                selectedDay!.day == day;
            onSelect(same ? null : DateTime(month.year, month.month, day));
          },
        ),
    ];

    final List<Widget> rows = <Widget>[Row(children: cells)];
    for (int i = 0; i < slots.length; i += 7) {
      rows.add(
        Row(
          children: <Widget>[
            for (int j = 0; j < 7; j++)
              Expanded(
                child: i + j < slots.length
                    ? (slots[i + j] ?? const SizedBox(height: 42))
                    : const SizedBox(height: 42),
              ),
          ],
        ),
      );
    }

    return Column(children: rows);
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.marked,
    required this.selected,
    required this.onTap,
  });

  final int day;
  final bool marked;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: '$day',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 42,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: selected
                ? c.terracotta
                : marked
                ? c.iconTile
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '$day',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? c.onTerracotta : c.textPrimary,
                ),
              ),
              if (marked)
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: selected ? c.onTerracotta : c.terracotta,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
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

// ------------------------------------------------------------------ Dialogues

class _AccountDraft {
  const _AccountDraft({required this.name, required this.brand});

  final String name;
  final AccountBrand brand;
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({this.initialName, this.initialBrand});

  final String? initialName;
  final AccountBrand? initialBrand;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName ?? '',
  );
  late AccountBrand _brand = widget.initialBrand ?? AccountBrand.liquide;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
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
        widget.initialName == null ? 'Ajouter un compte' : 'Modifier le compte',
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
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: _input(c, 'Nom du compte'),
            ),
            const SizedBox(height: AkibaSpacing.md),
            DropdownButtonFormField<AccountBrand>(
              initialValue: _brand,
              decoration: _input(c, 'Support'),
              items: <DropdownMenuItem<AccountBrand>>[
                for (final AccountBrand brand in AccountBrand.values)
                  DropdownMenuItem<AccountBrand>(
                    value: brand,
                    child: Text(brand.label),
                  ),
              ],
              onChanged: (AccountBrand? value) {
                if (value != null) setState(() => _brand = value);
              },
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
            final String name = _name.text.trim();
            if (name.length < 2) {
              setState(() => _error = 'Le nom doit faire au moins 2 lettres.');
              return;
            }
            Navigator.of(context).pop(_AccountDraft(name: name, brand: _brand));
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _SavingsDraft {
  const _SavingsDraft({
    required this.name,
    required this.kind,
    required this.target,
  });

  final String name;
  final SavingsKind kind;
  final int target;
}

class _SavingsDialog extends StatefulWidget {
  const _SavingsDialog();

  @override
  State<_SavingsDialog> createState() => _SavingsDialogState();
}

class _SavingsDialogState extends State<_SavingsDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _target = TextEditingController();
  SavingsKind _kind = SavingsKind.goal;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
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
        'Créer un coffre',
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
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: _input(c, 'Nom (ex. Voyage, Fonds d’urgence)'),
            ),
            const SizedBox(height: AkibaSpacing.md),
            DropdownButtonFormField<SavingsKind>(
              initialValue: _kind,
              decoration: _input(c, 'Type'),
              items: const <DropdownMenuItem<SavingsKind>>[
                DropdownMenuItem<SavingsKind>(
                  value: SavingsKind.emergency,
                  child: Text('Fonds d’urgence'),
                ),
                DropdownMenuItem<SavingsKind>(
                  value: SavingsKind.goal,
                  child: Text('Objectif'),
                ),
                DropdownMenuItem<SavingsKind>(
                  value: SavingsKind.free,
                  child: Text('Épargne libre'),
                ),
              ],
              onChanged: (SavingsKind? value) {
                if (value != null) setState(() => _kind = value);
              },
            ),
            const SizedBox(height: AkibaSpacing.md),
            TextField(
              controller: _target,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: _input(c, 'Objectif en FCFA (facultatif)'),
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
            final String name = _name.text.trim();
            if (name.length < 2) {
              setState(() => _error = 'Donnez un nom au coffre.');
              return;
            }
            Navigator.of(context).pop(
              _SavingsDraft(
                name: name,
                kind: _kind,
                target: int.tryParse(_target.text) ?? 0,
              ),
            );
          },
          child: const Text('Créer'),
        ),
      ],
    );
  }
}

class _DebtDraft {
  const _DebtDraft({
    required this.direction,
    required this.counterparty,
    required this.amount,
    this.dueDate,
    this.withMovement = false,
    this.accountId,
  });

  final DebtDirection direction;
  final String counterparty;
  final int amount;
  final DateTime? dueDate;

  /// Vrai quand le prêt ou l'emprunt déplace réellement de l'argent.
  final bool withMovement;
  final String? accountId;
}

class _DebtDialog extends StatefulWidget {
  const _DebtDialog({required this.accounts});

  final List<AccountBalance> accounts;

  @override
  State<_DebtDialog> createState() => _DebtDialogState();
}

class _DebtDialogState extends State<_DebtDialog> {
  final TextEditingController _counterparty = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  DebtDirection _direction = DebtDirection.owedToMe;
  DateTime? _dueDate;
  bool _withMovement = false;
  String? _accountId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _accountId = widget.accounts.isEmpty
        ? null
        : widget.accounts.first.account.id;
  }

  @override
  void dispose() {
    _counterparty.dispose();
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
        'Créance ou dette',
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
            SegmentedControl(
              segments: const <String>['On me doit', 'Je dois'],
              selectedIndex: _direction.index,
              onChanged: (int index) =>
                  setState(() => _direction = DebtDirection.values[index]),
            ),
            const SizedBox(height: AkibaSpacing.xs),
            Text(
              _direction == DebtDirection.owedToMe
                  ? 'On vous doit : cette somme n’entre pas dans votre solde '
                        'disponible avant l’encaissement. À l’encaissement, '
                        'elle est ajoutée au compte choisi.'
                  : 'Vous devez : cette somme reste suivie à part. Au '
                        'paiement, elle est retirée du compte choisi.',
              style: AkibaTypography.legend.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: AkibaSpacing.md),
            TextField(
              controller: _counterparty,
              textCapitalization: TextCapitalization.words,
              decoration: _input(c, 'Nom du tiers'),
            ),
            const SizedBox(height: AkibaSpacing.md),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: _input(c, 'Montant en ${AkibaMoney.currency}'),
            ),
            const SizedBox(height: AkibaSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _withMovement,
              onChanged: widget.accounts.isEmpty
                  ? null
                  : (bool value) => setState(() => _withMovement = value),
              title: Text(
                'Mouvement de trésorerie immédiat',
                style: TextStyle(fontSize: 13.5, color: c.textPrimary),
              ),
              subtitle: Text(
                widget.accounts.isEmpty
                    ? 'Aucun compte disponible : le suivi reste séparé.'
                    : _direction == DebtDirection.owedToMe
                    ? 'Prêt accordé : une sortie est enregistrée sur le '
                          'compte choisi.'
                    : 'Emprunt reçu : l’entrée reste hors du solde '
                          'disponible, car elle devra être rendue.',
                style: AkibaTypography.legend.copyWith(
                  color: c.textMuted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
            if (_withMovement && widget.accounts.isNotEmpty) ...<Widget>[
              const SizedBox(height: AkibaSpacing.xs),
              Wrap(
                spacing: AkibaSpacing.sm,
                runSpacing: AkibaSpacing.sm,
                children: <Widget>[
                  for (final AccountBalance item in widget.accounts)
                    AccountPill(
                      account: item.account,
                      selected: item.account.id == _accountId,
                      onTap: () => setState(() => _accountId = item.account.id),
                    ),
                ],
              ),
            ],
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
            final String name = _counterparty.text.trim();
            final int amount = int.tryParse(_amount.text) ?? 0;
            if (name.length < 2) {
              setState(() => _error = 'Indiquez le nom du tiers.');
              return;
            }
            if (amount <= 0) {
              setState(() => _error = 'Le montant doit être supérieur à 0.');
              return;
            }
            Navigator.of(context).pop(
              _DebtDraft(
                direction: _direction,
                counterparty: name,
                amount: amount,
                dueDate: _dueDate,
                withMovement: _withMovement && widget.accounts.isNotEmpty,
                accountId: _accountId,
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

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.accounts,
    required this.confirmLabel,
    this.maxAmount,
    this.initialAmount,
    this.helper,
    this.suggestPercent,
  });

  final String title;
  final List<AccountBalance> accounts;
  final String confirmLabel;
  final int? maxAmount;
  final int? initialAmount;
  final String? helper;

  /// Part (0 à 30 %) proposée pour un versement d'épargne.
  final int? suggestPercent;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.initialAmount?.toString() ?? '',
  );
  late String? _accountId = widget.accounts.isEmpty
      ? null
      : widget.accounts.first.account.id;
  String? _error;

  int get _value => int.tryParse(_amount.text) ?? 0;

  AccountBalance? get _selected {
    for (final AccountBalance item in widget.accounts) {
      if (item.account.id == _accountId) return item;
    }
    return null;
  }

  /// Proposition recalculée sur le compte sélectionné.
  int get _suggested {
    final int percent = widget.suggestPercent ?? 0;
    final AccountBalance? account = _selected;
    if (account == null) return 0;
    return SavingsProjection.suggestedDeposit(
      accountBalance: account.balance,
      percent: percent,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final int? max = widget.maxAmount;

    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AkibaRadii.card),
      ),
      title: Text(
        widget.title,
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
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              onChanged: (_) => setState(() => _error = null),
              style: AkibaTypography.money(22, color: c.textPrimary),
              decoration: _input(c, 'Montant en ${AkibaMoney.currency}'),
            ),
            const SizedBox(height: AkibaSpacing.sm),
            Text(
              AkibaMoney.format(_value),
              style: AkibaTypography.legend.copyWith(color: c.textMuted),
            ),
            if (widget.helper != null) ...<Widget>[
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                widget.helper!,
                style: AkibaTypography.legend.copyWith(color: c.textMuted),
              ),
            ],
            if (_suggested > 0) ...<Widget>[
              const SizedBox(height: AkibaSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _amount.text = '$_suggested';
                    _error = null;
                  }),
                  icon: const Icon(Icons.savings_rounded, size: 18),
                  label: Text(
                    'Proposer ${widget.suggestPercent} % · '
                    '${AkibaMoney.format(_suggested)}',
                  ),
                ),
              ),
            ],
            if (max != null) ...<Widget>[
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                'Maximum : ${AkibaMoney.format(max)}',
                style: AkibaTypography.legend.copyWith(color: c.textMuted),
              ),
            ],
            if (widget.accounts.isNotEmpty) ...<Widget>[
              const SizedBox(height: AkibaSpacing.md),
              Text(
                'COMPTE',
                style: AkibaTypography.label.copyWith(
                  color: c.textMuted,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Wrap(
                spacing: AkibaSpacing.sm,
                runSpacing: AkibaSpacing.sm,
                children: <Widget>[
                  for (final AccountBalance item in widget.accounts)
                    AccountPill(
                      account: item.account,
                      selected: item.account.id == _accountId,
                      onTap: () => setState(() => _accountId = item.account.id),
                    ),
                ],
              ),
            ],
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
            final int value = _value;
            if (value <= 0) {
              setState(() => _error = 'Saisissez un montant supérieur à 0.');
              return;
            }
            if (max != null && value > max) {
              setState(
                () => _error = 'Le maximum est ${AkibaMoney.format(max)}.',
              );
              return;
            }
            if (widget.accounts.isNotEmpty && _accountId == null) {
              setState(() => _error = 'Choisissez un compte.');
              return;
            }
            Navigator.of(
              context,
            ).pop((amount: value, accountId: _accountId ?? ''));
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

Future<({int amount, String accountId})?> _askAmount(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  List<AccountBalance> accounts = const <AccountBalance>[],
  int? maxAmount,
  int? initialAmount,
  String? helper,
  int? suggestPercent,
}) {
  return showDialog<({int amount, String accountId})>(
    context: context,
    builder: (BuildContext context) => _AmountDialog(
      title: title,
      accounts: accounts,
      confirmLabel: confirmLabel,
      maxAmount: maxAmount,
      initialAmount: initialAmount,
      helper: helper,
      suggestPercent: suggestPercent,
    ),
  );
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
