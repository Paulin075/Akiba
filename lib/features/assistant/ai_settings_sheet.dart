import 'package:flutter/material.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_key_vault.dart';
import '../../core/ai/ai_model_catalog.dart';
import '../../core/ai/ai_quota.dart';
import '../../core/format/akiba_date.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';

/// Réglages du module IA : clé API chiffrée, liste des modèles, priorité et
/// bascule distante.
///
/// La clé n'est jamais réaffichée : le champ est vide, masqué, et un
/// remplacement remplace l'ancienne valeur sans la montrer.
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

  late final AiKeyVault _vault = AiKeyVault(widget.settings);
  late List<AiModel> _catalog = AiModelCatalog.decode(
    widget.settings.raw('ai_models_cache'),
  );
  late List<String> _selected = _initialSelection();

  bool _busy = false;
  bool _obscure = true;
  String? _message;
  bool _error = false;

  AkibaSettings get _s => widget.settings;

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

  AiQuota get _quota => AiQuota(_s);

  @override
  void dispose() {
    _keyField.dispose();
    super.dispose();
  }

  void _say(String message, {bool error = false}) {
    setState(() {
      _message = message;
      _error = error;
    });
  }

  Future<void> _persistSelection() async {
    await _s.set('ai_model_priority', _selected.join(','));
  }

  Future<bool> _refreshModels({String? key}) async {
    final String? apiKey = key ?? await _vault.read();
    if (apiKey == null) {
      _say('Enregistrez d’abord une clé API.', error: true);
      return false;
    }
    setState(() => _busy = true);
    final AiModelsFetch fetch = await fetchAiModels(apiKey);
    if (!mounted) return false;
    if (!fetch.ok) {
      setState(() => _busy = false);
      _say(fetch.note, error: true);
      return false;
    }
    await _s.set('ai_models_cache', AiModelCatalog.encode(fetch.models));
    await _s.set('ai_models_cached_at', DateTime.now().toIso8601String());
    final Set<String> known = fetch.models.map((AiModel m) => m.id).toSet();
    final List<String> kept = _selected
        .where((String id) => known.contains(id))
        .toList();
    for (final AiModel model in fetch.models) {
      if (!kept.contains(model.id)) kept.add(model.id);
    }
    setState(() {
      _catalog = fetch.models;
      _selected = kept;
      _busy = false;
    });
    await _persistSelection();
    _say(fetch.note);
    return true;
  }

  Future<void> _saveKey() async {
    final String raw = _keyField.text;
    final String? problem = AiKeyVault.validate(raw);
    if (problem != null) {
      _say(problem, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _vault.save(raw);
      _keyField.clear();
      if (!mounted) return;
      setState(() => _busy = false);
      _say('Clé enregistrée, chiffrée localement. Vérification en cours…');
      await _refreshModels(key: raw.trim());
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
                                'Clé, modèles et priorité',
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

                    // -------------------------------------------- Clé API
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
                                      ? 'Clé enregistrée · '
                                            '${AiKeyVault.maskedLabel}'
                                      : 'Aucune clé enregistrée',
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
                                  : 'Coller la clé fournie par le service',
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
                          Wrap(
                            spacing: AkibaSpacing.sm,
                            runSpacing: AkibaSpacing.sm,
                            children: <Widget>[
                              FilledButton.icon(
                                onPressed: _busy ? null : _saveKey,
                                icon: const Icon(Icons.lock_rounded, size: 18),
                                label: Text(
                                  configured
                                      ? 'Remplacer et tester'
                                      : 'Enregistrer et tester',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy || !configured
                                    ? null
                                    : () async {
                                        setState(() => _busy = true);
                                        final bool ok = await _refreshModels();
                                        if (!mounted) return;
                                        setState(() => _busy = false);
                                        if (ok) {
                                          _say(
                                            'Clé valide, modèles récupérés.',
                                          );
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

                    // --------------------------------------------- Modèles
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
                            'Essais dans cet ordre, un seul appel par modèle. '
                            'Un modèle en échec deux fois passe en veille '
                            '10 minutes.',
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
                              onPressed: _busy || !configured
                                  ? null
                                  : () async {
                                      setState(() => _busy = true);
                                      await _refreshModels();
                                      if (mounted) {
                                        setState(() => _busy = false);
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

                    // --------------------------------------------- Délais
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
