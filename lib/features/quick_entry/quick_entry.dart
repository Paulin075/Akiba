import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/akiba_money.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/account_pill.dart';
import '../../core/widgets/segmented_control.dart';
import '../../data/akiba_store.dart';
import '../../data/models/account.dart';
import '../../data/models/budget.dart';
import '../../data/models/third_party.dart';
import '../../data/models/transaction_record.dart';

/// Nature de la saisie rapide.
enum QuickEntryMode { income, expense, transfer, thirdParty }

/// Mode de saisie correspondant à un mouvement existant (`null` si le
/// mouvement ne se modifie pas par la saisie rapide : épargne, ouverture).
QuickEntryMode? quickEntryModeFor(TransactionRecord record) {
  if (record.isNeutral) return QuickEntryMode.thirdParty;
  return switch (record.kind) {
    TransactionKind.income => QuickEntryMode.income,
    TransactionKind.expense => QuickEntryMode.expense,
    TransactionKind.transfer => QuickEntryMode.transfer,
    TransactionKind.savings || TransactionKind.opening => null,
  };
}

/// Résultat d'une saisie validée, avant écriture en base.
class QuickEntryOutcome {
  const QuickEntryOutcome({
    required this.created,
    required this.title,
    this.thirdParty,
  });

  final List<TransactionRecord> created;

  /// Résumé sans montant pour le bandeau d'annulation.
  final String title;

  /// Tiers à créer ou à réutiliser (opération neutre).
  final ThirdParty? thirdParty;
}

/// Ouvre la saisie rapide, écrit les mouvements et affiche « Annuler » 5 s.
Future<void> openQuickEntry(
  BuildContext context, {
  required AkibaStore store,
  required AkibaDataRevision revision,
  QuickEntryMode mode = QuickEntryMode.expense,
  TransactionLine? editing,
  VoidCallback? onSaved,
}) async {
  final QuickEntryOutcome? outcome = await _showQuickEntry(
    context,
    store: store,
    mode: mode,
    editing: editing,
  );
  if (outcome == null || !context.mounted) return;

  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    if (editing != null) {
      await store.deleteTransaction(editing.transaction);
    }
    final ThirdParty? thirdParty = outcome.thirdParty;
    if (thirdParty != null) {
      await store.saveThirdParty(thirdParty);
    }
    for (final TransactionRecord record in outcome.created) {
      await store.saveTransaction(record);
    }
    revision.bump();
    onSaved?.call();

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Enregistré · ${outcome.title}'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Annuler',
            onPressed: () async {
              for (final TransactionRecord record in outcome.created) {
                await store.deleteTransaction(record);
              }
              revision.bump();
              onSaved?.call();
            },
          ),
        ),
      );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Enregistrement impossible. Réessayez.')),
    );
  }
}

Future<QuickEntryOutcome?> _showQuickEntry(
  BuildContext context, {
  required AkibaStore store,
  required QuickEntryMode mode,
  TransactionLine? editing,
}) {
  final bool wide = MediaQuery.sizeOf(context).width >= 720;
  final Widget body = _QuickEntryBody(
    store: store,
    initialMode: mode,
    editing: editing,
  );

  if (wide) {
    return showDialog<QuickEntryOutcome>(
      context: context,
      builder: (BuildContext context) {
        final AkibaColors c = AkibaColors.of(context);
        return Dialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AkibaRadii.card),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: SizedBox(width: 560, child: body),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<QuickEntryOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AkibaColors.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AkibaRadii.card),
      ),
    ),
    builder: (BuildContext context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: body,
    ),
  );
}

class _QuickEntryBody extends StatefulWidget {
  const _QuickEntryBody({
    required this.store,
    required this.initialMode,
    this.editing,
  });

  final AkibaStore store;
  final QuickEntryMode initialMode;
  final TransactionLine? editing;

  @override
  State<_QuickEntryBody> createState() => _QuickEntryBodyState();
}

class _QuickEntryBodyState extends State<_QuickEntryBody> {
  static const List<String> _expenseCategories = <String>[
    'Alimentation',
    'Transport',
    'Loyer',
    'Santé',
    'École',
    'Tontine',
    'Autre',
  ];
  static const List<String> _incomeCategories = <String>[
    'Salaire',
    'Vente',
    'Don',
    'Autre',
  ];
  static const List<String> _modeLabels = <String>[
    'Entrée',
    'Sortie',
    'Transfert',
    'Tiers',
  ];

  late QuickEntryMode _mode = widget.initialMode;
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _partyName = TextEditingController();

  List<AccountBalance> _accounts = const <AccountBalance>[];
  List<BudgetStatus> _budgets = const <BudgetStatus>[];
  List<ThirdParty> _parties = const <ThirdParty>[];
  String? _accountId;
  String? _targetId;
  String? _category;
  String? _error;
  bool _loading = true;

  bool get _editing => widget.editing != null;

  int get _amountValue => int.tryParse(_amount.text) ?? 0;

  @override
  void initState() {
    super.initState();
    final TransactionLine? editing = widget.editing;
    if (editing != null) {
      final TransactionRecord record = editing.transaction;
      _amount.text = record.amount.abs().toString();
      _note.text = record.note ?? '';
      _category = record.category;
      _accountId = record.accountId;
      _targetId = record.transferAccountId;
      if (record.isNeutral) {
        _mode = QuickEntryMode.thirdParty;
      } else if (record.kind == TransactionKind.transfer) {
        _mode = QuickEntryMode.transfer;
      } else if (record.kind == TransactionKind.income) {
        _mode = QuickEntryMode.income;
      } else {
        _mode = QuickEntryMode.expense;
      }
    }
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _partyName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<AccountBalance> accounts = await widget.store.accountBalances();
    final List<BudgetStatus> budgets = await widget.store.budgets();
    final List<ThirdParty> parties = await widget.store.thirdParties();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _budgets = budgets;
      _parties = parties;
      _accountId ??= accounts.isEmpty ? null : accounts.first.account.id;
      _targetId ??= _defaultTarget(accounts, _accountId);
      _loading = false;
    });
  }

  static String? _defaultTarget(List<AccountBalance> accounts, String? source) {
    for (final AccountBalance item in accounts) {
      if (item.account.id != source) return item.account.id;
    }
    return null;
  }

  List<String> get _categories => switch (_mode) {
    QuickEntryMode.expense => _expenseCategories,
    QuickEntryMode.income => _incomeCategories,
    QuickEntryMode.transfer || QuickEntryMode.thirdParty => const <String>[],
  };

  AccountBalance? get _source {
    for (final AccountBalance item in _accounts) {
      if (item.account.id == _accountId) return item;
    }
    return null;
  }

  List<String> get _warnings {
    final int value = _amountValue;
    if (value <= 0) return const <String>[];

    final List<String> warnings = <String>[];
    final AccountBalance? source = _source;
    final bool debits =
        _mode == QuickEntryMode.expense || _mode == QuickEntryMode.transfer;
    if (debits && source != null && value > source.balance) {
      warnings.add(
        'Solde insuffisant sur ${source.account.name} : '
        '${AkibaMoney.format(source.balance)} disponibles. '
        'L’écriture reste possible.',
      );
    }

    if (_mode == QuickEntryMode.expense && _category != null) {
      for (final BudgetStatus status in _budgets) {
        if (status.budget.category != _category) continue;
        if (status.spent + value > status.limit) {
          warnings.add(
            'Budget ${status.budget.category} dépassé : '
            '${AkibaMoney.format(status.spent + value)} '
            'sur ${AkibaMoney.format(status.limit)}.',
          );
        }
      }
    }
    return warnings;
  }

  ThirdParty? _resolveThirdParty() {
    final String name = _partyName.text.trim();
    if (_mode != QuickEntryMode.thirdParty || name.isEmpty) return null;
    for (final ThirdParty party in _parties) {
      if (party.name.toLowerCase() == name.toLowerCase()) return party;
    }
    return ThirdParty(
      id: 'tp-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      createdAt: DateTime.now(),
    );
  }

  void _submit() {
    final int value = _amountValue;
    if (value <= 0) {
      setState(() => _error = 'Saisissez un montant en FCFA supérieur à 0.');
      return;
    }
    if (value > 999999999) {
      setState(() => _error = 'Montant trop élevé (maximum 999 999 999 FCFA).');
      return;
    }
    final String? accountId = _accountId;
    if (accountId == null) {
      setState(() => _error = 'Aucun compte disponible pour enregistrer.');
      return;
    }
    if (_mode == QuickEntryMode.transfer &&
        (_targetId == null || _targetId == accountId)) {
      setState(() => _error = 'Choisissez deux comptes différents.');
      return;
    }

    final DateTime at =
        widget.editing?.transaction.occurredAt ?? DateTime.now();
    final DateTime createdAt = DateTime.now();
    final String baseId = 'tx-${createdAt.microsecondsSinceEpoch}';
    final String? note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final ThirdParty? party = _resolveThirdParty();
    final List<TransactionRecord> created = <TransactionRecord>[];

    switch (_mode) {
      case QuickEntryMode.income:
        created.add(
          TransactionRecord(
            id: baseId,
            accountId: accountId,
            amount: value,
            kind: TransactionKind.income,
            category: _category,
            note: note,
            occurredAt: at,
            createdAt: createdAt,
          ),
        );
      case QuickEntryMode.expense:
        created.add(
          TransactionRecord(
            id: baseId,
            accountId: accountId,
            amount: -value,
            kind: TransactionKind.expense,
            category: _category,
            note: note,
            occurredAt: at,
            createdAt: createdAt,
          ),
        );
      case QuickEntryMode.transfer:
        created
          ..add(
            TransactionRecord(
              id: '$baseId-out',
              accountId: accountId,
              amount: -value,
              kind: TransactionKind.transfer,
              note: note,
              occurredAt: at,
              createdAt: createdAt,
              transferAccountId: _targetId,
            ),
          )
          ..add(
            TransactionRecord(
              id: '$baseId-in',
              accountId: _targetId!,
              amount: value,
              kind: TransactionKind.transfer,
              note: note,
              occurredAt: at,
              createdAt: createdAt,
              transferAccountId: accountId,
            ),
          );
      case QuickEntryMode.thirdParty:
        created.add(
          TransactionRecord(
            id: baseId,
            accountId: accountId,
            amount: value,
            kind: TransactionKind.income,
            note: note,
            occurredAt: at,
            createdAt: createdAt,
            isNeutral: true,
            thirdPartyId: party?.id,
          ),
        );
    }

    // Aucun montant dans le bandeau : il reste lisible quand le masquage est
    // actif, y compris sur l'écran de notifications du système.
    final String title = switch (_mode) {
      QuickEntryMode.income => 'Entrée enregistrée',
      QuickEntryMode.expense => 'Sortie enregistrée',
      QuickEntryMode.transfer => 'Transfert enregistré',
      QuickEntryMode.thirdParty => 'Entrée de tiers enregistrée',
    };

    Navigator.of(
      context,
    ).pop(QuickEntryOutcome(created: created, title: title, thirdParty: party));
  }

  void _setMode(QuickEntryMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      if (!_categories.contains(_category)) _category = null;
      if (mode == QuickEntryMode.transfer && _targetId == _accountId) {
        _targetId = _defaultTarget(_accounts, _accountId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final List<String> warnings = _warnings;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AkibaSpacing.xl,
          AkibaSpacing.md,
          AkibaSpacing.xl,
          AkibaSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.surfaceElevated,
                  borderRadius: BorderRadius.circular(AkibaRadii.pill),
                ),
              ),
            ),
            const SizedBox(height: AkibaSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _editing ? 'Modifier le mouvement' : 'Saisie rapide',
                        style: AkibaTypography.sectionTitle.copyWith(
                          fontSize: 19,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _editing
                            ? 'Les montants restent en FCFA entiers.'
                            : 'Moins de 10 secondes, 3 touches.',
                        style: AkibaTypography.legend.copyWith(
                          color: c.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: c.textMuted),
                ),
              ],
            ),
            const SizedBox(height: AkibaSpacing.md),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AkibaSpacing.xxxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...<Widget>[
              SegmentedControl(
                segments: _modeLabels,
                selectedIndex: _mode.index,
                onChanged: (int index) =>
                    _setMode(QuickEntryMode.values[index]),
              ),
              const SizedBox(height: AkibaSpacing.xl),
              _label(context, 'MONTANT'),
              const SizedBox(height: AkibaSpacing.sm),
              TextField(
                controller: _amount,
                autofocus: !_editing,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                onChanged: (_) => setState(() => _error = null),
                style: AkibaTypography.money(28, color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: AkibaTypography.money(
                    28,
                    weight: FontWeight.w500,
                    color: c.textMuted.withValues(alpha: 0.6),
                  ),
                  suffixText: 'FCFA',
                  suffixStyle: AkibaTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.textMuted,
                  ),
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
                ),
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                AkibaMoney.format(_amountValue),
                style: AkibaTypography.legend.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Wrap(
                spacing: AkibaSpacing.sm,
                children: <Widget>[
                  for (final (int step, String label) in <(int, String)>[
                    (1000, '+1 000'),
                    (2000, '+2 000'),
                    (5000, '+5 000'),
                    (10000, '+10 000'),
                  ])
                    _QuickAmount(
                      label: label,
                      onTap: () {
                        final int next = _amountValue + step;
                        _amount.text = (next > 999999999 ? 999999999 : next)
                            .toString();
                        setState(() => _error = null);
                      },
                    ),
                ],
              ),
              const SizedBox(height: AkibaSpacing.xl),
              _label(
                context,
                _mode == QuickEntryMode.transfer ? 'DEPUIS' : 'COMPTE',
              ),
              const SizedBox(height: AkibaSpacing.sm),
              if (_accounts.isEmpty)
                Text(
                  'Aucun compte disponible. Ouvrez le Portefeuille pour en '
                  'créer un.',
                  style: AkibaTypography.body.copyWith(color: c.danger),
                )
              else
                Wrap(
                  spacing: AkibaSpacing.sm,
                  runSpacing: AkibaSpacing.sm,
                  children: <Widget>[
                    for (final AccountBalance item in _accounts)
                      AccountPill(
                        account: item.account,
                        selected: item.account.id == _accountId,
                        onTap: () => setState(() {
                          _accountId = item.account.id;
                          if (_targetId == _accountId) {
                            _targetId = _defaultTarget(_accounts, _accountId);
                          }
                        }),
                      ),
                  ],
                ),
              if (_mode == QuickEntryMode.transfer) ...<Widget>[
                const SizedBox(height: AkibaSpacing.lg),
                _label(context, 'VERS'),
                const SizedBox(height: AkibaSpacing.sm),
                Wrap(
                  spacing: AkibaSpacing.sm,
                  runSpacing: AkibaSpacing.sm,
                  children: <Widget>[
                    for (final AccountBalance item in _accounts)
                      if (item.account.id != _accountId)
                        AccountPill(
                          account: item.account,
                          selected: item.account.id == _targetId,
                          onTap: () =>
                              setState(() => _targetId = item.account.id),
                        ),
                  ],
                ),
              ],
              if (_mode == QuickEntryMode.thirdParty) ...<Widget>[
                const SizedBox(height: AkibaSpacing.lg),
                _label(context, 'TIERS (OPTIONNEL)'),
                const SizedBox(height: AkibaSpacing.sm),
                TextField(
                  controller: _partyName,
                  textCapitalization: TextCapitalization.words,
                  decoration: _fieldDecoration(
                    c,
                    hint: 'Nom du client ou de la personne',
                  ),
                ),
                const SizedBox(height: AkibaSpacing.sm),
                Text(
                  'Cette entrée est isolée : elle n’augmente pas le solde '
                  'disponible et reste hors budget et statistiques.',
                  style: AkibaTypography.legend.copyWith(
                    color: c.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
              if (_categories.isNotEmpty) ...<Widget>[
                const SizedBox(height: AkibaSpacing.lg),
                _label(context, 'CATÉGORIE'),
                const SizedBox(height: AkibaSpacing.sm),
                Wrap(
                  spacing: AkibaSpacing.sm,
                  runSpacing: AkibaSpacing.sm,
                  children: <Widget>[
                    for (final String category in _categories)
                      _ChoicePill(
                        label: category,
                        selected: _category == category,
                        onTap: () => setState(
                          () => _category = _category == category
                              ? null
                              : category,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AkibaSpacing.lg),
              _label(context, 'NOTE (OPTIONNEL)'),
              const SizedBox(height: AkibaSpacing.sm),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                decoration: _fieldDecoration(c, hint: 'Ex. taxi, marché…'),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AkibaSpacing.sm),
                _Message(
                  icon: Icons.error_outline_rounded,
                  color: c.danger,
                  background: c.danger.withValues(alpha: 0.1),
                  text: _error!,
                ),
              ],
              for (final String warning in warnings) ...<Widget>[
                const SizedBox(height: AkibaSpacing.sm),
                _Message(
                  icon: Icons.info_outline_rounded,
                  color: c.warning,
                  background: c.warning.withValues(alpha: 0.12),
                  text: warning,
                ),
              ],
              const SizedBox(height: AkibaSpacing.xl),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.terracotta,
                    foregroundColor: c.onTerracotta,
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: Text(
                    _editing ? 'Mettre à jour' : 'Enregistrer',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(AkibaColors c, {required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AkibaTypography.body.copyWith(color: c.textMuted),
      filled: true,
      fillColor: c.surfaceElevated,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AkibaSpacing.lg,
        vertical: AkibaSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AkibaRadii.field),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    final AkibaColors c = AkibaColors.of(context);
    return Text(
      text,
      style: AkibaTypography.label.copyWith(
        color: c.textMuted,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AkibaDurations.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: AkibaSpacing.md,
          vertical: AkibaSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? c.terracotta : c.surfaceElevated,
          borderRadius: BorderRadius.circular(AkibaRadii.pill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? c.onTerracotta : c.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _QuickAmount extends StatelessWidget {
  const _QuickAmount({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AkibaSpacing.md,
          vertical: AkibaSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: c.ochre.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AkibaRadii.pill),
        ),
        child: Text(
          '$label FCFA',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.terracottaDeep,
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AkibaSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AkibaRadii.field),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AkibaSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AkibaTypography.legend.copyWith(
                color: color,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
