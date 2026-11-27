import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_command_parser.dart';
import '../../core/ai/ai_finance_context.dart';
import '../../core/ai/ai_quota.dart';
import '../../core/ai/ai_remote.dart';
import '../../core/ai/ai_text.dart';
import '../../core/format/akiba_date.dart';
import '../../core/savings/savings_messages.dart';
import '../../core/savings/savings_projection.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/format/akiba_money.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/segmented_control.dart';
import '../../core/widgets/savings_celebration.dart';
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

  /// Objectif d'épargne : nom du coffre et prix à atteindre. Le montant
  /// quotidien reste dans `_amount`.
  final TextEditingController _goalName = TextEditingController();
  final TextEditingController _goalTarget = TextEditingController();

  late final Future<List<Account>> _accounts = widget.store.accounts();
  List<Account> _loaded = <Account>[];
  String? _accountId;
  String _category = _expenseCategories.first;
  AiDraft? _draft;
  TransactionKind _kind = TransactionKind.expense;
  bool _neutral = false;

  /// « owedToMe » / « iOwe » quand la phrase décrit une créance ou une dette.
  /// Dans ce cas, aucune sortie d'argent n'est écrite : la créance ou la
  /// dette est suivie séparément du solde disponible.
  String? _debtDirection;

  /// Créances / dettes ouvertes (pour proposer le règlement d'une ligne
  /// existante au lieu d'en créer une nouvelle).
  List<Debt> _debts = const <Debt>[];
  bool _settleMode = false;
  String? _debtId;

  bool _listening = false;
  bool _analysing = false;
  final SpeechToText _speech = SpeechToText();
  String _engineNote = 'Analyse locale';
  String? _message;

  /// Compte crédité d'un transfert (le compte débité reste `_accountId`).
  String? _toAccountId;

  /// Réponse en langage naturel à une question sur la situation financière.
  /// Elle n'écrit jamais en base : seule la carte d'opération le fait.
  String? _answer;

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
    widget.store
        .debts()
        .then((List<Debt> debts) {
          if (!mounted) return;
          setState(() {
            _debts = debts.where((Debt d) => !d.isSettled).toList();
          });
        })
        .catchError((Object _) {});
  }

  /// Créances ou dettes ouvertes du même sens que la phrase.
  List<Debt> get _matchingDebts => <Debt>[
    for (final Debt debt in _debts)
      if (!debt.isSettled && debt.direction.name == _debtDirection) debt,
  ];

  Debt? get _selectedDebt {
    for (final Debt debt in _matchingDebts) {
      if (debt.id == _debtId) return debt;
    }
    return null;
  }

  /// Bascule entre « nouvelle créance/dette » et « règlement d'une ligne
  /// existante ». En mode règlement, le montant et le contact sont préremplis
  /// depuis la première ligne ouverte du même sens.
  void _toggleSettle() {
    setState(() {
      _settleMode = !_settleMode;
      _message = null;
      if (_settleMode) {
        final List<Debt> open = _matchingDebts;
        if (open.isNotEmpty) {
          final Debt debt = open.first;
          _debtId = debt.id;
          _amount.text = '${debt.remaining}';
          _note.text = debt.counterparty;
        } else {
          _debtId = null;
        }
      }
    });
  }

  @override
  void dispose() {
    _speech.cancel().catchError((Object _) => false);
    _text.dispose();
    _amount.dispose();
    _note.dispose();
    _goalName.dispose();
    _goalTarget.dispose();
    super.dispose();
  }

  Future<void> _analyse() async {
    if (_analysing) return;
    final AiDraft? local = AiCommandParser.parse(_text.text);
    if (local == null) {
      // Pas de montant : c'est une question (« combien me reste-t-il ? »),
      // pas un ordre. L'IA répond avec le résumé local, sans rien écrire.
      await _discuss();
      return;
    }

    // Créance / dette : le sens est déjà déterminé par la phrase, aucun
    // modèle ne peut le contredire. On applique la lecture locale.
    if (local.debtDirection != null) {
      _applyDraft(local, 'Analyse locale · créance / dette');
      return;
    }

    // Objectif d'épargne récurrent : « 100 FCFA par jour pour un moniteur ».
    // Le montant est un versement quotidien, jamais une dépense : la lecture
    // locale est appliquée avant le modèle distant, qui l'avait comprise comme
    // une sortie « Alimentation ».
    if (local.isSavingsGoal) {
      _applyDraft(local, 'Analyse locale · objectif d’épargne');
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
      _answer = null;
    });
    try {
      // Fournisseur choisi (Gemini, DeepSeek, OpenRouter, Home Lab / Ollama) :
      // masquage, appels distants coupés, adresse invalide ou clé absente
      // renvoient directement au moteur local.
      final AiRemoteResolution resolution = await resolveAiRemote(
        widget.settings,
        masked: widget.masked,
      );
      if (!mounted) return;
      final AiRemoteSetup? setup = resolution.setup;
      if (setup == null) {
        _applyDraft(local, resolution.note);
        return;
      }
      // Quota journalier : une analyse distante = une unité, cascade comprise.
      final AiQuota quota = AiQuota(widget.settings);
      if (!await quota.consume()) {
        if (!mounted) return;
        _applyDraft(local, 'Analyse locale · quota du jour atteint');
        return;
      }
      final AkibaAiClient client = AkibaAiClient(
        models: setup.models,
        transport: setup.transport,
        maxAttempts: widget.settings.aiMaxAttempts,
      );
      // Le modèle reçoit la situation locale (soldes, budgets, coffres) pour
      // lever toute ambiguïté et produire une action structurée fiable.
      final AiFinanceSummary summary = await AiFinanceSummary.build(
        widget.store,
        masked: widget.masked,
        language: widget.settings.language,
      );
      final AiCallResult result = await client.generate(
        task: AiTask.quickEntry,
        prompt: _remotePrompt(_text.text, summary),
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
            : '${setup.provider.label} · ${result.modelId}',
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
      // Créance / dette : le champ devient le contact. « On me doit 12 000 »
      // ne doit pas enregistrer toute la phrase comme nom de contact.
      _note.text = draft.debtDirection != null
          ? (draft.counterparty ?? '')
          : (draft.note ?? _text.text);
      _neutral = draft.isNeutral;
      _debtDirection = draft.debtDirection;
      if (draft.isSavingsGoal) {
        _goalName.text = draft.goalName ?? 'Objectif';
        _goalTarget.text = draft.targetAmount > 0
            ? '${draft.targetAmount}'
            : '';
      } else {
        _goalName.clear();
        _goalTarget.clear();
      }
      if (draft.debtDirection == null) {
        _settleMode = false;
        _debtId = null;
      }
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
        _accountId = _matchAccount(draft.fromBrand!) ?? _accountId;
      }
      if (draft.toBrand != null) {
        _toAccountId = _matchAccount(draft.toBrand!);
      }
      if (_kind == TransactionKind.transfer) {
        _toAccountId ??= _firstOtherAccountId();
      }
      _engineNote = engine;
      _message = null;
      _answer = null;
    });
  }

  /// Question libre : réponse conseil, sans écriture.
  Future<void> _discuss() async {
    if (widget.masked) {
      setState(() {
        _message =
            'Mode masqué : je ne lis ni n’envoie aucun montant. Désactivez le '
            'masquage pour une analyse chiffrée, ou dictez une opération.';
      });
      return;
    }
    if (!widget.settings.aiRemoteEnabled) {
      setState(() {
        _message =
            'Sans IA configurée, je ne peux pas discuter : dictez une opération '
            '(« j’ai payé 5 000 pour le transport ») — l’analyse locale la '
            'comprendra.';
      });
      return;
    }

    setState(() {
      _analysing = true;
      _message = null;
      _answer = null;
    });
    try {
      final AiRemoteResolution resolution = await resolveAiRemote(
        widget.settings,
        masked: widget.masked,
      );
      if (!mounted) return;
      final AiRemoteSetup? setup = resolution.setup;
      if (setup == null) {
        setState(() => _message = resolution.note);
        return;
      }
      final AiQuota quota = AiQuota(widget.settings);
      if (!await quota.consume()) {
        if (!mounted) return;
        setState(() => _message = 'Quota du jour atteint : réessayez demain.');
        return;
      }
      final AiFinanceSummary summary = await AiFinanceSummary.build(
        widget.store,
        masked: widget.masked,
        language: widget.settings.language,
      );
      final AkibaAiClient client = AkibaAiClient(
        models: setup.models,
        transport: setup.transport,
        maxAttempts: widget.settings.aiMaxAttempts,
      );
      final AiCallResult result = await client.generate(
        task: AiTask.coaching,
        prompt: _discussionPrompt(_text.text, summary),
      );
      if (!mounted) return;
      if (!result.ok) {
        setState(() => _message = result.note);
        return;
      }
      // Le modèle répond souvent en JSON (`{"conseil_financier": "..."}`) :
      // on n'affiche que la prose, jamais l'objet brut.
      final String answer = AiText.plain(result.text!);
      if (answer.isEmpty) {
        setState(() {
          _message =
              'Le modèle a répondu hors format : reformulez la question en une '
              'phrase.';
        });
        return;
      }
      setState(() {
        _answer = answer;
        _engineNote = '${setup.provider.label} · ${result.modelId}';
        _message = null;
      });
    } finally {
      if (mounted) setState(() => _analysing = false);
    }
  }

  /// Consigne de discussion : le modèle conseille, il n'écrit jamais lui-même.
  String _discussionPrompt(String text, AiFinanceSummary summary) =>
      'Tu es le conseiller financier prudent d’AKIBA. Réponds en français, '
      'en 120 mots maximum, en t’appuyant uniquement sur le résumé ci-dessous. '
      'Ne propose jamais d’inventer un montant, ne dis jamais que l’argent de '
      'tiers est un revenu, et rappelle qu’une action doit être confirmée '
      'dans l’application. Si la question appelle une opération précise, '
      'indique-la en une phrase commençant par « Dites : ».\n'
      '${summary.toPrompt()}\nQuestion : ${jsonEncode(text)}';

  /// Consigne stricte : un seul objet JSON, aucune invention de montant.
  String _remotePrompt(String text, AiFinanceSummary summary) {
    final String accounts = _loaded
        .map((Account a) => '${a.name} (${a.brand.label})')
        .join(', ');
    return 'Tu transformes une phrase française en UNE opération AKIBA, en '
        'FCFA entiers. Réponds uniquement par un objet JSON, sans texte '
        'autour, avec les clés : "action" '
        '("expense"|"income"|"transfer"|"savings"|"savings_goal"|'
        '"third_party"|"debt"), "amount" (entier positif), "account" (nom ou '
        'support source), "to_account" (destination d’un transfert), "category" '
        '(chaîne ou null), "note" (chaîne courte), "debtDirection" '
        '("owedToMe"|"iOwe"|null), "daily_amount" et "target" (pour '
        '"savings_goal" : versement quotidien et prix de l’objectif, 0 si '
        'inconnu), "goal" (nom de l’objectif), "confidence" (0 à 1). '
        'Un versement quotidien d’épargne n’est jamais une dépense. N’invente '
        'aucun montant : si la phrase n’en contient pas, renvoie amount à 0.\n'
        'Comptes disponibles : $accounts.\n${summary.toPrompt()}\n'
        'Phrase : ${jsonEncode(text)}';
  }

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
      final String action =
          '${decoded['action'] ?? decoded['kind'] ?? 'expense'}'.toLowerCase();
      final bool goalAction = action == 'savings_goal';
      final Object? category = decoded['category'];
      final Object? goal = decoded['goal'];
      final Object? target = decoded['target'];
      final Object? daily = decoded['daily_amount'] ?? decoded['daily'];
      final Object? note = decoded['note'];
      final Object? confidence = decoded['confidence'];
      final Object? from = decoded['account'] ?? decoded['from'];
      final Object? to = decoded['to_account'] ?? decoded['to'];
      final String? direction = switch ('${decoded['debtDirection']}') {
        'owedToMe' => 'owedToMe',
        'iOwe' => 'iOwe',
        _ => action == 'debt' ? 'owedToMe' : null,
      };
      return AiDraft(
        kind: switch (action) {
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
        isNeutral:
            action == 'third_party' ||
            decoded['neutral'] == true ||
            local.isNeutral,
        isSavings: action == 'savings' || goalAction || local.isSavings,
        isSavingsGoal: goalAction || local.isSavingsGoal,
        dailyAmount: goalAction
            ? (daily is num
                  ? daily.toInt()
                  : int.tryParse('${daily ?? ''}') ?? value)
            : local.dailyAmount,
        goalName: goal is String && goal.trim().isNotEmpty
            ? goal.trim()
            : local.goalName,
        targetAmount: target is num
            ? target.toInt()
            : int.tryParse('${target ?? ''}') ?? local.targetAmount,
        debtDirection: direction,
        counterparty: note is String && note.trim().isNotEmpty
            ? note.trim()
            : local.counterparty,
        occurredAt: local.occurredAt,
        fromBrand: from is String && from.trim().isNotEmpty
            ? from.trim()
            : local.fromBrand,
        toBrand: to is String && to.trim().isNotEmpty
            ? to.trim()
            : local.toBrand,
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
    final AiDraft? draft = _draft;
    final String? debt = _debtDirection ?? draft?.debtDirection;
    // Créance / dette : soit un règlement (mouvement de trésorerie sur le
    // compte choisi), soit une nouvelle ligne suivie hors solde.
    if (debt != null) {
      if (_settleMode) {
        await _saveSettlement(amount, debt);
      } else {
        await _saveDebt(amount, debt, draft?.counterparty);
      }
      return;
    }
    if (_accountId == null) {
      setState(() => _message = 'Aucun compte disponible.');
      return;
    }
    if (draft?.isSavings ?? false) {
      await _saveSavings(amount);
      return;
    }
    if (_kind == TransactionKind.transfer) {
      await _saveTransfer(amount);
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
      // Le contexte de la feuille est désactivé dès `pop()` : on garde le
      // navigateur et le messager avant, sinon l'assertion « descendant » de
      // Flutter tombe à la fermeture de l'assistant.
      final NavigatorState navigator = Navigator.of(context);
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      navigator.pop();
      HapticFeedback.lightImpact();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Proposition confirmée et enregistrée.'),
            duration: Duration(seconds: 3),
          ),
        );
    } catch (_) {
      if (mounted) setState(() => _message = 'Enregistrement impossible.');
    }
  }

  /// Premier compte différent du compte source, pour préremplir un transfert.
  String? _firstOtherAccountId() {
    for (final Account account in _loaded) {
      if (account.id != _accountId) return account.id;
    }
    return null;
  }

  /// Retrouve un compte par support (« Flooz ») ou par nom (« Liquide »).
  String? _matchAccount(String hint) {
    final String needle = hint.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final Account account in _loaded) {
      if (account.brand.label.toLowerCase() == needle ||
          account.brand.name.toLowerCase() == needle ||
          account.name.toLowerCase() == needle) {
        return account.id;
      }
    }
    for (final Account account in _loaded) {
      if (account.brand.name.toLowerCase().contains(needle) ||
          account.name.toLowerCase().contains(needle)) {
        return account.id;
      }
    }
    return null;
  }

  /// Transfert entre deux comptes : deux écritures symétriques, comme la
  /// saisie rapide, pour que les soldes et le total restent justes.
  Future<void> _saveTransfer(int amount) async {
    final String? from = _accountId;
    final String? to = _toAccountId;
    if (from == null || to == null || from == to) {
      setState(() {
        _message = 'Choisissez deux comptes différents pour le transfert.';
      });
      return;
    }
    final DateTime now = DateTime.now();
    final int stamp = now.microsecondsSinceEpoch;
    final String? note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final DateTime when = _draft?.occurredAt ?? now;
    try {
      await widget.store.saveTransaction(
        TransactionRecord(
          id: 'ai-$stamp-out',
          accountId: from,
          amount: -amount,
          kind: TransactionKind.transfer,
          note: note,
          occurredAt: when,
          createdAt: now,
          transferAccountId: to,
        ),
      );
      await widget.store.saveTransaction(
        TransactionRecord(
          id: 'ai-$stamp-in',
          accountId: to,
          amount: amount,
          kind: TransactionKind.transfer,
          note: note,
          occurredAt: when,
          createdAt: now,
          transferAccountId: from,
        ),
      );
      widget.revision.bump();
      if (!mounted) return;
      final NavigatorState navigator = Navigator.of(context);
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      navigator.pop();
      HapticFeedback.lightImpact();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Transfert enregistré : le total des comptes ne change pas.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
    } catch (error, stack) {
      debugPrint('AKIBA : transfert impossible (${error.runtimeType}).');
      debugPrintStack(stackTrace: stack, maxFrames: 6);
      if (mounted) setState(() => _message = 'Transfert impossible.');
    }
  }

  /// Règlement d'une créance (« on me doit ») ou d'une dette (« je dois »).
  ///
  /// L'argent bouge réellement sur le compte choisi : une créance encaissée
  /// augmente le solde disponible, une dette payée le diminue. Le reste dû est
  /// mis à jour dans la même écriture.
  Future<void> _saveSettlement(int amount, String direction) async {
    final Debt? debt = _selectedDebt;
    if (debt == null) {
      setState(() {
        _message =
            'Aucune ${direction == 'owedToMe' ? 'créance' : 'dette'} ouverte '
            'sélectionnée. Enregistrez-la d’abord, puis revenez la régler.';
      });
      return;
    }
    final String? accountId = _accountId;
    if (accountId == null) {
      setState(() => _message = 'Choisissez le compte concerné.');
      return;
    }
    final bool received = direction == 'owedToMe';
    try {
      await widget.store.settleDebt(debt, amount: amount, accountId: accountId);
      widget.revision.bump();
      if (!mounted) return;
      final NavigatorState navigator = Navigator.of(context);
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      navigator.pop();
      HapticFeedback.lightImpact();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              received
                  ? 'Créance encaissée : le montant a été ajouté au compte '
                        'choisi.'
                  : 'Dette payée : le montant a été retiré du compte choisi.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
    } on StateError catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Règlement impossible.');
    }
  }

  Future<void> _saveDebt(
    int amount,
    String direction,
    String? extracted,
  ) async {
    final DateTime now = DateTime.now();
    // Contact : le nom extrait de la phrase, sinon ce qui a été saisi dans le
    // champ (nettoyé des chiffres). Une phrase entière ne devient jamais un
    // nom : on retombe sur « Contact », que l'utilisateur peut corriger.
    final String typed = _note.text
        .replaceAll(RegExp(r"[\d\s.,;:!?()'’]+"), ' ')
        .trim();
    final bool typedLooksLikeName =
        typed.isNotEmpty && typed.split(RegExp(r'\s+')).length <= 3;
    final String counterparty =
        (extracted != null && extracted.trim().isNotEmpty)
        ? extracted.trim()
        : (typedLooksLikeName ? typed : 'Contact');
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
      final NavigatorState navigator = Navigator.of(context);
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              direction == 'owedToMe'
                  ? 'Créance enregistrée : elle reste hors du solde disponible '
                        'jusqu’à l’encaissement.'
                  : 'Dette enregistrée : elle reste hors du solde disponible '
                        'jusqu’au paiement.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
    } catch (_) {
      if (mounted) setState(() => _message = 'Enregistrement impossible.');
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
      // La fête s'affiche sur le navigateur, pas sur le contexte de la feuille
      // qui vient d'être retirée de l'arbre.
      final NavigatorState navigator = Navigator.of(context);
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      final String local = SavingsMessages(
        language: widget.settings.language,
      ).next(SavingsMessageKind.encouragement, potName: pots.first.name);
      final Future<String?>? ai = widget.settings.aiRemoteEnabled
          ? SavingsCoach()
                .enrich(
                  settings: widget.settings,
                  kind: SavingsMessageKind.encouragement,
                  localMessage: local,
                  potName: pots.first.name,
                )
                .then((SavingsCoachResult r) => r.fromAi ? r.message : null)
          : null;
      navigator.pop();
      await showSavingsCelebration(
        navigator.context,
        potName: pots.first.name,
        message: local,
        aiMessage: ai,
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Versement d’épargne enregistré : le solde disponible ne baisse '
              'pas. $local',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
    } catch (_) {
      if (mounted) setState(() => _message = 'Enregistrement impossible.');
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
        // Dictée terminée : l'analyse part toute seule, sans bouton
        // « Analyser » à cliquer. L'utilisateur relit puis confirme.
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          unawaited(_analyse());
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final bool wide = MediaQuery.sizeOf(context).width >= 720;

    // Un modèle distant ou un ancien brouillon peut proposer une catégorie qui
    // n'existe pas dans la liste courante : on retombe sur la première pour ne
    // jamais déclencher l'assertion « exactly one item with DropdownButton ».
    final List<String> categories = _kind == TransactionKind.income
        ? _incomeCategories
        : _expenseCategories;
    final String safeCategory = categories.contains(_category)
        ? _category
        : categories.first;
    final List<Account> accountItems = <Account>[];
    final Set<String> seenAccounts = <String>{};
    for (final Account account in _loaded) {
      if (seenAccounts.add(account.id)) accountItems.add(account);
    }

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
                                'Une opération ou une question',
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
                    if (_answer != null) ...<Widget>[
                      const SizedBox(height: AkibaSpacing.lg),
                      Container(
                        padding: const EdgeInsets.all(AkibaSpacing.lg),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(AkibaRadii.card),
                          border: Border.all(color: c.terracotta, width: 1.2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Icon(
                                  Icons.lightbulb_outline_rounded,
                                  size: 18,
                                  color: c.terracotta,
                                ),
                                const SizedBox(width: AkibaSpacing.sm),
                                Expanded(
                                  child: Text(
                                    'Conseil · $_engineNote',
                                    style: AkibaTypography.label.copyWith(
                                      color: c.textMuted,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Effacer',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      setState(() => _answer = null),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            _AnswerText(text: _answer!, colors: c),
                            const SizedBox(height: AkibaSpacing.sm),
                            Text(
                              'Aucune écriture : dictez l’opération pour la '
                              'confirmer.',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_draft != null) ...<Widget>[
                      const SizedBox(height: AkibaSpacing.xl),
                      if (_draft!.isSavingsGoal)
                        _savingsGoalCard(c)
                      else
                        Container(
                          padding: const EdgeInsets.all(AkibaSpacing.lg),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(
                              AkibaRadii.card,
                            ),
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
                              if (_debtDirection != null) ...<Widget>[
                                Container(
                                  padding: const EdgeInsets.all(
                                    AkibaSpacing.md,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.iconTile,
                                    borderRadius: BorderRadius.circular(
                                      AkibaRadii.field,
                                    ),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Icon(
                                        _debtDirection == 'owedToMe'
                                            ? Icons.call_received_rounded
                                            : Icons.call_made_rounded,
                                        size: 18,
                                        color: c.terracotta,
                                      ),
                                      const SizedBox(width: AkibaSpacing.sm),
                                      Expanded(
                                        child: Text(
                                          _settleMode
                                              ? (_debtDirection == 'owedToMe'
                                                    ? 'Règlement · '
                                                          'l’encaissement entre '
                                                          'sur le compte choisi '
                                                          'et augmente le solde '
                                                          'disponible.'
                                                    : 'Règlement · le '
                                                          'paiement sort du '
                                                          'compte choisi et '
                                                          'diminue le solde '
                                                          'disponible.')
                                              : (_debtDirection == 'owedToMe'
                                                    ? 'Créance · on me doit. '
                                                          'Tant qu’elle n’est '
                                                          'pas encaissée, elle '
                                                          'reste hors du solde '
                                                          'disponible.'
                                                    : 'Dette · je dois. Tant '
                                                          'qu’elle n’est pas '
                                                          'payée, elle reste '
                                                          'hors du solde '
                                                          'disponible.'),
                                          style: AkibaTypography.legend
                                              .copyWith(
                                                color: c.textMuted,
                                                height: 1.4,
                                              ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => setState(() {
                                          _debtDirection = null;
                                          _settleMode = false;
                                          _debtId = null;
                                          _kind = TransactionKind.expense;
                                        }),
                                        child: const Text('Changer'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AkibaSpacing.xs),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _toggleSettle,
                                    icon: Icon(
                                      _settleMode
                                          ? Icons.close_rounded
                                          : Icons.task_alt_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      _settleMode
                                          ? 'Annuler le règlement'
                                          : (_debtDirection == 'owedToMe'
                                                ? 'Cette créance a été encaissée'
                                                : 'Cette dette a été payée'),
                                    ),
                                  ),
                                ),
                                if (_settleMode) ...<Widget>[
                                  if (_matchingDebts.isEmpty)
                                    Text(
                                      'Aucune ${_debtDirection == 'owedToMe' ? 'créance' : 'dette'} '
                                      'ouverte pour l’instant : enregistrez-la '
                                      'd’abord sans règlement.',
                                      style: AkibaTypography.legend.copyWith(
                                        color: c.warning,
                                      ),
                                    )
                                  else
                                    DropdownButtonFormField<String>(
                                      initialValue: _selectedDebt?.id,
                                      decoration: _field(c, 'Ligne à régler'),
                                      items: <DropdownMenuItem<String>>[
                                        for (final Debt item in _matchingDebts)
                                          DropdownMenuItem<String>(
                                            value: item.id,
                                            child: Text(
                                              '${item.counterparty} · '
                                              '${AkibaMoney.format(item.remaining, masked: widget.masked)}',
                                            ),
                                          ),
                                      ],
                                      onChanged: (String? value) {
                                        if (value == null) return;
                                        for (final Debt item
                                            in _matchingDebts) {
                                          if (item.id != value) continue;
                                          setState(() {
                                            _debtId = item.id;
                                            _amount.text = '${item.remaining}';
                                            _note.text = item.counterparty;
                                          });
                                        }
                                      },
                                    ),
                                ],
                              ],
                              if (_debtDirection == null)
                                SegmentedControl(
                                  segments: const <String>[
                                    'Sortie',
                                    'Entrée',
                                    'Transfert',
                                    'Tiers',
                                  ],
                                  selectedIndex: _neutral
                                      ? 3
                                      : _kind == TransactionKind.transfer
                                      ? 2
                                      : (_kind == TransactionKind.income
                                            ? 1
                                            : 0),
                                  onChanged: (int index) => setState(() {
                                    _debtDirection = null;
                                    _neutral = index == 3;
                                    if (index == 2) {
                                      _kind = TransactionKind.transfer;
                                      _toAccountId ??= _firstOtherAccountId();
                                    } else {
                                      _kind = index == 1
                                          ? TransactionKind.income
                                          : TransactionKind.expense;
                                      _category =
                                          _kind == TransactionKind.income
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
                                    accountItems.any(
                                      (Account a) => a.id == _accountId,
                                    )
                                    ? _accountId
                                    : null,
                                decoration: _field(
                                  c,
                                  _debtDirection != null
                                      ? (_debtDirection == 'owedToMe'
                                            ? 'Compte qui reçoit'
                                            : 'Compte qui paie')
                                      : 'Compte',
                                ),
                                items: <DropdownMenuItem<String>>[
                                  for (final Account account in accountItems)
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
                              if (_kind == TransactionKind.transfer &&
                                  !_neutral &&
                                  _debtDirection == null) ...<Widget>[
                                const SizedBox(height: AkibaSpacing.md),
                                DropdownButtonFormField<String>(
                                  initialValue:
                                      accountItems.any(
                                        (Account a) => a.id == _toAccountId,
                                      )
                                      ? _toAccountId
                                      : null,
                                  decoration: _field(c, 'Compte destination'),
                                  items: <DropdownMenuItem<String>>[
                                    for (final Account account in accountItems)
                                      if (account.id != _accountId)
                                        DropdownMenuItem<String>(
                                          value: account.id,
                                          child: Text(
                                            '${account.name} · '
                                            '${account.brand.label}',
                                          ),
                                        ),
                                  ],
                                  onChanged: (String? value) =>
                                      setState(() => _toAccountId = value),
                                ),
                              ],
                              const SizedBox(height: AkibaSpacing.md),
                              if (!_neutral &&
                                  _debtDirection == null &&
                                  _kind != TransactionKind.transfer)
                                DropdownButtonFormField<String>(
                                  initialValue: safeCategory,
                                  decoration: _field(c, 'Catégorie'),
                                  items: <DropdownMenuItem<String>>[
                                    for (final String category in categories)
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
                                decoration: _field(
                                  c,
                                  _debtDirection != null
                                      ? 'Contact (ex. Koffi)'
                                      : 'Note',
                                ),
                              ),
                              const SizedBox(height: AkibaSpacing.md),
                              Text(
                                _debtDirection != null
                                    ? _settleMode
                                          ? (_debtDirection == 'owedToMe'
                                                ? 'Le montant encaissé sera '
                                                      'ajouté au compte choisi ; '
                                                      'le reste dû diminue '
                                                      'd’autant.'
                                                : 'Le montant payé sera retiré '
                                                      'du compte choisi ; le '
                                                      'reste dû diminue d’autant.')
                                          : 'La créance / dette sera '
                                                'enregistrée sans mouvement de '
                                                'trésorerie : elle reste hors '
                                                'du solde disponible, du budget '
                                                'et des statistiques.'
                                    : _neutral
                                    ? 'Argent de tiers : la ligne sera isolée du '
                                          'solde disponible, du budget et des '
                                          'statistiques.'
                                    : _kind == TransactionKind.transfer
                                    ? 'Transfert : deux écritures symétriques, '
                                          'le total des comptes ne change pas.'
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
                                label: Text(
                                  _settleMode
                                      ? 'Confirmer le règlement · '
                                            '${_previewAmount()}'
                                      : 'Confirmer · ${_previewAmount()}',
                                ),
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

  /// Carte dédiée à un objectif d'épargne récurrent.
  ///
  /// Elle remplace la carte d'opération : le montant dicté est un versement
  /// **quotidien**, pas une dépense. La date d'atteinte est calculée en direct
  /// dès que le prix de l'objectif est connu.
  Widget _savingsGoalCard(AkibaColors c) {
    final DateTime start = _draft?.occurredAt ?? DateTime.now();
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
              Icon(Icons.savings_outlined, size: 18, color: c.terracotta),
              const SizedBox(width: AkibaSpacing.sm),
              Expanded(
                child: Text(
                  'Objectif d’épargne · à confirmer',
                  style: AkibaTypography.label.copyWith(
                    color: c.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  '$_engineNote · ${_confidenceLabel(_draft!.confidence)}',
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
          Container(
            padding: const EdgeInsets.all(AkibaSpacing.md),
            decoration: BoxDecoration(
              color: c.iconTile,
              borderRadius: BorderRadius.circular(AkibaRadii.field),
            ),
            child: Text(
              'AKIBA crée le coffre et calcule quand l’objectif sera atteint. '
              'Aucun versement n’est débité avant votre confirmation.',
              style: AkibaTypography.legend.copyWith(
                color: c.textMuted,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: AkibaSpacing.md),
          TextField(
            controller: _goalName,
            textCapitalization: TextCapitalization.sentences,
            decoration: _field(c, 'Nom du coffre (ex. Moniteur)'),
          ),
          const SizedBox(height: AkibaSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _goalTarget,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  decoration: _field(c, 'Prix de l’objectif'),
                ),
              ),
              const SizedBox(width: AkibaSpacing.sm),
              Text(
                'FCFA',
                style: AkibaTypography.legend.copyWith(color: c.textMuted),
              ),
            ],
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
                  decoration: _field(c, 'Chaque jour'),
                ),
              ),
              const SizedBox(width: AkibaSpacing.sm),
              Text(
                'FCFA / jour',
                style: AkibaTypography.legend.copyWith(color: c.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AkibaSpacing.md),
          Text(
            'Premier versement : ${AkibaDate.short(start)}.',
            style: AkibaTypography.legend.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: AkibaSpacing.xs),
          ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[_goalTarget, _amount]),
            builder: (BuildContext context, Widget? _) {
              final int target = int.tryParse(_goalTarget.text) ?? 0;
              final int daily = int.tryParse(_amount.text) ?? 0;
              final DateTime? date = SavingsProjection.dateForDailyPlan(
                target: target,
                daily: daily,
                firstDeposit: start,
              );
              if (target <= 0) {
                return Text(
                  'Indiquez le prix de l’objectif pour connaître la date '
                  'd’atteinte.',
                  style: AkibaTypography.legend.copyWith(
                    color: c.warning,
                    height: 1.4,
                  ),
                );
              }
              if (date == null) {
                return Text(
                  'Avec ce rythme, l’objectif n’est pas atteignable dans les '
                  'dix ans. Augmentez le versement quotidien.',
                  style: AkibaTypography.legend.copyWith(
                    color: c.warning,
                    height: 1.4,
                  ),
                );
              }
              final int deposits = SavingsProjection.depositsFor(
                target: target,
                daily: daily,
              );
              return Text(
                '$deposits versements de '
                '${AkibaMoney.format(daily, masked: widget.masked)} · objectif '
                'atteint le ${AkibaDate.short(date)}.',
                style: AkibaTypography.legend.copyWith(
                  color: c.success,
                  height: 1.4,
                ),
              );
            },
          ),
          const SizedBox(height: AkibaSpacing.lg),
          FilledButton.icon(
            onPressed: _saveSavingsGoal,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Créer l’épargne'),
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
    );
  }

  /// Crée le coffre de l'objectif et mémorise le rythme quotidien.
  ///
  /// Aucune transaction n'est écrite : le premier versement reste un geste
  /// volontaire de la personne, comme partout dans AKIBA.
  Future<void> _saveSavingsGoal() async {
    final int daily = int.tryParse(_amount.text) ?? 0;
    final int target = int.tryParse(_goalTarget.text) ?? 0;
    if (daily <= 0 || daily > 999999999) {
      setState(
        () => _message = 'Versement quotidien invalide (1 à 999 999 999 FCFA).',
      );
      return;
    }
    if (target < 0 || target > 999999999) {
      setState(() => _message = 'Prix de l’objectif invalide.');
      return;
    }
    final String name = _goalName.text.trim().isEmpty
        ? 'Objectif'
        : _goalName.text.trim();
    final DateTime start = _draft?.occurredAt ?? DateTime.now();
    final DateTime? date = SavingsProjection.dateForDailyPlan(
      target: target,
      daily: daily,
      firstDeposit: start,
    );
    final DateTime now = DateTime.now();
    try {
      final SavingsPot pot = SavingsPot(
        id: 'pot-${now.microsecondsSinceEpoch}',
        name: name,
        kind: SavingsKind.goal,
        targetAmount: target,
        targetDate: date,
        createdAt: now,
      );
      await widget.store.saveSavingsPot(pot);
      // Le rythme est mémorisé pour le rappel et le suivi, sans être un
      // mouvement d'argent : aucun solde ne change ici.
      await widget.settings.set(
        'savings_plan_${pot.id}',
        jsonEncode(<String, Object?>{
          'daily': daily,
          'first': start.toUtc().toIso8601String(),
          'target': target,
        }),
      );
      widget.revision.bump();
      if (!mounted) return;
      final NavigatorState navigator = Navigator.of(context);
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      navigator.pop();
      HapticFeedback.lightImpact();
      final String horizon = date == null
          ? ' Ajoutez le prix de l’objectif pour connaître la date d’atteinte.'
          : ' Objectif atteint le ${AkibaDate.short(date)}.';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Épargne « $name » créée : '
              '${AkibaMoney.format(daily, masked: widget.masked)} par jour.$horizon',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Création du coffre impossible.');
      }
    }
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

/// Rendu lisible d'un conseil : paragraphes aérés, puces alignées et montants
/// mis en avant. Jamais de JSON ni de Markdown affiché tel quel.
class _AnswerText extends StatelessWidget {
  const _AnswerText({required this.text, required this.colors});

  final String text;
  final AkibaColors colors;

  @override
  Widget build(BuildContext context) {
    final List<AiTextBlock> blocks = AiText.blocks(text);
    if (blocks.isEmpty) return const SizedBox.shrink();
    final TextStyle style = AkibaTypography.body.copyWith(
      color: colors.textPrimary,
      height: 1.45,
    );
    Widget selectable(String value) => SelectableText.rich(
      TextSpan(children: _highlight(value, style, colors.terracotta)),
      style: style,
    );
    final List<Widget> children = <Widget>[];
    for (int index = 0; index < blocks.length; index++) {
      final AiTextBlock block = blocks[index];
      if (index > 0) {
        children.add(
          SizedBox(height: block.isBullet ? AkibaSpacing.xs : AkibaSpacing.sm),
        );
      }
      if (!block.isBullet) {
        children.add(selectable(block.text));
        continue;
      }
      children.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 7, right: AkibaSpacing.sm),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.terracotta,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(child: selectable(block.text)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// Met en gras les montants en FCFA pour une lecture immédiate.
List<InlineSpan> _highlight(String text, TextStyle style, Color accent) {
  final RegExp amounts = RegExp(r'\d[\d\u00A0 ]{0,15}\s?(?:FCFA|CFA)\b');
  final List<InlineSpan> spans = <InlineSpan>[];
  int cursor = 0;
  for (final RegExpMatch match in amounts.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    spans.add(
      TextSpan(
        text: match.group(0),
        style: style.copyWith(color: accent, fontWeight: FontWeight.w700),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans.isEmpty ? <InlineSpan>[TextSpan(text: text)] : spans;
}
