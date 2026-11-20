import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_command_parser.dart';
import '../../core/ai/ai_key_vault.dart';
import '../../core/ai/ai_model_catalog.dart';
import '../../core/ai/ai_quota.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/format/akiba_money.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/segmented_control.dart';
import '../../data/akiba_store.dart';
import '../../data/models/account.dart';
import '../../data/models/debt.dart';
import '../../data/models/savings_pot.dart';
import '../../data/models/transaction_record.dart';

const List<String> _expenseCategories = <String>[
  'Alimentation',
  'Transport',
  'Loyer',
  'Santé',
  'École',
  'Tontine',
  'Autre',
];

const List<String> _incomeCategories = <String>[
  'Salaire',
  'Vente',
  'Don',
  'Autre',
];

/// Ouvre l'assistant IA.
///
/// Analyse locale par défaut ; si une clé est enregistrée et que les appels
/// distants sont autorisés, les modèles choisis sont essayés en cascade
/// (délai court, bascule automatique) puis l'analyse locale reprend la main.
/// La proposition est toujours relue et modifiable : rien n'est écrit à
/// l'aveugle.
Future<void> openAssistant(
  BuildContext context, {
  required AkibaStore store,
  required AkibaDataRevision revision,
  required bool masked,
  required AkibaSettings settings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => _AssistantSheet(
      store: store,
      revision: revision,
      masked: masked,
      settings: settings,
    ),
  );
}

class _AssistantSheet extends StatefulWidget {
  const _AssistantSheet({
    required this.store,
    required this.revision,
    required this.masked,
    required this.settings,
  });

  final AkibaStore store;
  final AkibaDataRevision revision;
  final bool masked;
  final AkibaSettings settings;

  @override
  State<_AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends State<_AssistantSheet> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  late final Future<List<Account>> _accounts = widget.store.accounts();
  List<Account> _loaded = <Account>[];
  String? _accountId;
  String _category = _expenseCategories.first;
  AiDraft? _draft;
  TransactionKind _kind = TransactionKind.expense;
  bool _neutral = false;
  bool _listening = false;
  bool _analysing = false;
  final SpeechToText _speech = SpeechToText();
  String _engineNote = 'Analyse locale';
  String? _message;

  @override
  void initState() {
    super.initState();
    _accounts.then((List<Account> accounts) {
      if (!mounted) return;
      setState(() {
        _loaded = accounts;
        _accountId = accounts.isEmpty ? null : accounts.first.id;
      });
    });
  }

  @override
  void dispose() {
    _speech.cancel().catchError((Object _) => false);
    _text.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _analyse() async {
    if (_analysing) return;
    final AiDraft? local = AiCommandParser.parse(_text.text);
    if (local == null) {
      setState(() {
        _message =
            'Je n’ai pas trouvé de montant. Exemple : '
            '« j’ai payé 5 000 pour le transport ».';
      });
      return;
    }

    if (!widget.settings.aiRemoteEnabled) {
      _applyDraft(local, 'Analyse locale');
      return;
    }
    // Mode masqué : la phrase peut contenir un montant, rien ne part.
    if (widget.masked) {
      _applyDraft(local, 'Analyse locale · masquage actif');
      return;
    }

    setState(() {
      _analysing = true;
      _message = null;
    });
    try {
      final String? key = await AiKeyVault(widget.settings).read();
      if (!mounted) return;
      if (key == null) {
        _applyDraft(local, 'Analyse locale · clé absente');
        return;
      }
      // Quota journalier : une analyse distante = une unité, cascade comprise.
      final AiQuota quota = AiQuota(widget.settings);
      if (!await quota.consume()) {
        if (!mounted) return;
        _applyDraft(local, 'Analyse locale · quota du jour atteint');
        return;
      }
      final List<AiModel> models = AiModelCatalog.selected(
        AiModelCatalog.decode(widget.settings.raw('ai_models_cache')),
        widget.settings.raw('ai_model_priority'),
      );
      final AkibaAiClient client = AkibaAiClient(
        models: models,
        transport: GeminiTransport(apiKey: key).call,
        maxAttempts: widget.settings.aiMaxAttempts,
      );
      final AiCallResult result = await client.generate(
        task: AiTask.quickEntry,
        prompt: _remotePrompt(_text.text),
      );
      if (!mounted) return;
      if (!result.ok) {
        _applyDraft(local, result.note);
        return;
      }
      final AiDraft? remote = _readRemote(result.text!, local);
      _applyDraft(
        remote ?? local,
        remote == null
            ? 'Analyse locale · réponse du modèle illisible'
            : 'Modèle : ${result.modelId}',
      );
    } finally {
      if (mounted) setState(() => _analysing = false);
    }
  }

  /// Applique une proposition éditable, sans jamais écrire en base.
  void _applyDraft(AiDraft draft, String engine) {
    setState(() {
      _draft = draft;
      _kind = draft.kind;
      _amount.text = '${draft.amount}';
      _note.text = draft.note ?? _text.text;
      _neutral = draft.isNeutral;
      if (draft.category != null &&
          (_kind == TransactionKind.income
                  ? _incomeCategories
                  : _expenseCategories)
              .contains(draft.category)) {
        _category = draft.category!;
      } else {
        _category = _kind == TransactionKind.income
            ? _incomeCategories.first
            : _expenseCategories.first;
      }
      if (draft.fromBrand != null) {
        for (final Account account in _loaded) {
          if (account.brand.name == draft.fromBrand) _accountId = account.id;
        }
      }
      _engineNote = engine;
      _message = null;
    });
  }

  /// Consigne stricte : un seul objet JSON, aucune invention de montant.
  String _remotePrompt(String text) =>
      'Tu extrais une seule opération financière en FCFA depuis une phrase '
      'française. Réponds uniquement par un objet JSON sans texte autour, '
      'avec les clés : "amount" (entier positif), "kind" '
      '("expense"|"income"|"transfer"), "category" (chaîne ou null), '
      '"note" (chaîne courte), "neutral" (true si l’argent appartient à un '
      'tiers), "confidence" (0 à 1). N’invente aucun montant : si la phrase '
      'n’en contient pas, renvoie amount à 0.\nPhrase : ${jsonEncode(text)}';

  /// Relit la réponse du modèle ; toute anomalie renvoie `null` (repli local).
  AiDraft? _readRemote(String raw, AiDraft local) {
    String cleaned = raw.trim();
    final int start = cleaned.indexOf('{');
    final int end = cleaned.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    cleaned = cleaned.substring(start, end + 1);
    try {
      final Object? decoded = jsonDecode(cleaned);
      if (decoded is! Map) return null;
      final Object? amount = decoded['amount'];
      final int value = amount is int
          ? amount
          : int.tryParse('${amount ?? ''}') ?? 0;
      if (value <= 0) return null;
      final String kind = '${decoded['kind'] ?? 'expense'}'.toLowerCase();
      final Object? category = decoded['category'];
      final Object? note = decoded['note'];
      final Object? confidence = decoded['confidence'];
      return AiDraft(
        kind: switch (kind) {
          'income' => TransactionKind.income,
          'transfer' => TransactionKind.transfer,
          _ => TransactionKind.expense,
        },
        amount: value,
        category: category is String && category.trim().isNotEmpty
            ? category.trim()
            : local.category,
        note: note is String && note.trim().isNotEmpty
            ? note.trim()
            : local.note,
        isNeutral: decoded['neutral'] == true || local.isNeutral,
        occurredAt: local.occurredAt,
        fromBrand: local.fromBrand,
        toBrand: local.toBrand,
        confidence: confidence is num
            ? confidence.toDouble().clamp(0.0, 1.0)
            : 0.7,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final int amount = int.tryParse(_amount.text) ?? 0;
    if (amount <= 0 || amount > 999999999) {
      setState(() => _message = 'Montant invalide (1 à 999 999 999 FCFA).');
      return;
    }
    if (_accountId == null) {
      setState(() => _message = 'Aucun compte disponible.');
      return;
    }

    final AiDraft? draft = _draft;
    if (draft?.debtDirection != null) {
      await _saveDebt(amount, draft!.debtDirection!);
      return;
    }
    if (draft?.isSavings ?? false) {
      await _saveSavings(amount);
      return;
    }

    final DateTime now = DateTime.now();
    final TransactionRecord record = TransactionRecord(
      id: 'ai-${now.microsecondsSinceEpoch}',
      accountId: _accountId!,
      amount: _kind == TransactionKind.income ? amount : -amount,
      kind: _kind,
      category: _neutral || _kind == TransactionKind.transfer
          ? null
          : _category,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      isNeutral: _neutral,
      occurredAt: _draft?.occurredAt ?? now,
      createdAt: now,
    );

    try {
      await widget.store.saveTransaction(record);
      widget.revision.bump();
      if (!mounted) return;
      Navigator.of(context).pop();
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Proposition confirmée et enregistrée.'),
            duration: Duration(seconds: 3),
          ),
        );
    } catch (_) {
      setState(() => _message = 'Enregistrement impossible.');
    }
  }

  Future<void> _saveDebt(int amount, String direction) async {
    final DateTime now = DateTime.now();
    final String counterparty = _note.text.trim().isEmpty
        ? 'Contact'
        : _note.text.trim();
    try {
      await widget.store.saveDebt(
        Debt(
          id: 'debt-${now.microsecondsSinceEpoch}',
          direction: direction == 'owedToMe'
              ? DebtDirection.owedToMe
              : DebtDirection.iOwe,
          counterparty: counterparty,
          principal: amount,
          note: _text.text.trim(),
          createdAt: now,
        ),
      );
      widget.revision.bump();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              direction == 'owedToMe'
                  ? 'Créance enregistrée : elle reste hors du solde disponible.'
                  : 'Dette enregistrée : elle reste hors du solde disponible.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
    } catch (_) {
      setState(() => _message = 'Enregistrement impossible.');
    }
  }

  Future<void> _saveSavings(int amount) async {
    final DateTime now = DateTime.now();
    try {
      List<SavingsPot> pots = await widget.store.savingsPots();
      if (pots.isEmpty) {
        final SavingsPot pot = SavingsPot(
          id: 'pot-${now.microsecondsSinceEpoch}',
          name: 'Épargne libre',
          kind: SavingsKind.free,
          createdAt: now,
        );
        await widget.store.saveSavingsPot(pot);
        pots = <SavingsPot>[pot];
      }
      await widget.store.saveTransaction(
        TransactionRecord(
          id: 'ai-${now.microsecondsSinceEpoch}',
          accountId: _accountId!,
          amount: -amount,
          kind: TransactionKind.savings,
          savingsPotId: pots.first.id,
          note: _note.text.trim().isEmpty
              ? 'Versement épargne'
              : _note.text.trim(),
          occurredAt: _draft?.occurredAt ?? now,
          createdAt: now,
        ),
      );
      widget.revision.bump();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Versement d’épargne enregistré : le solde disponible ne baisse '
              'pas.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
    } catch (_) {
      setState(() => _message = 'Enregistrement impossible.');
    }
  }

  /// Dictée par le moteur de reconnaissance **de l'appareil**.
  ///
  /// Aucune clé API n'est requise : le moteur Android transcrit la phrase,
  /// puis `AiCommandParser` l'analyse localement (type, montant, catégorie).
  /// Si le téléphone n'a pas de moteur ou de modèle hors ligne, un message
  /// clair le dit et la saisie clavier reste disponible.
  Future<void> _voice() async {
    HapticFeedback.selectionClick();
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    bool available = false;
    try {
      available = await _speech.initialize(
        onStatus: (String status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _listening = false);
          }
        },
        onError: (SpeechRecognitionError error) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _message =
                'Dictée interrompue (${error.errorMsg}). Réessayez ou '
                'saisissez la phrase.';
          });
        },
      );
    } catch (_) {
      available = false;
    }

    if (!mounted) return;
    if (!available) {
      setState(() {
        _message =
            'Aucun moteur de reconnaissance vocale disponible sur cet '
            'appareil. Installez la reconnaissance vocale hors ligne dans les '
            'réglages Android, ou saisissez la phrase.';
      });
      return;
    }

    setState(() {
      _listening = true;
      _message = 'Parlez : « j’ai payé 5 000 pour le transport ».';
    });
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'fr_FR',
        // Reconnaissance **hors ligne** : si le téléphone n'a pas de modèle
        // français local, l'erreur est expliquée à l'utilisateur.
        onDevice: true,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
      onResult: (SpeechRecognitionResult result) {
        if (!mounted) return;
        setState(() {
          _text.text = result.recognizedWords;
          if (result.finalResult) _listening = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final bool wide = MediaQuery.sizeOf(context).width >= 720;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(wide ? AkibaRadii.card : AkibaRadii.card),
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
                constraints: const BoxConstraints(maxWidth: 640),
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
                                'ASSISTANT IA',
                                style: AkibaTypography.label.copyWith(
                                  color: c.textMuted,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              Text(
                                'Dites-moi ce qui s’est passé',
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
                    TextField(
                      controller: _text,
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _field(
                        c,
                        'Ex. « j’ai payé 5 000 pour le transport hier »',
                      ),
                    ),
                    const SizedBox(height: AkibaSpacing.sm),
                    Row(
                      children: <Widget>[
                        _MicButton(listening: _listening, onTap: _voice),
                        const SizedBox(width: AkibaSpacing.sm),
                        Expanded(
                          child: Text(
                            widget.settings.aiRemoteEnabled
                                ? 'Relecture obligatoire avant toute écriture.'
                                : 'Analyse locale, sans réseau. Vous relisez '
                                      'avant d’enregistrer.',
                            style: AkibaTypography.legend.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: _analysing ? null : _analyse,
                          child: Text(_analysing ? 'Analyse…' : 'Analyser'),
                        ),
                      ],
                    ),
                    if (_message != null) ...<Widget>[
                      const SizedBox(height: AkibaSpacing.sm),
                      Text(
                        _message!,
                        style: AkibaTypography.legend.copyWith(
                          color: _message!.startsWith('Micro')
                              ? c.warning
                              : c.danger,
                        ),
                      ),
                    ],
                    if (_draft != null) ...<Widget>[
                      const SizedBox(height: AkibaSpacing.xl),
                      Container(
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
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 18,
                                  color: c.terracotta,
                                ),
                                const SizedBox(width: AkibaSpacing.sm),
                                Expanded(
                                  child: Text(
                                    'Carte de compréhension · à vérifier',
                                    style: AkibaTypography.label.copyWith(
                                      color: c.textMuted,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                                Flexible(
                                  child: Text(
                                    '$_engineNote · '
                                    '${_confidenceLabel(_draft!.confidence)}',
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
                            const SizedBox(height: AkibaSpacing.md),
                            SegmentedControl(
                              segments: const <String>[
                                'Sortie',
                                'Entrée',
                                'Tiers',
                              ],
                              selectedIndex: _neutral
                                  ? 2
                                  : (_kind == TransactionKind.income ? 1 : 0),
                              onChanged: (int index) => setState(() {
                                if (index == 2) {
                                  _neutral = true;
                                } else {
                                  _neutral = false;
                                  _kind = index == 1
                                      ? TransactionKind.income
                                      : TransactionKind.expense;
                                  _category = _kind == TransactionKind.income
                                      ? _incomeCategories.first
                                      : _expenseCategories.first;
                                }
                              }),
                            ),
                            const SizedBox(height: AkibaSpacing.md),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: TextField(
                                    controller: _amount,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: <TextInputFormatter>[
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(9),
                                    ],
                                    decoration: _field(c, 'Montant'),
                                  ),
                                ),
                                const SizedBox(width: AkibaSpacing.sm),
                                Text(
                                  'FCFA',
                                  style: AkibaTypography.legend.copyWith(
                                    color: c.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AkibaSpacing.md),
                            DropdownButtonFormField<String>(
                              initialValue:
                                  _loaded.any((Account a) => a.id == _accountId)
                                  ? _accountId
                                  : null,
                              decoration: _field(c, 'Compte'),
                              items: <DropdownMenuItem<String>>[
                                for (final Account account in _loaded)
                                  DropdownMenuItem<String>(
                                    value: account.id,
                                    child: Text(
                                      '${account.name} · ${account.brand.label}',
                                    ),
                                  ),
                              ],
                              onChanged: (String? value) =>
                                  setState(() => _accountId = value),
                            ),
                            const SizedBox(height: AkibaSpacing.md),
                            if (!_neutral)
                              DropdownButtonFormField<String>(
                                initialValue: _category,
                                decoration: _field(c, 'Catégorie'),
                                items: <DropdownMenuItem<String>>[
                                  for (final String category
                                      in _kind == TransactionKind.income
                                          ? _incomeCategories
                                          : _expenseCategories)
                                    DropdownMenuItem<String>(
                                      value: category,
                                      child: Text(category),
                                    ),
                                ],
                                onChanged: (String? value) {
                                  if (value != null) {
                                    setState(() => _category = value);
                                  }
                                },
                              ),
                            const SizedBox(height: AkibaSpacing.md),
                            TextField(
                              controller: _note,
                              decoration: _field(c, 'Note'),
                            ),
                            const SizedBox(height: AkibaSpacing.md),
                            Text(
                              _neutral
                                  ? 'Argent de tiers : la ligne sera isolée du '
                                        'solde disponible, du budget et des '
                                        'statistiques.'
                                  : _kind == TransactionKind.income
                                  ? 'Entrée enregistrée sur le compte choisi.'
                                  : 'Sortie enregistrée sur le compte choisi.',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.lg),
                            FilledButton.icon(
                              onPressed: _save,
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: Text('Confirmer · ${_previewAmount()}'),
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            Text(
                              'Aucune écriture n’est faite avant ce bouton.',
                              textAlign: TextAlign.center,
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _previewAmount() {
    final int value = int.tryParse(_amount.text) ?? 0;
    if (value <= 0) return 'enregistrer';
    return AkibaMoney.format(value, masked: widget.masked);
  }

  String _confidenceLabel(double confidence) =>
      confidence >= 0.7 ? 'compris' : 'à confirmer';

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

class _MicButton extends StatelessWidget {
  const _MicButton({required this.listening, required this.onTap});

  final bool listening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: listening ? 0.85 : 1, end: 1),
      duration: const Duration(milliseconds: 700),
      builder: (BuildContext context, double value, Widget? child) =>
          Transform.scale(scale: value, child: child),
      child: Semantics(
        button: true,
        label: 'Dicter une opération',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AkibaDurations.fast,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: listening
                  ? c.terracotta.withValues(alpha: 0.18)
                  : c.iconTile,
              border: listening
                  ? Border.all(color: c.terracotta, width: 2)
                  : null,
            ),
            child: Icon(
              listening ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
              color: c.terracottaDeep,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
