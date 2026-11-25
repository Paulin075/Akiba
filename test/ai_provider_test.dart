import 'package:flutter_test/flutter_test.dart';

import 'package:akiba/core/ai/ai_client.dart';
import 'package:akiba/core/ai/ai_key_vault.dart';
import 'package:akiba/core/ai/ai_model_catalog.dart';
import 'package:akiba/core/ai/ai_provider.dart';
import 'package:akiba/core/ai/ai_remote.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/data/akiba_store.dart';

void main() {
  group('Fournisseurs IA', () {
    test('le fournisseur est lu, avec repli Gemini', () {
      expect(AiProvider.fromStorage('deepseek'), AiProvider.deepseek);
      expect(AiProvider.fromStorage('openrouter'), AiProvider.openrouter);
      expect(AiProvider.fromStorage('ollama'), AiProvider.ollama);
      expect(AiProvider.fromStorage(null), AiProvider.gemini);
      expect(AiProvider.fromStorage('inconnu'), AiProvider.gemini);

      expect(AiProvider.gemini.requiresKey, isTrue);
      expect(AiProvider.deepseek.requiresKey, isTrue);
      expect(AiProvider.ollama.requiresKey, isFalse);
      expect(AiProvider.deepseek.defaultBaseUrl, 'https://api.deepseek.com/v1');
      expect(AiProvider.deepseek.defaultModel, 'deepseek-chat');
      expect(
        AiProvider.openrouter.defaultBaseUrl,
        'https://openrouter.ai/api/v1',
      );
      expect(AiProvider.ollama.defaultBaseUrl, 'http://127.0.0.1:11434/v1');
    });

    test('les adresses saisies sont normalisées et validées', () {
      expect(
        AiProviderSettings.normalizeBaseUrl(' https://exemple.test/v1/// '),
        'https://exemple.test/v1',
      );
      expect(
        AiProviderSettings.normalizeBaseUrl('http://127.0.0.1:11434/v1'),
        'http://127.0.0.1:11434/v1',
      );
      expect(AiProviderSettings.normalizeBaseUrl(''), isNull);
      expect(AiProviderSettings.normalizeBaseUrl('pas une url'), isNull);
      expect(AiProviderSettings.normalizeBaseUrl('ftp://exemple.test'), isNull);
    });

    test('chaque fournisseur construit sa propre requête', () {
      final AiProviderCall gemini = buildAiProviderCall(
        provider: AiProvider.gemini,
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        apiKey: 'AIza-cle-de-test',
        modelId: 'gemini-2.0-flash',
        prompt: 'Test',
      );
      expect(
        gemini.uri.toString(),
        contains('models/gemini-2.0-flash:generateContent'),
      );
      expect(gemini.uri.queryParameters['key'], 'AIza-cle-de-test');
      expect(gemini.headers.containsKey('Authorization'), isFalse);
      expect(gemini.body, contains('"contents"'));

      for (final AiProvider provider in <AiProvider>[
        AiProvider.deepseek,
        AiProvider.openrouter,
      ]) {
        final AiProviderCall call = buildAiProviderCall(
          provider: provider,
          baseUrl: provider.defaultBaseUrl,
          apiKey: 'secret',
          modelId: provider.defaultModel,
          prompt: 'Bonjour',
        );
        expect(
          call.uri.toString(),
          '${provider.defaultBaseUrl}/chat/completions',
        );
        expect(call.headers['Authorization'], 'Bearer secret');
        expect(call.body, contains('"model":"${provider.defaultModel}"'));
        expect(call.body, contains('Bonjour'));
      }

      final AiProviderCall ollama = buildAiProviderCall(
        provider: AiProvider.ollama,
        baseUrl: 'http://127.0.0.1:11434/v1/',
        modelId: 'llama3.1',
        prompt: 'x',
      );
      expect(
        ollama.uri.toString(),
        'http://127.0.0.1:11434/v1/chat/completions',
      );
      expect(ollama.headers.containsKey('Authorization'), isFalse);
    });

    test('les deux formats de réponse sont lus', () {
      const String gemini =
          '{"candidates":[{"content":{"parts":['
          '{"text":"{\\"amount\\":5000}"}]}}]}';
      expect(extractAiText(AiProvider.gemini, gemini), '{"amount":5000}');

      const String openAi =
          '{"choices":[{"message":{"content":"{\\"amount\\":7000}"}}]}';
      expect(extractAiText(AiProvider.deepseek, openAi), '{"amount":7000}');

      const String parts =
          '{"choices":[{"message":{"content":[{"text":"a"},{"text":"b"}]}}]}';
      expect(extractAiText(AiProvider.openrouter, parts), 'ab');

      expect(
        () => extractAiText(AiProvider.ollama, '{}'),
        throwsFormatException,
      );
    });

    test('les modèles compatibles OpenAI sont lus sans doublon', () {
      const String body =
          '{"data":[{"id":"deepseek-chat"},{"id":"deepseek-chat"},'
          '{"id":"deepseek-reasoner"}]}';
      final List<AiModel> models = AiModelCatalog.parseOpenAiList(body);
      expect(models.map((AiModel m) => m.id), <String>[
        'deepseek-chat',
        'deepseek-reasoner',
      ]);
      expect(AiModelCatalog.parseOpenAiList('pas du json'), isEmpty);
    });
  });

  group('Routage, masquage et repli local', () {
    late AkibaSettings settings;

    setUp(() {
      settings = AkibaSettings(const EmptyAkibaStore());
    });

    test('le masquage bloque tout appel distant', () async {
      await settings.setFlag('ai_remote_enabled', true);
      final AiRemoteResolution result = await resolveAiRemote(
        settings,
        masked: true,
      );

      expect(result.setup, isNull);
      expect(result.block, AiRemoteBlock.masked);
      expect(result.note, contains('masquage'));
    });

    test('sans appels distants, l’analyse locale reprend', () async {
      final AiRemoteResolution result = await resolveAiRemote(
        settings,
        masked: false,
      );

      expect(result.setup, isNull);
      expect(result.block, AiRemoteBlock.disabled);
    });

    test('Home Lab / Ollama fonctionne sans jeton, les autres non', () async {
      await settings.setFlag('ai_remote_enabled', true);
      await settings.set('ai_provider', 'ollama');
      await settings.set('ai_base_url_ollama', 'http://192.168.1.20:11434/v1');

      final AiRemoteResolution local = await resolveAiRemote(
        settings,
        masked: false,
      );
      expect(local.setup, isNotNull);
      expect(local.setup!.provider, AiProvider.ollama);
      expect(local.setup!.apiKey, isNull);
      expect(local.setup!.models.single.id, 'llama3.1');

      await settings.set('ai_provider', 'deepseek');
      final AiRemoteResolution withoutKey = await resolveAiRemote(
        settings,
        masked: false,
      );
      expect(withoutKey.setup, isNull);
      expect(withoutKey.block, AiRemoteBlock.unconfigured);
    });

    test('une adresse invalide ne part pas et retombe sur le défaut', () async {
      await settings.setFlag('ai_remote_enabled', true);
      await settings.set('ai_provider', 'ollama');
      await settings.set('ai_base_url_ollama', 'n’importe quoi');

      final AiRemoteResolution result = await resolveAiRemote(
        settings,
        masked: false,
      );
      expect(result.setup, isNull);
      expect(result.block, AiRemoteBlock.unconfigured);

      final AiProviderSettings config = AiProviderSettings(settings);
      expect(config.hasInvalidBaseUrl(AiProvider.ollama), isTrue);
      expect(
        config.baseUrl(AiProvider.ollama),
        AiProvider.ollama.defaultBaseUrl,
      );
    });

    test('les clés sont rangées par fournisseur', () {
      expect(AiKeyVault.sealedKeyFor(AiProvider.gemini), 'ai_api_key_sealed');
      expect(
        AiKeyVault.sealedKeyFor(AiProvider.deepseek),
        'ai_api_key_sealed_deepseek',
      );
      expect(
        AiKeyVault.sealedKeyFor(AiProvider.openrouter),
        'ai_api_key_sealed_openrouter',
      );
      expect(
        AiKeyVault.sealedKeyFor(AiProvider.ollama),
        'ai_api_key_sealed_ollama',
      );

      expect(
        AiKeyVault(settings, provider: AiProvider.deepseek).isConfigured,
        isFalse,
      );
      expect(
        AiKeyVault(settings, provider: AiProvider.gemini).isConfigured,
        isFalse,
      );
    });
  });
}
