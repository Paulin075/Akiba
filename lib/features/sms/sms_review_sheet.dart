import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/akiba_money.dart';
import '../../core/sms/sms_parser.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/segmented_control.dart';
import '../../data/akiba_store.dart';
import '../../data/models/account.dart';
import '../../data/models/transaction_record.dart';

/// Revue des SMS financiers.
///
/// La détection automatique (Flooz, Mixx by Yas, banques) vit dans le récepteur
/// Android : elle ouvre la fiche préremplie et ne notifie jamais avec un
/// montant. Cette feuille reste le chemin manuel : le texte est collé ou
/// saisi, puis chaque message est classé à la main. Rien n'est enregistré
/// automatiquement.
Future<void> openSmsReview(
  BuildContext context, {
  required AkibaStore store,
  required AkibaDataRevision revision,
  required bool masked,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) =>
        _SmsSheet(store: store, revision: revision, masked: masked),
  );
}

class _SmsSheet extends StatefulWidget {
  const _SmsSheet({
    required this.store,
    required this.revision,
    required this.masked,
  });

  final AkibaStore store;
  final AkibaDataRevision revision;
  final bool masked;

  @override
  State<_SmsSheet> createState() => _SmsSheetState();
}

class _SmsSheetState extends State<_SmsSheet> {
  final TextEditingController _text = TextEditingController();
  late final Future<List<Account>> _accounts = widget.store.accounts();
  List<Account> _loaded = <Account>[];
  List<_SmsRow> _rows = <_SmsRow>[];
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _accounts.then((List<Account> accounts) {
      if (!mounted) return;
      setState(() => _loaded = accounts);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _parse() {
    final List<SmsDraft> drafts = SmsParser.parse(_text.text);
    if (drafts.isEmpty) {
      setState(() {
        _rows = <_SmsRow>[];
        _message = 'Aucun montant FCFA reconnu dans ce texte.';
      });
      return;
    }
    setState(() {
      _rows = <_SmsRow>[
        for (final SmsDraft draft in drafts)
          _SmsRow(
            draft: draft,
            direction: draft.direction,
            accountId: _accountFor(draft.operator),
            neutral: draft.isNeutral,
          ),
      ];
      _message = null;
    });
  }

  String? _accountFor(String? operator) {
    if (_loaded.isEmpty) return null;
    String? brand;
    if (operator == 'Flooz') brand = 'flooz';
    if (operator == 'Mixx by Yas') brand = 'mixx';
    if (operator == 'Orabank') brand = 'orabank';
    for (final Account account in _loaded) {
      if (account.brand.name == brand) return account.id;
    }
    return _loaded.first.id;
  }

  void _sample() {
    _text.text =
        'Flooz: Vous avez recu 25000 FCFA de KOFFI Ama le 18/11/2026. '
        'Reference FL8842. Frais 0 FCFA.\n\n'
        'Mixx by Yas: Paiement de 3500 FCFA effectue chez ALIMENTATION '
        'DU MARCHE. Ref MX2210.\n\n'
        'Orabank: Debit de 120000 FCFA - LOYER NOVEMBRE.';
    _parse();
  }

  Future<void> _save(_SmsRow row) async {
    if (row.accountId == null) {
      setState(() => _message = 'Choisissez un compte.');
      return;
    }
    if (row.direction == SmsDirection.unknown) {
      setState(() => _message = 'Classez le message avant d’enregistrer.');
      return;
    }

    setState(() => _busy = true);
    final DateTime now = DateTime.now();
    final bool income = row.direction == SmsDirection.income;
    final TransactionRecord record = TransactionRecord(
      id: 'sms-${now.microsecondsSinceEpoch}-${row.hashCode}',
      accountId: row.accountId!,
      amount: income ? row.draft.amount : -row.draft.amount,
      kind: income ? TransactionKind.income : TransactionKind.expense,
      category: row.neutral ? null : (income ? 'SMS' : 'SMS'),
      note: row.neutral
          ? 'SMS · argent de tiers'
          : 'SMS ${row.draft.operator ?? ''}'.trim(),
      isNeutral: row.neutral,
      occurredAt: row.draft.occurredAt ?? now,
      createdAt: now,
    );

    try {
      await widget.store.saveTransaction(record);
      widget.revision.bump();
      if (!mounted) return;
      setState(() {
        _rows = _rows.where((_SmsRow r) => !identical(r, row)).toList();
        _message = keyboardMessage(row.draft.amount, widget.masked);
      });
      HapticFeedback.lightImpact();
    } catch (_) {
      setState(() => _message = 'Enregistrement impossible.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String keyboardMessage(int amount, bool masked) => masked
      ? 'SMS enregistré · montant masqué.'
      : 'SMS enregistré : ${AkibaMoney.format(amount)}';

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.94,
      ),
      child: Container(
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
                constraints: const BoxConstraints(maxWidth: 720),
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
                                'SMS FINANCIERS',
                                style: AkibaTypography.label.copyWith(
                                  color: c.textMuted,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              Text(
                                'Relire avant d’enregistrer',
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
                    const SizedBox(height: AkibaSpacing.sm),
                    Text(
                      'La lecture automatique de la boîte SMS demande le module '
                      'Android et une autorisation explicite. Collez ici un ou '
                      'plusieurs SMS (séparés par une ligne vide) : Flooz, Mixx '
                      'by Yas et Orabank sont reconnus.',
                      style: AkibaTypography.legend.copyWith(
                        color: c.textMuted,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AkibaSpacing.md),
                    TextField(
                      controller: _text,
                      minLines: 3,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _field(c, 'Collez un SMS financier'),
                    ),
                    const SizedBox(height: AkibaSpacing.sm),
                    Wrap(
                      spacing: AkibaSpacing.sm,
                      runSpacing: AkibaSpacing.sm,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: _parse,
                          icon: const Icon(Icons.search_rounded, size: 18),
                          label: const Text('Analyser'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _sample,
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            size: 18,
                          ),
                          label: const Text('Exemple'),
                        ),
                      ],
                    ),
                    if (_message != null) ...<Widget>[
                      const SizedBox(height: AkibaSpacing.md),
                      Text(
                        _message!,
                        style: AkibaTypography.legend.copyWith(
                          color: c.textMuted,
                        ),
                      ),
                    ],
                    const SizedBox(height: AkibaSpacing.lg),
                    for (final _SmsRow row in _rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AkibaSpacing.md),
                        child: _SmsCard(
                          row: row,
                          accounts: _loaded,
                          masked: widget.masked,
                          busy: _busy,
                          onDirection: (SmsDirection value) =>
                              setState(() => row.direction = value),
                          onAccount: (String? id) =>
                              setState(() => row.accountId = id),
                          onNeutral: (bool value) =>
                              setState(() => row.neutral = value),
                          onSave: () => _save(row),
                          onIgnore: () => setState(
                            () => _rows = _rows
                                .where((_SmsRow r) => !identical(r, row))
                                .toList(),
                          ),
                        ),
                      ),
                    if (_rows.isEmpty)
                      Text(
                        'Aucune proposition en attente.',
                        style: AkibaTypography.legend.copyWith(
                          color: c.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _field(AkibaColors c, String hint) => InputDecoration(
    hintText: hint,
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
}

class _SmsRow {
  _SmsRow({
    required this.draft,
    required this.direction,
    required this.accountId,
    required this.neutral,
  });

  final SmsDraft draft;
  SmsDirection direction;
  String? accountId;
  bool neutral;
}

class _SmsCard extends StatelessWidget {
  const _SmsCard({
    required this.row,
    required this.accounts,
    required this.masked,
    required this.busy,
    required this.onDirection,
    required this.onAccount,
    required this.onNeutral,
    required this.onSave,
    required this.onIgnore,
  });

  final _SmsRow row;
  final List<Account> accounts;
  final bool masked;
  final bool busy;
  final ValueChanged<SmsDirection> onDirection;
  final ValueChanged<String?> onAccount;
  final ValueChanged<bool> onNeutral;
  final VoidCallback onSave;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final SmsDraft draft = row.draft;
    final int segment = switch (row.direction) {
      SmsDirection.expense => 0,
      SmsDirection.income => 1,
      SmsDirection.unknown => 0,
    };

    return Container(
      padding: const EdgeInsets.all(AkibaSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AkibaRadii.card),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  AkibaMoney.format(draft.amount, masked: masked),
                  style: AkibaTypography.money(
                    20,
                    color: draft.direction == SmsDirection.unknown
                        ? c.textPrimary
                        : (draft.direction == SmsDirection.income
                              ? c.success
                              : c.danger),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AkibaSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: c.iconTile,
                  borderRadius: BorderRadius.circular(AkibaRadii.pill),
                ),
                child: Text(
                  draft.operator ?? 'SMS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: c.terracottaDeep,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AkibaSpacing.xs),
          Text(
            draft.raw,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AkibaTypography.legend.copyWith(
              color: c.textMuted,
              height: 1.35,
            ),
          ),
          if (draft.reference != null || draft.fee != null) ...<Widget>[
            const SizedBox(height: AkibaSpacing.xs),
            Text(
              <String>[
                if (draft.reference != null) 'Réf. ${draft.reference}',
                if (draft.fee != null)
                  'Frais ${AkibaMoney.format(draft.fee!, masked: masked)}',
              ].join(' · '),
              style: AkibaTypography.legend.copyWith(
                color: c.textMuted,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: AkibaSpacing.md),
          SegmentedControl(
            segments: const <String>['Sortie', 'Entrée'],
            selectedIndex: segment,
            onChanged: (int index) => onDirection(
              index == 0 ? SmsDirection.expense : SmsDirection.income,
            ),
          ),
          const SizedBox(height: AkibaSpacing.md),
          DropdownButtonFormField<String>(
            // Si la ligne référence un compte absent de la liste (compte
            // supprimé entre deux ouvertures), on retombe sur le premier :
            // sinon Flutter lève l'assertion « exactly one item ».
            initialValue: accounts.any((Account a) => a.id == row.accountId)
                ? row.accountId
                : (accounts.isEmpty ? null : accounts.first.id),
            decoration: InputDecoration(
              filled: true,
              fillColor: c.surfaceElevated,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AkibaSpacing.md,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AkibaRadii.field),
                borderSide: BorderSide.none,
              ),
            ),
            items: <DropdownMenuItem<String>>[
              for (final Account account in accounts)
                DropdownMenuItem<String>(
                  value: account.id,
                  child: Text('${account.name} · ${account.brand.label}'),
                ),
            ],
            onChanged: onAccount,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: row.neutral,
            onChanged: onNeutral,
            title: Text(
              'Isoler comme argent de tiers',
              style: TextStyle(fontSize: 13, color: c.textPrimary),
            ),
            subtitle: Text(
              'Exclu du solde disponible, du budget et des statistiques.',
              style: AkibaTypography.legend.copyWith(
                color: c.textMuted,
                fontSize: 11,
              ),
            ),
          ),
          Row(
            children: <Widget>[
              TextButton(
                onPressed: busy ? null : onIgnore,
                child: const Text('Ignorer'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: busy ? null : onSave,
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
