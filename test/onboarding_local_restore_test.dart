import 'package:akiba/core/backup/home_lab_setup.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/core/theme/akiba_theme.dart';
import 'package:akiba/data/simulation_store.dart';
import 'package:akiba/features/onboarding/local_restore_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SimulationAkibaStore store;
  late AkibaSettings settings;

  Future<void> mount(
    WidgetTester tester, {
    required LocalBackupFetcher fetcher,
    required LocalBackupRestorer restorer,
    required InMemoryLabTokenStore tokens,
    required VoidCallback onRestored,
  }) async {
    store = SimulationAkibaStore();
    settings = AkibaSettings(store);
    await settings.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: AkibaTheme.forId(AkibaThemeId.blanc),
        home: LocalRestorePage(
          store: store,
          settings: settings,
          onRestored: onRestored,
          tokens: tokens,
          fetcher: fetcher,
          restorer: restorer,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('normalise l’adresse puis restaure automatiquement', (
    WidgetTester tester,
  ) async {
    final InMemoryLabTokenStore tokens = InMemoryLabTokenStore();
    String? fetchedUrl;
    String? fetchedToken;
    int restored = 0;
    final Map<String, dynamic> envelope = <String, dynamic>{
      'createdAt': '2026-11-20T10:00:00Z',
      'counts': <String, int>{'transactions': 12, 'accounts': 4},
    };

    await mount(
      tester,
      tokens: tokens,
      onRestored: () => restored++,
      fetcher: (String url, String token) async {
        fetchedUrl = url;
        fetchedToken = token;
        return envelope;
      },
      restorer: (Map<String, dynamic> _) async => <String, int>{
        'transactions': 12,
        'accounts': 4,
      },
    );

    await tester.enterText(find.byType(TextField).at(0), '192.168.1.20:8080');
    await tester.enterText(find.byType(TextField).at(1), 'jeton-test');
    final Finder action = find.text('Rechercher et restaurer');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    // L'adresse est normalisée avant l'appel réseau, sans intervention.
    expect(fetchedUrl, 'http://192.168.1.20:8080');
    expect(fetchedToken, 'jeton-test');
    expect(await tokens.read(), 'jeton-test');
    expect(settings.raw('lab_url'), 'http://192.168.1.20:8080');
    expect(settings.flag('lab_auto_backup'), isTrue);
    expect(settings.flag('restore_done'), isTrue);
    expect(restored, 1);
    expect(find.textContaining('Restauration terminée'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
  });

  testWidgets('un serveur sans sauvegarde laisse continuer sans restaurer', (
    WidgetTester tester,
  ) async {
    final InMemoryLabTokenStore tokens = InMemoryLabTokenStore();
    int restored = 0;

    await mount(
      tester,
      tokens: tokens,
      onRestored: () => restored++,
      fetcher: (String url, String token) async => null,
      restorer: (Map<String, dynamic> _) async => <String, int>{},
    );

    await tester.enterText(find.byType(TextField).at(0), '10.0.0.12');
    await tester.enterText(find.byType(TextField).at(1), 'jeton-test');
    final Finder action = find.text('Rechercher et restaurer');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.textContaining('Aucune sauvegarde AKIBA'), findsOneWidget);
    expect(find.text('Continuer sans restaurer'), findsOneWidget);
    expect(restored, 0);
    expect(settings.flag('restore_done'), isFalse);
  });

  testWidgets('une adresse invalide est refusée avant tout appel', (
    WidgetTester tester,
  ) async {
    final InMemoryLabTokenStore tokens = InMemoryLabTokenStore();
    int fetches = 0;

    await mount(
      tester,
      tokens: tokens,
      onRestored: () {},
      fetcher: (String url, String token) async {
        fetches++;
        return null;
      },
      restorer: (Map<String, dynamic> _) async => <String, int>{},
    );

    await tester.enterText(find.byType(TextField).at(0), 'ftp://serveur');
    await tester.enterText(find.byType(TextField).at(1), 'jeton-test');
    final Finder action = find.text('Rechercher et restaurer');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(fetches, 0);
    expect(find.textContaining('Adresse invalide'), findsOneWidget);
  });
}
