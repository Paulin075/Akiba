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
  final TextEditingController _modelField = TextEditingController();

  late final AiProviderSettings _cfg = AiProviderSettings(widget.settings);
  late AiProvider _provider = _cfg.provider;
  late List<AiModel> _catalog = AiModelCatalog.decode(
    widget.settings.raw('ai_models_cache'),
  );
  late List<String> _selected = _initialSelection();

  bool _busy = false;
  bool _obscure = true;
  String? _message;
  bool _error = false;

  AkibaSettings get _s => widget.settings;

  AiKeyVault get _vault => AiKeyVault(_s, provider: _provider);

  AiQuota get _quota => AiQuota(_s);

  @override
  void initState() {
    super.initState();
    _urlField.text = _s.raw('ai_base_url_${_provider.id}');
    _modelField.text = _s.raw('ai_model_${_provider.id}');
  }

  List<String> _initialSelection() {
    final List<String> configured = _ids(_s.raw('ai_model_priority'));
    if (configured.isNotEmpty) return configured;
    return _catalog.map((AiModel m) => m.id).toList();
  }

  static List<String> _ids(String raw) => raw
      .split(',')
      .map((String id) => id.trim())
      .where((String id) => id.isNotEmpty)
      .toList();

  @override
  void dispose() {
    _keyField.dispose();
    _urlField.dispose();
    _modelField.dispose();
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

  Future<void> _persistSelection() async {
    await _s.set('ai_model_priority', _selected.join(','));
  }

  Future<void> _selectProvider(AiProvider provider) async {
    if (provider == _provider) return;
    await _cfg.setProvider(provider);
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _urlField.text = _s.raw('ai_base_url_${provider.id}');
      _modelField.text = _s.raw('ai_model_${provider.id}');
      _message = null;
    });
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
    if (!_provider.isGemini) {
      await _cfg.setModel(_provider, _modelField.text);
    }
    return true;
  }

  Future<bool> _refreshModels({String? key}) async {
    final String? apiKey = key ?? await _vault.read();
    if (_provider.requiresKey && (apiKey == null || apiKey.isEmpty)) {
      _say('Enregistrez d’abord une clé ${_provider.label}.', error: true);
      return false;
    }
    if (_cfg.hasInvalidBaseUrl(_provider)) {
      _say('Adresse invalide : corrigez-la avant de tester.', error: true);
      return false;
    }
    setState(() => _busy = true);
    final AiModelsFetch fetch = await fetchAiModels(
      provider: _provider,
      baseUrl: _cfg.baseUrl(_provider),
      apiKey: apiKey,
    );
    if (!mounted) return false;
    if (!fetch.ok) {
      setState(() => _busy = false);
      _say(fetch.note, error: true);
      return false;
    }

    List<String> kept = _selected;
    if (_provider.isGemini) {
      // Le catalogue et la priorité ne concernent que Gemini : les API
      // compatibles OpenAI n'ont qu'un modèle choisi.
      final Set<String> known = fetch.models.map((AiModel m) => m.id).toSet();
      kept = _selected.where((String id) => known.contains(id)).toList();
      for (final AiModel model in fetch.models) {
        if (!kept.contains(model.id)) kept.add(model.id);
      }
      await _s.set('ai_models_cache', AiModelCatalog.encode(fetch.models));
      await _s.set('ai_models_cached_at', DateTime.now().toIso8601String());
    }
    if (!mounted) return false;
    setState(() {
      _catalog = fetch.models;
      _selected = kept;
      _busy = false;
    });
    if (_provider.isGemini) await _persistSelection();
    _say(fetch.note);
    return true;
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
      if (raw.isNotEmpty) await _vault.save(raw);
      final bool endpointOk = await _persistEndpoint();
      if (!mounted) return;
      setState(() => _busy = false);
      if (!endpointOk) return;
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

  Future<void> _toggleModel(String id) async {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
    await _persistSelection();
  }

  Future<void> _move(int index, int delta) async {
    final int target = index + delta;
    if (target < 0 || target >= _selected.length) return;
    setState(() {
      final String id = _selected.removeAt(index);
      _selected.insert(target, id);
    });
    await _persistSelection();
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final bool configured = _vault.isConfigured;
    final DateTime? updated = _vault.updatedAt;
    final bool keyOptional = !_provider.requiresKey;
    final DateTime? cachedAt = DateTime.tryParse(_s.raw('ai_models_cached_at'));

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
                            obscureText: _obscure,
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
                              suffixIcon: IconButton(
                                tooltip: _obscure
                                    ? 'Afficher la saisie'
                                    : 'Masquer la saisie',
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  size: 18,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AkibaRadii.field,
                                ),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: AkibaSpacing.sm),
                          TextField(
                            controller: _urlField,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: 'Adresse (endpoint)',
                              hintText: _provider.defaultBaseUrl,
                              helperText: 'Vide = ${_provider.defaultBaseUrl}',
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
                          if (!_provider.isGemini) ...<Widget>[
                            const SizedBox(height: AkibaSpacing.sm),
                            TextField(
                              controller: _modelField,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                labelText: 'Modèle',
                                hintText: _provider.defaultModel,
                                helperText:
                                    'Vide = ${_provider.defaultModel}. '
                                    'Un seul modèle est essayé.',
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
                          ],
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

                    // ------------------------------ Modèles (Gemini seul)
                    if (_provider.isGemini) ...<Widget>[
                      _card(
                        c,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    'Modèles et priorité',
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
                              'Essais dans cet ordre, un seul appel par '
                              'modèle. Un modèle en échec deux fois passe en '
                              'veille 10 minutes.',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.md),
                            for (final AiModel model in _catalog)
                              _modelRow(c, model),
                            const SizedBox(height: AkibaSpacing.sm),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed:
                                    _busy || (!configured && !keyOptional)
                                    ? null
                                    : () async {
                                        setState(() => _busy = true);
                                        await _refreshModels();
                                        if (mounted) {
                                          setState(() => _busy = false);
                                        }
                                      },
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: const Text('Actualiser la liste'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AkibaSpacing.lg),
                    ],

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

  Widget _modelRow(AkibaColors c, AiModel model) {
    final int index = _selected.indexOf(model.id);
    final bool enabled = index >= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AkibaSpacing.xs),
      child: Row(
        children: <Widget>[
          Checkbox(value: enabled, onChanged: (_) => _toggleModel(model.id)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  model.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: enabled ? c.textPrimary : c.textMuted,
                  ),
                ),
                Text(
                  enabled ? '${index + 1} · ${model.id}' : model.id,
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
          IconButton(
            tooltip: 'Monter',
            onPressed: enabled && index > 0 ? () => _move(index, -1) : null,
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          ),
          IconButton(
            tooltip: 'Descendre',
            onPressed: enabled && index < _selected.length - 1
                ? () => _move(index, 1)
                : null,
            icon: const Icon(Icons.arrow_downward_rounded, size: 18),
          ),
        ],
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
    child: child,
  );
}
