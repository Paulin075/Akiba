import 'package:akiba/core/ai/ai_key_vault.dart';
import 'package:akiba/core/ai/ai_model_catalog.dart';
import 'package:akiba/core/ai/ai_provider.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/core/theme/akiba_theme.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:akiba/features/assistant/ai_settings_sheet.dart';
import 'package:akiba/features/assistant/ai_test_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sélection automatique du fournisseur', () {
    test('un seul fournisseur avec clé est sélectionné', () {
      expect(
        selectAiProviderOnOpen(
          current: AiProvider.gemini,
          providersWithKey: <AiProvider>{AiProvider.deepseek},
        ),
        AiProvider.deepseek,
      );
      expect(
        selectAiProviderOnOpen(
          current: AiProvider.ollama,
          providersWithKey: <AiProvider>{AiProvider.openrouter},
        ),
        AiProvider.openrouter,
      );
    });

    test('un choix courant qui a une clé n’est jamais remplacé', () {
      expect(
        selectAiProviderOnOpen(
          current: AiProvider.deepseek,
          providersWithKey: <AiProvider>{
            AiProvider.gemini,
            AiProvider.deepseek,
          },
        ),
        AiProvider.deepseek,
      );
    });

    test('plusieurs clés ou aucune conservent le choix courant', () {
      expect(
        selectAiProviderOnOpen(
          current: AiProvider.gemini,
          providersWithKey: <AiProvider>{
            AiProvider.deepseek,
            AiProvider.openrouter,
          },
        ),
        AiProvider.gemini,
      );
      expect(
        selectAiProviderOnOpen(
          current: AiProvider.openrouter,
          providersWithKey: <AiProvider>{},
        ),
        AiProvider.openrouter,
      );
    });
  });

  test('enregistrer une clé active immédiatement le fournisseur', () async {
    final AkibaSettings settings = AkibaSettings(const EmptyAkibaStore());
    await settings.load();
    expect(settings.aiRemoteEnabled, isFalse);

    await activateAiProviderWithKey(settings, AiProvider.deepseek);

    expect(AiProviderSettings(settings).provider, AiProvider.deepseek);
    expect(settings.aiRemoteEnabled, isTrue);
    // La clé reste rangée par fournisseur et lisible par le coffre.
    expect(
      AiKeyVault(settings, provider: AiProvider.deepseek).isConfigured,
      isFalse,
    );
  });

  group('Panneau de test IA', () {
    Future<void> mount(WidgetTester tester, AiTestPanel panel) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AkibaTheme.light(),
          home: Scaffold(body: panel),
        ),
      );
    }

    testWidgets('affiche la réponse sous le titre, sans URL ni secret', (
      WidgetTester tester,
    ) async {
      await mount(tester, const AiTestPanel(reply: 'AKIBA OK'));
      expect(find.text('Réponse du modèle'), findsOneWidget);
      expect(find.text('AKIBA OK'), findsOneWidget);
      expect(find.textContaining('http'), findsNothing);
    });

    testWidgets('affiche l’état de chargement', (WidgetTester tester) async {
      await mount(tester, const AiTestPanel(loading: true));
      expect(find.text('Test en cours…'), findsOneWidget);
      expect(find.text('Réponse du modèle'), findsOneWidget);
    });

    testWidgets('affiche l’erreur catégorisée', (WidgetTester tester) async {
      await mount(
        tester,
        const AiTestPanel(error: 'Le modèle n’a pas répondu à temps.'),
      );
      expect(find.text('Test de connexion'), findsOneWidget);
      expect(find.textContaining('répondu'), findsOneWidget);
      expect(find.text('Réponse du modèle'), findsNothing);
    });

    testWidgets('reste invisible sans test', (WidgetTester tester) async {
      await mount(tester, const AiTestPanel());
      expect(find.byKey(const Key('ai-test-panel')), findsNothing);
    });
  });

  group('Réglages IA', () {
    testWidgets('ne demande aucun endpoint et garde les avancés repliés', (
      WidgetTester tester,
    ) async {
      final AkibaSettings settings = AkibaSettings(const EmptyAkibaStore());
      await settings.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AkibaTheme.light(),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => openAiSettings(context, settings: settings),
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      // L'endpoint par défaut est résolu en arrière-plan : aucun champ à
      // remplir, aucun blocage si la personne colle seulement sa clé.
      expect(find.text('Adresse (endpoint)'), findsNothing);
      expect(find.text('Réglages avancés (facultatif)'), findsOneWidget);
      expect(
        find.textContaining('Adresse choisie automatiquement'),
        findsOneWidget,
      );
      // Aucune carte de réponse avant le test.
      expect(find.text('Réponse du modèle'), findsNothing);
      expect(find.byKey(const Key('ai-test-panel')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la liste déroulante propose tous les modèles de la clé', (
      WidgetTester tester,
    ) async {
      final AkibaSettings settings = AkibaSettings(const EmptyAkibaStore());
      await settings.load();
      await settings.set('ai_provider', AiProvider.deepseek.id);
      await settings.set(
        'ai_models_cache_deepseek',
        AiModelCatalog.encode(const <AiModel>[
          AiModel(id: 'deepseek-chat', label: 'DeepSeek Chat'),
          AiModel(id: 'deepseek-reasoner', label: 'DeepSeek Reasoner'),
        ]),
      );
      await settings.set('ai_model_deepseek', 'deepseek-reasoner');
      await tester.pumpWidget(
        MaterialApp(
          theme: AkibaTheme.light(),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => openAiSettings(context, settings: settings),
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      expect(find.text('Modèle utilisé'), findsOneWidget);
      final Finder dropdown = find.byType(DropdownButton<String>);
      await tester.ensureVisible(dropdown);
      expect(
        find.text('DeepSeek Reasoner · deepseek-reasoner'),
        findsOneWidget,
      );

      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('DeepSeek Chat · deepseek-chat'), findsWidgets);

      await tester.tap(find.text('DeepSeek Chat · deepseek-chat').last);
      await tester.pumpAndSettle();
      expect(settings.raw('ai_model_deepseek'), 'deepseek-chat');
    });
  });
}
