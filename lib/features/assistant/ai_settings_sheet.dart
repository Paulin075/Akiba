import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_key_vault.dart';
import '../../core/ai/ai_model_catalog.dart';
import '../../core/ai/ai_provider.dart';
import '../../core/ai/ai_quota.dart';
import '../../core/format/akiba_date.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import 'ai_test_panel.dart';

/// Réglages du module IA : fournisseur, adresse, clé chiffrée, modèles,
/// priorité et quota.
///
/// La clé de chaque fournisseur est chiffrée séparément (AES-256-GCM) et n'est
/// jamais réaffichée : le champ reste vide. Home Lab / Ollama accepte un jeton
/// vide ; les autres fournisseurs en exigent un.
Future<void> openAiSettings(
  BuildContext context, {
  required AkibaSettings settings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => _AiSettingsSheet(settings: settings),
  );
}

class _AiSettingsSheet extends StatefulWidget {
  const _AiSettingsSheet({required this.settings});

  final AkibaSettings settings;

  @override
  State<_AiSettingsSheet> createState() => _AiSettingsSheetState();
}

class _AiSettingsSheetState extends State<_AiSettingsSheet> {
  final TextEditingController _keyField = TextEditingController();
  final TextEditingController _urlField = TextEditingController();

  late final AiProviderSettings _cfg = AiProviderSettings(widget.settings);
  late AiProvider _provider = _cfg.provider;
  late List<AiModel> _catalog = _cachedModels(_provider);
  late String _selectedModel = _cfg.model(_provider);

  bool _busy = false;
  bool _testing = false;
  String? _message;
  String? _testReply;
  String? _testError;
  bool _error = false;

  AkibaSettings get _s => widget.settings;

  AiKeyVault get _vault => AiKeyVault(_s, provider: _provider);

  AiQuota get _quota => AiQuota(_s);

  @override
  void initState() {
    super.initState();
    final Set<AiProvider> configured = <AiProvider>{
      for (final AiProvider provider in AiProvider.values)
        if (AiKeyVault(_s, provider: provider).isConfigured) provider,
    };
    // Keep an explicit selection when it has a key. If exactly one provider
    // has a saved key, select it automatically; never guess among several.
    _provider = selectAiProviderOnOpen(
      current: _provider,
      providersWithKey: configured,
    );
    _urlField.text = _s.raw('ai_base_url_${_provider.id}');
    _selectedModel = _cfg.model(_provider);
    _catalog = _cachedModels(_provider);
    // Une clé déjà enregistrée suffit à remplir la liste déroulante, sans
    // demander à la personne de cliquer sur « Tester ».
    if (_vault.isConfigured) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadModels(silent: true));
      });
    }
  }

  /// Liste connue pour ce fournisseur, avec repli propre (modèle configuré et
  /// modèle par défaut) quand aucun catalogue n'a encore été chargé.
  List<AiModel> _cachedModels(AiProvider provider) {
    final String raw = _s.raw('ai_models_cache_${provider.id}').trim();
    final List<AiModel> models;
    if (raw.isNotEmpty) {
      models = AiModelCatalog.decode(raw);
    } else if (provider.isGemini) {
      // Cache historique de Gemini, conservé pour les installations existantes.
      models = AiModelCatalog.decode(_s.raw('ai_models_cache'));
    } else {
      models = <AiModel>[];
    }
    return _withModels(models, <String>[
      _cfg.model(provider),
      if (!provider.isGemini) provider.defaultModel,
    ]);
  }

  /// Garantit que chaque identifiant utile a une entrée sélectionnable.
  static List<AiModel> _withModels(List<AiModel> models, Iterable<String> ids) {
    final List<AiModel> result = List<AiModel>.of(models);
    for (final String id in ids) {
      final String trimmed = id.trim();
      if (trimmed.isEmpty) continue;
      if (result.any((AiModel model) => model.id == trimmed)) continue;
      result.add(AiModel(id: trimmed, label: trimmed));
    }
    return result;
  }

  @override
  void dispose() {
    _keyField.dispose();
    _urlField.dispose();
    super.dispose();
  }

  void _say(String message, {bool error = false}) {
    // Une réponse réseau peut arriver après la fermeture de la feuille : sans
    // ce garde-fou, `setState` s'exécute sur un élément désactivé et lève
    // l'assertion de cycle de vie au moment de quitter les paramètres IA.
    if (!mounted) return;
    setState(() {
      _message = message;
      _error = error;
    });
  }

  /// Enregistre le modèle choisi ; pour Gemini, il passe aussi en tête de la
  /// cascade de secours.
  Future<void> _persistModel() async {
    final String model = _selectedModel.trim();
    if (model.isEmpty) return;
    await _cfg.setModel(_provider, model);
    if (_provider.isGemini) {
      final List<String> order = <String>[
        model,
        for (final AiModel item in _catalog)
          if (item.id != model) item.id,
      ];
      await _s.set('ai_model_priority', order.join(','));
    }
  }

  Future<void> _selectProvider(AiProvider provider) async {
    if (provider == _provider) return;
    await _cfg.setProvider(provider);
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _urlField.text = _s.raw('ai_base_url_${provider.id}');
      _selectedModel = _cfg.model(provider);
      _catalog = _cachedModels(provider);
      _message = null;
      _testReply = null;
      _testError = null;
      _testing = false;
    });
    if (_vault.isConfigured) unawaited(_loadModels(silent: true));
  }

  /// Enregistre l'adresse et le modèle du fournisseur courant.
  Future<bool> _persistEndpoint() async {
    final String url = _urlField.text.trim();
    if (url.isNotEmpty && AiProviderSettings.normalizeBaseUrl(url) == null) {
      _say(
        'Adresse invalide : attendu http(s)://hôte (ex. '
        '${_provider.defaultBaseUrl}).',
        error: true,
      );
      return false;
    }
    await _cfg.setBaseUrl(_provider, url);
    return true;
  }

  /// Erreur du test : catégorie sûre, affichée sous le bouton « Tester ».
  void _testFailure(String message) {
    if (!mounted) return;
    setState(() {
      _testing = false;
      _busy = false;
      _testReply = null;
      _testError = message;
      _message = null;
    });
  }

  /// Remplit la liste déroulante avec **tous** les modèles accessibles avec
  /// la clé fournie, puis mémorise le catalogue de ce fournisseur.
  Future<bool> _loadModels({String? key, bool silent = false}) async {
    final String? apiKey = key ?? await _vault.read();
    if (_provider.requiresKey && (apiKey == null || apiKey.isEmpty)) {
      if (!silent) {
        _testFailure('Enregistrez d’abord une clé ${_provider.label}.');
      }
      return false;
    }
    if (_cfg.hasInvalidBaseUrl(_provider)) {
      if (!silent) {
        _testFailure('Adresse invalide : corrigez-la avant de tester.');
      }
      return false;
    }
    if (!mounted) return false;
    if (!silent) {
      setState(() {
        _busy = true;
        _testing = true;
        _testReply = null;
        _testError = null;
      });
    }
    final AiModelsFetch fetch = await fetchAiModels(
      provider: _provider,
      baseUrl: _cfg.baseUrl(_provider),
      apiKey: apiKey,
    );
    if (!mounted) return false;
    if (!fetch.ok) {
      if (!silent) _testFailure(fetch.note);
      return false;
    }

    final List<AiModel> models = _withModels(fetch.models, <String>[
      _selectedModel,
    ]);
    final String stamp = DateTime.now().toIso8601String();
    await _s.set(
      'ai_models_cache_${_provider.id}',
      AiModelCatalog.encode(fetch.models),
    );
    await _s.set('ai_models_cached_at_${_provider.id}', stamp);
    if (_provider.isGemini) {
      // Ancien cache Gemini, toujours lu par la cascade de l'assistant.
      await _s.set('ai_models_cache', AiModelCatalog.encode(fetch.models));
      await _s.set('ai_models_cached_at', stamp);
    }
    if (!mounted) return false;
    setState(() {
      _catalog = models;
      if (_selectedModel.trim().isEmpty) _selectedModel = models.first.id;
      if (!silent) {
        _busy = false;
        _testing = false;
        _testError = null;
        _message = null;
      }
    });
    await _persistModel();
    return true;
  }

  /// Actualise la liste puis teste le modèle **choisi dans la liste déroulante**.
  ///
  /// Un modèle retiré par le fournisseur (404) ou momentanément surchargé
  /// (5xx) ne doit pas condamner le test : les deux modèles suivants du
  /// catalogue sont essayés, et celui qui répond devient le modèle retenu.
  /// Une clé refusée, un délai ou un souci réseau, eux, dépendent de la clé ou
  /// du réseau : inutile d'insister sur un autre modèle.
  Future<bool> _refreshModels({String? key}) async {
    final bool loaded = await _loadModels(key: key);
    if (!loaded) return false;
    final String? apiKey = key ?? await _vault.read();
    final List<String> candidates = <String>[
      _selectedModel,
      for (final AiModel model in _catalog)
        if (model.id != _selectedModel) model.id,
    ].where((String id) => id.trim().isNotEmpty).toList();
    final List<String> tried = <String>[];
    AiTestException? lastFailure;
    for (final String modelId in candidates.take(3)) {
      tried.add(modelId);
      try {
        final String reply = await fetchAiTestReply(
          provider: _provider,
          baseUrl: _cfg.baseUrl(_provider),
          apiKey: apiKey,
          modelId: modelId,
        );
        if (!mounted) return false;
        if (modelId != _selectedModel) {
          // Le modèle choisi ne répond pas : celui qui vient de répondre est
          // retenu et enregistré pour les appels suivants.
          setState(() => _selectedModel = modelId);
          await _persistModel();
          if (!mounted) return false;
        }
        setState(() {
          _testReply = reply;
          _testError = null;
          _testing = false;
          _busy = false;
          _message = null;
        });
        return true;
      } on AiTestException catch (error) {
        lastFailure = error;
        if (error.kind != AiFailureKind.model &&
            error.kind != AiFailureKind.server) {
          break;
        }
      }
    }
    final String base = lastFailure?.message ?? AiFailureKind.model.hint;
    final String models = tried.join(', ');
    _testFailure(
      '$base Modèle${tried.length > 1 ? 's' : ''} testé'
      '${tried.length > 1 ? 's' : ''} : $models.',
    );
    return false;
  }

  Future<void> _save() async {
    final String raw = _keyField.text.trim();
    if (raw.isNotEmpty) {
      final String? problem = AiKeyVault.validate(raw);
      if (problem != null) {
        _say(problem, error: true);
        return;
      }
    } else if (_provider.requiresKey && !_vault.isConfigured) {
      _say('Collez la clé fournie par ${_provider.label}.', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      if (raw.isNotEmpty) {
        await _vault.save(raw);
        // La clé est active tout de suite : fournisseur mémorisé et appels
        // distants autorisés, sans redémarrage ni manipulation cachée.
        await activateAiProviderWithKey(_s, _provider);
      }
      final bool endpointOk = await _persistEndpoint();
      if (!mounted) return;
      setState(() => _busy = false);
      if (!endpointOk) return;
      await _persistModel();
      _keyField.clear();
      _say(
        raw.isNotEmpty
            ? 'Clé enregistrée, chiffrée localement. Vérification en cours…'
            : 'Réglages enregistrés. Vérification en cours…',
      );
      await _refreshModels(key: raw.isNotEmpty ? raw : null);
    } on AiKeyException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _say(error.message, error: true);
    }
  }

  Future<void> _clearKey() async {
    setState(() => _busy = true);
    await _vault.clear();
    await _s.setFlag('ai_remote_enabled', false);
    if (!mounted) return;
    setState(() => _busy = false);
    _say('Clé effacée. L’assistant repasse en analyse locale.');
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final bool configured = _vault.isConfigured;
    final DateTime? updated = _vault.updatedAt;
    final bool keyOptional = !_provider.requiresKey;
    final String cachedStamp =
        _s.raw('ai_models_cached_at_${_provider.id}').trim().isEmpty
        ? _s.raw('ai_models_cached_at')
        : _s.raw('ai_models_cached_at_${_provider.id}');
    final DateTime? cachedAt = DateTime.tryParse(cachedStamp);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
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
                                'MODULE IA',
                                style: AkibaTypography.label.copyWith(
                                  color: c.textMuted,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              Text(
                                'Fournisseur, clé et modèles',
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

                    // --------------------------------------- Fournisseur
                    _card(
                      c,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'Fournisseur',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AkibaSpacing.xs),
                          Text(
                            'Un seul fournisseur actif. Chaque clé et chaque '
                            'adresse restent enregistrées séparément.',
                            style: AkibaTypography.legend.copyWith(
                              color: c.textMuted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: AkibaSpacing.sm),
                          RadioGroup<AiProvider>(
                            groupValue: _provider,
                            onChanged: (AiProvider? value) {
                              if (value != null) _selectProvider(value);
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                for (final AiProvider provider
                                    in AiProvider.values)
                                  _providerRow(c, provider),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AkibaSpacing.lg),

                    // ------------------------------------- Clé / adresse
                    _card(
                      c,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                configured
                                    ? Icons.key_rounded
                                    : Icons.key_off_rounded,
                                size: 18,
                                color: configured ? c.success : c.textMuted,
                              ),
                              const SizedBox(width: AkibaSpacing.sm),
                              Expanded(
                                child: Text(
                                  configured
                                      ? 'Clé ${_provider.label} enregistrée · '
                                            '${AiKeyVault.maskedLabel}'
                                      : keyOptional
                                      ? 'Jeton facultatif pour ${_provider.label}'
                                      : 'Aucune clé ${_provider.label}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (configured && updated != null) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              'Dernier remplacement : '
                              '${AkibaDate.short(updated)} · '
                              'chiffrée en AES-256-GCM',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(height: AkibaSpacing.md),
                          TextField(
                            controller: _keyField,
                            // La clé n'est jamais affichée, même à la demande :
                            // elle ne sert qu'à être collée puis enregistrée.
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              hintText: configured
                                  ? 'Coller une nouvelle clé pour remplacer'
                                  : keyOptional
                                  ? 'Jeton si l’instance en exige un'
                                  : 'Coller la clé ${_provider.label}',
                              filled: true,
                              fillColor: c.surfaceElevated,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AkibaRadii.field,
                                ),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: AkibaSpacing.sm),
                          // Aucun endpoint n'est demandé : l'adresse par défaut
                          // du fournisseur est résolue en arrière-plan. Le
                          // réglage avancé reste facultatif et replié.
                          Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              key: const Key('ai-advanced-settings'),
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: EdgeInsets.zero,
                              title: Text(
                                'Réglages avancés (facultatif)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: c.textMuted,
                                ),
                              ),
                              subtitle: Text(
                                'Adresse choisie automatiquement : '
                                '${_provider.defaultBaseUrl}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AkibaTypography.legend.copyWith(
                                  color: c.textMuted,
                                  fontSize: 10.5,
                                ),
                              ),
                              children: <Widget>[
                                TextField(
                                  controller: _urlField,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  keyboardType: TextInputType.url,
                                  decoration: InputDecoration(
                                    labelText: 'Adresse (endpoint)',
                                    hintText: _provider.defaultBaseUrl,
                                    helperText:
                                        'Vide = ${_provider.defaultBaseUrl}',
                                    helperMaxLines: 2,
                                    filled: true,
                                    fillColor: c.surfaceElevated,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        AkibaRadii.field,
                                      ),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AkibaSpacing.sm),
                                Text(
                                  'Le modèle se choisit dans la liste '
                                  'déroulante ci-dessous, une fois la clé '
                                  'enregistrée.',
                                  style: AkibaTypography.legend.copyWith(
                                    color: c.textMuted,
                                    fontSize: 11,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AkibaSpacing.sm),
                          Wrap(
                            spacing: AkibaSpacing.sm,
                            runSpacing: AkibaSpacing.sm,
                            children: <Widget>[
                              FilledButton.icon(
                                onPressed: _busy ? null : _save,
                                icon: const Icon(Icons.lock_rounded, size: 18),
                                label: Text(
                                  configured
                                      ? 'Enregistrer et tester'
                                      : 'Configurer et tester',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    _busy || (!configured && !keyOptional)
                                    ? null
                                    : () async {
                                        setState(() => _busy = true);
                                        final bool ok = await _refreshModels();
                                        if (!mounted) return;
                                        setState(() => _busy = false);
                                        if (ok) {
                                          _say('Connexion vérifiée.');
                                        }
                                      },
                                icon: const Icon(
                                  Icons.wifi_tethering_rounded,
                                  size: 18,
                                ),
                                label: const Text('Tester'),
                              ),
                              if (configured)
                                TextButton(
                                  onPressed: _busy ? null : _clearKey,
                                  child: const Text('Effacer la clé'),
                                ),
                            ],
                          ),
                          // La réponse (ou l'erreur catégorisée) s'affiche
                          // dans cette même carte, juste sous « Tester ».
                          AiTestPanel(
                            loading: _testing,
                            reply: _testReply,
                            error: _testError,
                          ),
                          const SizedBox(height: AkibaSpacing.xs),
                          Text(
                            'La clé est chiffrée avec une clé maîtresse '
                            'conservée par le coffre du système (Keystore / '
                            'DPAPI). Elle n’est jamais affichée, ni exportée '
                            'dans une sauvegarde.',
                            style: AkibaTypography.legend.copyWith(
                              color: c.textMuted,
                              height: 1.4,
                            ),
                          ),
                          const Divider(height: AkibaSpacing.xl),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: _s.flag('ai_remote_enabled'),
                            onChanged: (bool value) async {
                              await _s.setFlag('ai_remote_enabled', value);
                              if (mounted) setState(() {});
                            },
                            title: Text(
                              'Utiliser le modèle distant',
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              'Désactivé : analyse locale uniquement. En mode '
                              'masqué, aucun appel distant n’est fait.',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AkibaSpacing.lg),

                    // -------------------------------------------- Modèle
                    _card(
                      c,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  'Modèle utilisé',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                              if (cachedAt != null)
                                Text(
                                  'liste du ${AkibaDate.short(cachedAt)}',
                                  style: AkibaTypography.legend.copyWith(
                                    color: c.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AkibaSpacing.xs),
                          Text(
                            'Tous les modèles accessibles avec cette clé. La '
                            'liste se remplit automatiquement dès que la clé '
                            'est enregistrée ; le modèle choisi est testé et '
                            'utilisé par l’assistant.',
                            style: AkibaTypography.legend.copyWith(
                              color: c.textMuted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: AkibaSpacing.md),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AkibaSpacing.md,
                            ),
                            decoration: BoxDecoration(
                              color: c.surfaceElevated,
                              borderRadius: BorderRadius.circular(
                                AkibaRadii.field,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                key: ValueKey<String>(
                                  'ai-model-${_provider.id}-'
                                  '${_selectedModel.isEmpty ? '-' : _selectedModel}',
                                ),
                                isExpanded: true,
                                value:
                                    _catalog.any(
                                      (AiModel model) =>
                                          model.id == _selectedModel,
                                    )
                                    ? _selectedModel
                                    : null,
                                hint: Text(
                                  'Choisir un modèle',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.textMuted,
                                  ),
                                ),
                                items: <DropdownMenuItem<String>>[
                                  for (final AiModel model in _catalog)
                                    DropdownMenuItem<String>(
                                      value: model.id,
                                      child: Text(
                                        model.label == model.id
                                            ? model.id
                                            : '${model.label} · ${model.id}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                    ),
                                ],
                                onChanged: _busy
                                    ? null
                                    : (String? value) async {
                                        if (value == null ||
                                            value == _selectedModel) {
                                          return;
                                        }
                                        setState(() => _selectedModel = value);
                                        await _persistModel();
                                      },
                              ),
                            ),
                          ),
                          const SizedBox(height: AkibaSpacing.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _busy || (!configured && !keyOptional)
                                  ? null
                                  : () async {
                                      setState(() => _busy = true);
                                      final bool ok = await _loadModels();
                                      if (!mounted) return;
                                      setState(() => _busy = false);
                                      if (ok) {
                                        _say('Liste des modèles actualisée.');
                                      }
                                    },
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Actualiser la liste'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AkibaSpacing.lg),

                    // -------------------------------------------- Délais
                    _card(
                      c,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'Délais et bascule',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AkibaSpacing.sm),
                          Wrap(
                            spacing: AkibaSpacing.sm,
                            runSpacing: AkibaSpacing.sm,
                            children: <Widget>[
                              for (final AiTask task in AiTask.values)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AkibaSpacing.sm,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.iconTile,
                                    borderRadius: BorderRadius.circular(
                                      AkibaRadii.pill,
                                    ),
                                  ),
                                  child: Text(
                                    '${task.label} · ${task.seconds} s',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: c.terracottaDeep,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AkibaSpacing.sm),
                          Text(
                            'Délai dépassé, quota (429) ou erreur 5xx : le '
                            'modèle suivant prend le relais, sans bloquer '
                            'l’application. Au-delà de 3 essais, l’analyse '
                            'locale reprend la main. Aucune écriture n’est '
                            'faite sans votre confirmation.',
                            style: AkibaTypography.legend.copyWith(
                              color: c.textMuted,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: AkibaSpacing.sm),
                          Text(
                            'Quota du jour : ${_quota.label}. Remis à zéro '
                            'chaque jour ; une analyse distante compte une '
                            'unité. Quota atteint : analyse locale, sans '
                            'erreur ni blocage.',
                            style: AkibaTypography.legend.copyWith(
                              color: c.textMuted,
                              height: 1.45,
                            ),
                          ),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  'Analyses distantes par jour',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                '${_s.integer('ai_quota_per_day', fallback: 20)}',
                                style: AkibaTypography.money(
                                  14,
                                  color: c.textPrimary,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Moins de quota',
                                onPressed: () async {
                                  final int value = _s.integer(
                                    'ai_quota_per_day',
                                    fallback: 20,
                                  );
                                  if (value <= 1) return;
                                  await _s.set(
                                    'ai_quota_per_day',
                                    '${value - 1}',
                                  );
                                  if (mounted) setState(() {});
                                },
                                icon: const Icon(Icons.remove_rounded),
                              ),
                              IconButton(
                                tooltip: 'Plus de quota',
                                onPressed: () async {
                                  final int value = _s.integer(
                                    'ai_quota_per_day',
                                    fallback: 20,
                                  );
                                  if (value >= 100) return;
                                  await _s.set(
                                    'ai_quota_per_day',
                                    '${value + 1}',
                                  );
                                  if (mounted) setState(() {});
                                },
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  'Plafond d’essais',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                '${_s.integer('ai_max_attempts', fallback: 3)}',
                                style: AkibaTypography.money(
                                  14,
                                  color: c.textPrimary,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Moins d’essais',
                                onPressed: () async {
                                  final int value = _s.integer(
                                    'ai_max_attempts',
                                    fallback: 3,
                                  );
                                  if (value <= 1) return;
                                  await _s.set(
                                    'ai_max_attempts',
                                    '${value - 1}',
                                  );
                                  if (mounted) setState(() {});
                                },
                                icon: const Icon(Icons.remove_rounded),
                              ),
                              IconButton(
                                tooltip: 'Plus d’essais',
                                onPressed: () async {
                                  final int value = _s.integer(
                                    'ai_max_attempts',
                                    fallback: 3,
                                  );
                                  if (value >= 5) return;
                                  await _s.set(
                                    'ai_max_attempts',
                                    '${value + 1}',
                                  );
                                  if (mounted) setState(() {});
                                },
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_message != null) ...<Widget>[
                      const SizedBox(height: AkibaSpacing.md),
                      Text(
                        _message!,
                        style: AkibaTypography.legend.copyWith(
                          color: _error ? c.danger : c.success,
                        ),
                      ),
                    ],
                    if (_busy) ...<Widget>[
                      const SizedBox(height: AkibaSpacing.md),
                      const LinearProgressIndicator(minHeight: 2),
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

  Widget _providerRow(AkibaColors c, AiProvider provider) {
    final bool selected = provider == _provider;
    final bool keyReady = AiKeyVault(_s, provider: provider).isConfigured;
    return InkWell(
      onTap: () => _selectProvider(provider),
      borderRadius: BorderRadius.circular(AkibaRadii.field),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AkibaSpacing.xs),
        child: Row(
          children: <Widget>[
            Radio<AiProvider>(value: provider),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    provider.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? c.textPrimary : c.textMuted,
                    ),
                  ),
                  Text(
                    provider.requiresKey
                        ? '${provider.detail} · '
                              '${keyReady ? 'clé enregistrée' : 'clé requise'}'
                        : provider.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AkibaTypography.legend.copyWith(
                      color: c.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: c.success),
          ],
        ),
      ),
    );
  }

  Widget _card(AkibaColors c, {required Widget child}) => Container(
    padding: const EdgeInsets.all(AkibaSpacing.lg),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(AkibaRadii.card),
      boxShadow: c.cardShadow,
    ),
    // Material transparent : les ListTile (interrupteur, réglages avancés)
    // peignent leur fond et leur encre sur ce plan, au-dessus du DecoratedBox.
    child: Material(type: MaterialType.transparency, child: child),
  );
}
