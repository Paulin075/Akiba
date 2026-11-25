import 'package:akiba/core/state/akiba_data_revision.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/core/state/masked_amounts.dart';
import 'package:akiba/core/theme/akiba_theme.dart';
import 'package:akiba/core/widgets/quick_action_tile.dart';
import 'package:akiba/data/simulation_store.dart';
import 'package:akiba/features/dashboard/dashboard_screen.dart';
import 'package:akiba/features/portfolio/portfolio_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('l’action Épargne de l’accueil ouvre les coffres, sans phase 5', (
    WidgetTester tester,
  ) async {
    final SimulationAkibaStore store = SimulationAkibaStore();
    final AkibaSettings settings = AkibaSettings(store);
    await settings.load();
    final AkibaDataRevision revision = AkibaDataRevision();
    final ValueNotifier<bool> masked = ValueNotifier<bool>(false);
    addTearDown(revision.dispose);
    addTearDown(masked.dispose);

    bool openedSavings = false;
    await tester.pumpWidget(
      AkibaSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: AkibaTheme.light(),
          home: MaskedAmounts(
            notifier: masked,
            child: Scaffold(
              body: DashboardScreen(
                store: store,
                revision: revision,
                themeId: AkibaThemeId.blanc,
                onThemeChanged: (AkibaThemeId _) {},
                onOpenSavings: () => openedSavings = true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder savingsTile = find.byWidgetPredicate(
      (Widget widget) =>
          widget is QuickActionTile && widget.icon == Icons.savings_rounded,
    );
    expect(savingsTile, findsOneWidget);
    await tester.ensureVisible(savingsTile);
    await tester.tap(savingsTile);
    await tester.pump();

    expect(openedSavings, isTrue);
    expect(find.textContaining('Phase 5'), findsNothing);
    expect(find.textContaining('Phase 6'), findsNothing);
  });

  testWidgets('le portefeuille affiche directement le coffre demandé', (
    WidgetTester tester,
  ) async {
    final SimulationAkibaStore store = SimulationAkibaStore();
    final AkibaDataRevision revision = AkibaDataRevision();
    final ValueNotifier<int> segment = ValueNotifier<int>(0);
    final AkibaSettings settings = AkibaSettings(store);
    await settings.load();
    addTearDown(revision.dispose);
    addTearDown(segment.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AkibaTheme.light(),
        home: AkibaSettingsScope(
          settings: settings,
          child: Scaffold(
            body: PortfolioScreen(
              store: store,
              revision: revision,
              segmentRequest: segment,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    segment.value = 2; // Épargne
    await tester.pumpAndSettle();

    expect(find.text('ÉPARGNE TOTALE'), findsOneWidget);
    expect(find.text('Coffres et objectifs'), findsOneWidget);
    expect(find.textContaining('Phase 5'), findsNothing);
  });
}
