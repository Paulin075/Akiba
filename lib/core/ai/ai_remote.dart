import '../state/akiba_settings.dart';
import 'ai_client.dart';
import 'ai_key_vault.dart';
import 'ai_model_catalog.dart';
import 'ai_provider.dart';

/// Pourquoi aucun appel distant n'est possible : l'interface le dit en une
/// ligne, sans jargon et sans jamais proposer d'écrire en base.
enum AiRemoteBlock {
  masked('Analyse locale · masquage actif'),
  disabled('Analyse locale'),
  unconfigured('Analyse locale · fournisseur à configurer');

  const AiRemoteBlock(this.note);

  final String note;
}

/// Configuration distante prête à l'emploi : fournisseur, adresse, clé et
/// modèles. La clé n'est conservée que le temps de l'appel.
class AiRemoteSetup {
  const AiRemoteSetup({
    required this.provider,
    required this.baseUrl,
    required this.models,
    this.apiKey,
  });

  final AiProvider provider;
  final String baseUrl;
  final List<AiModel> models;
  final String? apiKey;

  /// Transport du fournisseur : Gemini natif, ou `/chat/completions`.
  AiTransport get transport => provider.isGemini
      ? GeminiTransport(apiKey: apiKey ?? '').call
      : OpenAiCompatibleTransport(
          provider: provider,
          baseUrl: baseUrl,
          apiKey: apiKey,
        ).call;
}

/// Résultat de la résolution : soit une configuration, soit un motif de repli.
class AiRemoteResolution {
  const AiRemoteResolution.ready(this.setup) : block = null;

  const AiRemoteResolution.blocked(AiRemoteBlock this.block) : setup = null;

  final AiRemoteSetup? setup;
  final AiRemoteBlock? block;

  String get note => block?.note ?? 'Analyse locale';
}

/// Décide, sans réseau, si un appel distant est autorisé.
///
/// Règles : masquage actif → rien ne part ; appels distants désactivés → rien ;
/// adresse invalide ou clé absente (sauf Home Lab / Ollama) → rien. Dans tous
/// ces cas l'analyse locale hors ligne prend le relais silencieusement.
Future<AiRemoteResolution> resolveAiRemote(
  AkibaSettings settings, {
  required bool masked,
}) async {
  if (masked) return const AiRemoteResolution.blocked(AiRemoteBlock.masked);
  if (!settings.aiRemoteEnabled) {
    return const AiRemoteResolution.blocked(AiRemoteBlock.disabled);
  }

  final AiProviderSettings config = AiProviderSettings(settings);
  final AiProvider provider = config.provider;
  if (config.hasInvalidBaseUrl(provider)) {
    return const AiRemoteResolution.blocked(AiRemoteBlock.unconfigured);
  }

  final String? apiKey = await AiKeyVault(settings, provider: provider).read();
  if (provider.requiresKey && (apiKey == null || apiKey.isEmpty)) {
    return const AiRemoteResolution.blocked(AiRemoteBlock.unconfigured);
  }

  final List<AiModel> models = config.models(provider);
  if (models.isEmpty) {
    return const AiRemoteResolution.blocked(AiRemoteBlock.unconfigured);
  }

  return AiRemoteResolution.ready(
    AiRemoteSetup(
      provider: provider,
      baseUrl: config.baseUrl(provider),
      models: models,
      apiKey: apiKey,
    ),
  );
}
