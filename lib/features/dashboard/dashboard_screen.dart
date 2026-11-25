import 'package:flutter/material.dart';

import '../../core/format/akiba_date.dart';
import '../../core/format/akiba_money.dart';
import '../../core/format/transaction_display.dart';
import '../../core/profile/profile_photo.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/state/akiba_l10n.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/state/masked_amounts.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_theme.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/ai_insight_card.dart';
import '../../core/widgets/akiba_surface_card.dart';
import '../../core/widgets/balance_card.dart';
import '../../core/widgets/icon_circle_button.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../core/widgets/quick_action_tile.dart';
import '../../core/widgets/triangle_fringe.dart';
import '../../core/widgets/transaction_row.dart';
import '../../data/akiba_store.dart';
import '../../data/balance_summary.dart';
import '../quick_entry/quick_entry.dart';

/// Écran Accueil : solde disponible, argent de tiers isolé, aperçu IA, actions
/// rapides et dernières transactions.
///
/// Le cochon latéral, les pilules de la carte de solde et les actions rapides
/// ouvrent la même saisie rapide ; un glissement sur une ligne permet de la
/// modifier ou de la supprimer avec annulation.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.store,
    required this.revision,
    required this.themeId,
    required this.onThemeChanged,
    this.onSeeAllMovements,
  });

  final AkibaStore store;
  final AkibaDataRevision revision;
  final AkibaThemeId themeId;
  final ValueChanged<AkibaThemeId> onThemeChanged;
  final VoidCallback? onSeeAllMovements;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<DashboardSnapshot> _snapshot = widget.store.loadDashboard();

  @override
  void initState() {
    super.initState();
    widget.revision.addListener(_reload);
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) _reload();
  }

  @override
  void dispose() {
    widget.revision.removeListener(_reload);
    super.dispose();
  }

  /// Relit la base après chaque écriture (revision.bump).
  ///
  /// Le callback de `setState` doit être **synchrone** : lui rendre un `Future`
  /// (forme `setState(() => _snapshot = store.loadDashboard())`) lève
  /// « setState() callback argument returned a Future » et laisse le solde
  /// figé. On crée donc le Future avant, puis on l'affecte dans un bloc.
  void _reload() {
    if (!mounted) return;
    final Future<DashboardSnapshot> next = widget.store.loadDashboard();
    setState(() {
      _snapshot = next;
    });
  }

  Future<void> _refresh() async {
    final Future<DashboardSnapshot> next = widget.store.loadDashboard();
    if (mounted) {
      setState(() {
        _snapshot = next;
      });
    }
    await next;
  }

  void _notYet(String label, String phase) {
    final AkibaColors c = AkibaColors.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AkibaL10n.tr('planned_in', <String, String>{
              'label': label,
              'phase': phase,
            }),
          ),
          backgroundColor: c.textPrimary,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _enter(QuickEntryMode mode) {
    return openQuickEntry(
      context,
      store: widget.store,
      revision: widget.revision,
      mode: mode,
    );
  }

  Future<void> _edit(TransactionLine line) async {
    final QuickEntryMode? mode = quickEntryModeFor(line.transaction);
    if (mode == null) {
      _notYet('La modification de ce mouvement', 'Phase 5');
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

  Future<void> _delete(TransactionLine line) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await widget.store.deleteTransaction(line.transaction);
    widget.revision.bump();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(AkibaL10n.tr('movement_deleted')),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: AkibaL10n.tr('cancel'),
            onPressed: () async {
              await widget.store.saveTransaction(line.transaction);
              widget.revision.bump();
            },
          ),
        ),
      );
  }

  /// Bascule vers le thème suivant : Blanc → Sombre → Bleu → Vert → Or → Blanc.
  void _cycleTheme() {
    final List<AkibaThemeId> all = AkibaThemeId.values;
    widget.onThemeChanged(all[(all.indexOf(widget.themeId) + 1) % all.length]);
  }

  String get _themeLabel => widget.themeId.label;

  @override
  Widget build(BuildContext context) {
    final bool masked = MaskedAmounts.of(context);

    return FutureBuilder<DashboardSnapshot>(
      future: _snapshot,
      builder: (BuildContext context, AsyncSnapshot<DashboardSnapshot> async) {
        if (async.hasError) {
          return _ErrorState(onRetry: _refresh);
        }

        final DashboardSnapshot? data = async.data;
        return RefreshIndicator(
          color: AkibaColors.of(context).terracotta,
          onRefresh: _refresh,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool wide = constraints.maxWidth >= 900;
              final Widget header = _Header(
                masked: masked,
                onToggleMasked: () => MaskedAmounts.toggle(context),
                themeTooltip: AkibaL10n.tr(
                  'appearance_tooltip',
                  <String, String>{'theme': _themeLabel},
                ),
                onCycleTheme: _cycleTheme,
              );

              if (data == null) {
                return _scroll(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      header,
                      const SizedBox(height: AkibaSpacing.xxxl),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                );
              }

              final List<Widget> main = <Widget>[
                BalanceCard(
                  available: data.balance.available,
                  totalAccounts: data.balance.totalAccounts,
                  savingsHeld: data.balance.savingsHeld,
                  thirdPartyHeld: data.balance.thirdPartyHeld,
                  masked: masked,
                  onTransfer: () => _enter(QuickEntryMode.transfer),
                  onAdd: () => _enter(QuickEntryMode.expense),
                ),
                _insightCard(data, masked),
                _QuickActions(
                  onEntry: () => _enter(QuickEntryMode.income),
                  onExpense: () => _enter(QuickEntryMode.expense),
                  onTransfer: () => _enter(QuickEntryMode.transfer),
                  onSavings: () => _notYet('Coffre épargne', 'Phase 5'),
                ),
              ];

              final List<Widget> side = <Widget>[
                _ThirdPartyCard(balance: data.balance, masked: masked),
                _TransactionsCard(
                  recent: data.recent,
                  masked: masked,
                  onSeeAll:
                      widget.onSeeAllMovements ??
                      () => _notYet('Historique complet', 'Phase 5'),
                  onEdit: _edit,
                  onDelete: _delete,
                ),
              ];

              return _scroll(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    header,
                    const SizedBox(height: AkibaSpacing.xxl),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(flex: 5, child: _column(main)),
                          const SizedBox(width: AkibaSpacing.xxl),
                          Expanded(flex: 4, child: _column(side)),
                        ],
                      )
                    else
                      _column(<Widget>[...main, ...side]),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _scroll({required Widget child}) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AkibaSpacing.screen,
        AkibaSpacing.lg,
        AkibaSpacing.screen,
        160,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: child,
        ),
      ),
    );
  }

  Widget _column(List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AkibaSpacing.xxl),
          // Cascade légère à l'ouverture (désactivée si « Réduire les
          // animations » est actif, via MediaQuery.disableAnimations).
          _Cascade(index: i, child: children[i]),
        ],
      ],
    );
  }

  Widget _insightCard(DashboardSnapshot data, bool masked) {
    final ({String title, String message, String? highlight}) insight =
        _buildInsight(data, masked);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionHeader(title: AkibaL10n.tr('ai_preview')),
        const SizedBox(height: AkibaSpacing.md),
        AIInsightCard(
          title: insight.title,
          message: insight.message,
          highlight: insight.highlight,
          footnote: AkibaL10n.tr('ai_footnote'),
          onTap: () => _notYet('Assistant IA', 'Phase 6'),
        ),
      ],
    );
  }

  ({String title, String message, String? highlight}) _buildInsight(
    DashboardSnapshot data,
    bool masked,
  ) {
    final BalanceSummary balance = data.balance;

    if (data.recent.isEmpty) {
      return (
        title: AkibaL10n.tr('insight_welcome_title'),
        message: AkibaL10n.tr('insight_welcome_message'),
        highlight: null,
      );
    }

    if (masked) {
      return (
        title: AkibaL10n.tr('insight_masked_title'),
        message: AkibaL10n.tr('insight_masked_message'),
        highlight: null,
      );
    }

    if (balance.monthExpense > 0) {
      final String amount = AkibaMoney.format(balance.monthExpense);
      return (
        title: AkibaL10n.tr('insight_month_title'),
        message: AkibaL10n.tr('insight_month_message', <String, String>{
          'amount': amount,
        }),
        highlight: amount,
      );
    }

    return (
      title: AkibaL10n.tr('insight_none_title'),
      message: AkibaL10n.tr('insight_none_message'),
      highlight: null,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.masked,
    required this.onToggleMasked,
    required this.themeTooltip,
    required this.onCycleTheme,
  });

  final bool masked;
  final VoidCallback onToggleMasked;
  final String themeTooltip;
  final VoidCallback onCycleTheme;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    // Photo de profil locale (avatar par défaut si absente).
    final ProfilePhotoController? photo = ProfilePhotoScope.maybeOf(context);
    final String name =
        AkibaSettingsScope.maybeOf(context)?.firstName.trim() ?? '';

    return Row(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: AkibaSpacing.md),
          child: ProfileAvatar(bytes: photo?.bytes, name: name, size: 46),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                AkibaDate.long(DateTime.now()).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AkibaTypography.label.copyWith(
                  color: c.textMuted,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: AkibaSpacing.xs),
              Text(
                AkibaL10n.tr('my_money'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
          tooltip: masked
              ? AkibaL10n.tr('show_amounts')
              : AkibaL10n.tr('hide_amounts'),
          onTap: onToggleMasked,
        ),
        const SizedBox(width: AkibaSpacing.sm),
        IconCircleButton(
          icon: Icons.palette_outlined,
          tooltip: themeTooltip,
          onTap: onCycleTheme,
        ),
      ],
    );
  }
}

class _ThirdPartyCard extends StatelessWidget {
  const _ThirdPartyCard({required this.balance, required this.masked});

  final BalanceSummary balance;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final bool hasThirdParty = balance.thirdPartyHeld != 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionHeader(title: AkibaL10n.tr('third_party')),
        const SizedBox(height: AkibaSpacing.md),
        AkibaSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      AkibaMoney.format(balance.thirdPartyHeld, masked: masked),
                      style: AkibaTypography.money(26, color: c.terracotta),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AkibaSpacing.sm,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: c.iconTile,
                      borderRadius: BorderRadius.circular(AkibaRadii.pill),
                    ),
                    child: Text(
                      hasThirdParty
                          ? AkibaL10n.tr('isolated')
                          : AkibaL10n.tr('none'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.terracottaDeep,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                AkibaL10n.tr('third_party_note'),
                style: AkibaTypography.legend.copyWith(
                  color: c.textMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AkibaSpacing.md),
              Container(height: 1, color: c.surfaceElevated),
              const SizedBox(height: AkibaSpacing.sm),
              _MetricRow(
                label: AkibaL10n.tr('total_accounts'),
                value: AkibaMoney.format(balance.totalAccounts, masked: masked),
              ),
              _MetricRow(
                label: AkibaL10n.tr('savings_vault'),
                value: AkibaMoney.format(balance.savingsHeld, masked: masked),
              ),
              _MetricRow(
                label: AkibaL10n.tr('available_balance'),
                value: AkibaMoney.format(balance.available, masked: masked),
                strong: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AkibaSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: AkibaTypography.body.copyWith(
                fontSize: 13,
                color: c.textMuted,
              ),
            ),
          ),
          const SizedBox(width: AkibaSpacing.sm),
          Text(
            value,
            style: AkibaTypography.money(
              15,
              weight: strong ? FontWeight.w700 : FontWeight.w500,
              color: strong ? c.terracotta : c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onEntry,
    required this.onExpense,
    required this.onTransfer,
    required this.onSavings,
  });

  final VoidCallback onEntry;
  final VoidCallback onExpense;
  final VoidCallback onTransfer;
  final VoidCallback onSavings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionHeader(title: AkibaL10n.tr('quick_actions')),
        const SizedBox(height: AkibaSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: QuickActionTile(
                icon: Icons.south_west_rounded,
                label: AkibaL10n.tr('entry'),
                onTap: onEntry,
              ),
            ),
            const SizedBox(width: AkibaSpacing.sm),
            Expanded(
              child: QuickActionTile(
                icon: Icons.north_east_rounded,
                label: AkibaL10n.tr('expense'),
                onTap: onExpense,
              ),
            ),
            const SizedBox(width: AkibaSpacing.sm),
            Expanded(
              child: QuickActionTile(
                icon: Icons.swap_horiz_rounded,
                label: AkibaL10n.tr('transfer'),
                onTap: onTransfer,
              ),
            ),
            const SizedBox(width: AkibaSpacing.sm),
            Expanded(
              child: QuickActionTile(
                icon: Icons.savings_rounded,
                label: AkibaL10n.tr('savings'),
                onTap: onSavings,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TransactionsCard extends StatelessWidget {
  const _TransactionsCard({
    required this.recent,
    required this.masked,
    required this.onSeeAll,
    required this.onEdit,
    required this.onDelete,
  });

  final List<TransactionLine> recent;
  final bool masked;
  final VoidCallback onSeeAll;
  final ValueChanged<TransactionLine> onEdit;
  final ValueChanged<TransactionLine> onDelete;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _SectionHeader(title: AkibaL10n.tr('latest_transactions')),
            ),
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(foregroundColor: c.terracottaDeep),
              child: Text(AkibaL10n.tr('see_all')),
            ),
          ],
        ),
        const SizedBox(height: AkibaSpacing.sm),
        if (recent.isEmpty)
          const _EmptyTransactions()
        else
          AkibaSurfaceCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AkibaSpacing.lg,
              vertical: AkibaSpacing.xs,
            ),
            child: Column(
              children: <Widget>[
                for (final TransactionLine line in recent)
                  Dismissible(
                    key: ValueKey<String>(line.transaction.id),
                    direction: DismissDirection.horizontal,
                    background: _SwipeBackground(
                      color: c.ochre,
                      icon: Icons.edit_rounded,
                      label: AkibaL10n.tr('edit'),
                      alignLeft: true,
                    ),
                    secondaryBackground: _SwipeBackground(
                      color: c.danger,
                      icon: Icons.delete_outline_rounded,
                      label: AkibaL10n.tr('delete'),
                      alignLeft: false,
                    ),
                    confirmDismiss: (DismissDirection direction) async {
                      if (direction == DismissDirection.startToEnd) {
                        onEdit(line);
                        return false;
                      }
                      return true;
                    },
                    onDismissed: (_) => onDelete(line),
                    child: TransactionRow(
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
                      badge: line.transaction.isNeutral
                          ? AkibaL10n.tr('third_party_short')
                          : null,
                      onTap: () => onEdit(line),
                    ),
                  ),
              ],
            ),
          ),
        if (recent.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AkibaSpacing.sm),
            child: Text(
              AkibaL10n.tr('swipe_hint'),
              style: AkibaTypography.legend.copyWith(color: c.textMuted),
            ),
          ),
      ],
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignLeft,
  });

  final Color color;
  final IconData icon;
  final String label;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: AkibaSpacing.lg),
      margin: const EdgeInsets.symmetric(vertical: AkibaSpacing.xs),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AkibaRadii.field),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: AkibaSpacing.sm),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return AkibaSurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          TriangleFringe(
            alignTop: true,
            height: 14,
            color: c.sand.withValues(alpha: 0.5),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AkibaSpacing.xl,
              vertical: AkibaSpacing.xl,
            ),
            child: Column(
              children: <Widget>[
                Icon(Icons.receipt_long_rounded, size: 28, color: c.terracotta),
                const SizedBox(height: AkibaSpacing.md),
                Text(
                  AkibaL10n.tr('no_movement'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: AkibaSpacing.xs),
                Text(
                  AkibaL10n.tr('no_movement_note'),
                  textAlign: TextAlign.center,
                  style: AkibaTypography.legend.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
          TriangleFringe(
            alignTop: false,
            height: 14,
            color: c.sand.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

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

/// Apparition en cascade des blocs de l'accueil (40 ms par bloc).
class _Cascade extends StatefulWidget {
  const _Cascade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Cascade> createState() => _CascadeState();
}

class _CascadeState extends State<_Cascade> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) return widget.child;

    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 0.03),
      duration: AkibaDurations.page,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: AkibaDurations.page,
        child: widget.child,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AkibaSpacing.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.lock_outline_rounded, size: 32, color: c.danger),
            const SizedBox(height: AkibaSpacing.md),
            Text(
              AkibaL10n.tr('db_unreadable'),
              style: AkibaTypography.sectionTitle.copyWith(
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AkibaSpacing.sm),
            Text(
              AkibaL10n.tr('db_unreadable_note'),
              textAlign: TextAlign.center,
              style: AkibaTypography.body.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: AkibaSpacing.lg),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(AkibaL10n.tr('retry')),
            ),
          ],
        ),
      ),
    );
  }
}
