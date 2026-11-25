import 'package:flutter/material.dart';

import '../../core/format/akiba_date.dart';
import '../../core/format/akiba_money.dart';
import '../../core/format/transaction_display.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../data/akiba_store.dart';
import '../../data/models/transaction_record.dart';
import '../../data/transaction_reclassifier.dart';

/// Action renvoyée par la fiche de détail quand la personne veut ouvrir la
/// saisie complète.
enum MovementDetailAction { edit }

/// Fiche de détail d'un mouvement : tout ce qui est enregistré, puis le
/// reclassement de la catégorie.
///
/// Le reclassement ne touche qu'à la catégorie : le montant, la date, le compte
/// et l'identifiant restent identiques, donc les soldes dérivés ne bougent pas.
/// L'argent de tiers, les transferts, l'épargne et les soldes d'ouverture
/// restent hors catégorie, avec l'explication affichée.
Future<MovementDetailAction?> showMovementDetail(
  BuildContext context, {
  required TransactionLine line,
  required AkibaStore store,
  required AkibaDataRevision revision,
  required bool masked,
}) {
  return showModalBottomSheet<MovementDetailAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => _MovementDetailSheet(
      line: line,
      store: store,
      revision: revision,
      masked: masked,
    ),
  );
}

class _MovementDetailSheet extends StatefulWidget {
  const _MovementDetailSheet({
    required this.line,
    required this.store,
    required this.revision,
    required this.masked,
  });

  final TransactionLine line;
  final AkibaStore store;
  final AkibaDataRevision revision;
  final bool masked;

  @override
  State<_MovementDetailSheet> createState() => _MovementDetailSheetState();
}

class _MovementDetailSheetState extends State<_MovementDetailSheet> {
  late TransactionRecord _record = widget.line.transaction;
  bool _saving = false;

  Future<void> _reclassify(String? category) async {
    if (_saving || category == _record.category) return;
    final TransactionRecord updated = TransactionReclassifier.withCategory(
      _record,
      category,
    );
    setState(() => _saving = true);
    try {
      await widget.store.saveTransaction(updated);
      widget.revision.bump();
      if (!mounted) return;
      setState(() {
        _record = updated;
        _saving = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              category == null
                  ? 'Catégorie retirée.'
                  : 'Catégorie mise à jour : $category.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Reclassement impossible.'),
            duration: Duration(seconds: 3),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final bool canReclassify = TransactionReclassifier.canReclassify(_record);
    final String? blocked = _blockedReason(_record);

    return Container(
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AkibaRadii.card),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AkibaSpacing.screen,
            AkibaSpacing.lg,
            AkibaSpacing.screen,
            AkibaSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'DÉTAIL DU MOUVEMENT',
                              style: AkibaTypography.label.copyWith(
                                color: c.textMuted,
                                letterSpacing: 1.6,
                              ),
                            ),
                            Text(
                              TransactionDisplay.titleFor(_record),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AkibaTypography.sectionTitle.copyWith(
                                fontSize: 18,
                                color: c.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fermer',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: AkibaSpacing.md),
                  Text(
                    AkibaMoney.formatSigned(
                      _record.amount,
                      masked: widget.masked,
                    ),
                    style: AkibaTypography.money(
                      26,
                      color: TransactionDisplay.amountColor(_record, c),
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AkibaSpacing.lg),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(AkibaRadii.card),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _row(c, 'Type', _kindLabel(_record.kind)),
                        _row(
                          c,
                          'Compte',
                          '${widget.line.account.name} · '
                              '${widget.line.account.brand.label}',
                        ),
                        _row(c, 'Date', _dateLabel(_record.occurredAt)),
                        _row(c, 'Catégorie', _record.category ?? 'Aucune'),
                        if (_record.note != null &&
                            _record.note!.trim().isNotEmpty)
                          _row(c, 'Note', _record.note!.trim()),
                        if (_record.isNeutral)
                          _row(c, 'Nature', 'Argent de tiers'),
                        _row(
                          c,
                          'Budget',
                          _record.countsForBudget
                              ? 'Compté dans le budget et les statistiques'
                              : 'Hors budget et hors statistiques',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.xl),
                  Text(
                    'RECLASSER',
                    style: AkibaTypography.label.copyWith(
                      color: c.textMuted,
                      letterSpacing: 1.3,
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.sm),
                  if (!canReclassify)
                    Text(
                      blocked ??
                          'Ce mouvement reste hors budget : il n’a pas '
                              'de catégorie.',
                      style: AkibaTypography.legend.copyWith(
                        color: c.textMuted,
                        height: 1.4,
                      ),
                    )
                  else ...<Widget>[
                    Text(
                      'La catégorie seule change. Le montant, la date et le '
                      'compte restent identiques : aucun solde ne bouge.',
                      style: AkibaTypography.legend.copyWith(
                        color: c.textMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AkibaSpacing.sm),
                    Wrap(
                      spacing: AkibaSpacing.sm,
                      runSpacing: AkibaSpacing.xs,
                      children: <Widget>[
                        for (final String category
                            in TransactionReclassifier.categoriesFor(_record))
                          ChoiceChip(
                            label: Text(category),
                            selected: _record.category == category,
                            onSelected: _saving
                                ? null
                                : (_) => _reclassify(category),
                          ),
                        ChoiceChip(
                          label: const Text('Aucune'),
                          selected: _record.category == null,
                          onSelected: _saving ? null : (_) => _reclassify(null),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AkibaSpacing.xl),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Fermer'),
                        ),
                      ),
                      const SizedBox(width: AkibaSpacing.sm),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(MovementDetailAction.edit),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Modifier'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(AkibaColors c, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: AkibaSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: AkibaTypography.legend.copyWith(color: c.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AkibaTypography.body.copyWith(color: c.textPrimary),
          ),
        ),
      ],
    ),
  );

  static String _kindLabel(TransactionKind kind) => switch (kind) {
    TransactionKind.income => 'Entrée',
    TransactionKind.expense => 'Sortie',
    TransactionKind.transfer => 'Transfert',
    TransactionKind.savings => 'Épargne',
    TransactionKind.opening => 'Solde d’ouverture',
  };

  static String _dateLabel(DateTime date) {
    final DateTime local = date.toLocal();
    return '${AkibaDate.short(local)} · ${AkibaDate.time(local)}';
  }

  static String? _blockedReason(TransactionRecord record) {
    if (record.isNeutral) {
      return 'Argent de tiers : cette ligne reste hors budget, elle n’a donc '
          'pas de catégorie.';
    }
    return switch (record.kind) {
      TransactionKind.transfer =>
        'Un transfert entre comptes n’a pas de catégorie de budget.',
      TransactionKind.savings =>
        'Un mouvement d’épargne n’a pas de catégorie de budget.',
      TransactionKind.opening => 'Un solde d’ouverture n’a pas de catégorie.',
      _ => null,
    };
  }
}
