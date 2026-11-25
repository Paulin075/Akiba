import '../state/akiba_settings.dart';
import 'ai_model_catalog.dart';

/// Fournisseur de modèle de langage utilisable par l'assistant.
///
/// Gemini garde son API native ; les trois autres parlent le même dialecte
/// `/v1/chat/completions` (DeepSeek, OpenRouter, Home Lab / Ollama). Le choix
/// est explicite, enregistré dans les réglages et jamais deviné.
enum AiProvider {
  gemini(
    id: 'gemini',
    label: 'Gemini',
    detail: 'Clé Google AI Studio',
    defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    defaultModel: 'gemini-2.0-flash',
    requiresKey: true,
  ),
  deepseek(
    id: 'deepseek',
    label: 'DeepSeek',
    detail: 'Clé api.deepseek.com',
    defaultBaseUrl: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
    requiresKey: true,
  ),
  openrouter(
    id: 'openrouter',
    label: 'OpenRouter',
    detail: 'Clé openrouter.ai',
    defaultBaseUrl: 'https://openrouter.ai/api/v1',
    defaultModel: 'openai/gpt-4o-mini',
    requiresKey: true,
  ),
  ollama(
    id: 'ollama',
    label: 'Home Lab / Ollama',
    detail: 'Instance locale ou LAN, jeton facultatif',
    defaultBaseUrl: 'http://127.0.0.1:11434/v1',
    defaultModel: 'llama3.1',
    requiresKey: false,
  );

  const AiProvider({
    required this.id,
    required this.label,
    required this.detail,
    required this.defaultBaseUrl,
    required this.defaultModel,
    required this.requiresKey,
  });

  /// Identifiant enregistré dans les réglages.
  final String id;

  /// Nom affiché.
  final String label;

  /// Précision courte affichée sous le nom.
  final String detail;

  /// Point d'entrée par défaut, utilisé si aucun n'est saisi.
  final String defaultBaseUrl;

  /// Modèle proposé par défaut.
  final String defaultModel;

  /// Faux uniquement pour une instance locale sans jeton.
  final bool requiresKey;

  /// Gemini a son propre protocole ; les autres sont compatibles OpenAI.
  bool get isGemini => this == AiProvider.gemini;

  static AiProvider fromStorage(String? raw) {
    for (final AiProvider provider in AiProvider.values) {
      if (provider.id == raw) return provider;
    }
    return AiProvider.gemini;
  }
}

/// Lecture et écriture des réglages propres à chaque fournisseur.
///
/// Une URL et un modèle par fournisseur : changer de fournisseur ne réécrit
/// jamais la configuration des autres, et une URL invalide retombe sur la
/// valeur par défaut (un appel réseau ne part jamais vers un hôte vide).
class AiProviderSettings {
  const AiProviderSettings(this.settings);

  final AkibaSettings settings;

  AiProvider get provider =>
      AiProvider.fromStorage(settings.raw('ai_provider'));

  /// Adresse réellement utilisée : saisie valide, sinon valeur par défaut.
  String baseUrl(AiProvider provider) {
    final String typed = settings.raw('ai_base_url_${provider.id}').trim();
    if (typed.isEmpty) return provider.defaultBaseUrl;
    return normalizeBaseUrl(typed) ?? provider.defaultBaseUrl;
  }

  /// L'URL saisie est-elle exploitable ? (`null` = vide ou invalide)
  static String? normalizeBaseUrl(String raw) {
    final String value = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (value.isEmpty) return null;
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    return value;
  }

  /// Vraie si une URL personnalisée a été saisie mais est inutilisable.
  bool hasInvalidBaseUrl(AiProvider provider) {
    final String typed = settings.raw('ai_base_url_${provider.id}').trim();
    return typed.isNotEmpty && normalizeBaseUrl(typed) == null;
  }

  String model(AiProvider provider) {
    final String typed = settings.raw('ai_model_${provider.id}').trim();
    return typed.isEmpty ? provider.defaultModel : typed;
  }

  /// Modèles proposés à la cascade, dans l'ordre.
  ///
  /// Gemini garde son catalogue et sa priorité ; les API compatibles OpenAI
  /// n'ont besoin que du modèle choisi.
  List<AiModel> models(AiProvider provider) {
    if (!provider.isGemini) {
      final String id = model(provider);
      return <AiModel>[AiModel(id: id, label: id)];
    }
    return AiModelCatalog.selected(
      AiModelCatalog.decode(settings.raw('ai_models_cache')),
      settings.raw('ai_model_priority'),
    );
  }

  Future<void> setProvider(AiProvider provider) =>
      settings.set('ai_provider', provider.id);

  Future<void> setBaseUrl(AiProvider provider, String raw) =>
      settings.set('ai_base_url_${provider.id}', normalizeBaseUrl(raw) ?? '');

  Future<void> setModel(AiProvider provider, String raw) =>
      settings.set('ai_model_${provider.id}', raw.trim());
}
