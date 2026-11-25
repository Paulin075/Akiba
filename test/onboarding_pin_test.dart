import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/data/simulation_store.dart';
import 'package:akiba/main.dart';

/// Parcours réel : ouverture, onboarding E1→E11 avec un PIN, puis saisie du
/// code sur l'écran de verrouillage.
///
/// Ce test reproduit le scénario qui faisait tomber l'assertion de Flutter
/// (`InheritedElement.notifyClients`) au premier code PIN : le champ de
/// l'onboarding et celui du verrou ne doivent jamais coexister.
void main() {
  testWidgets('onboarding avec PIN, puis déverrouillage sans assertion', (
    WidgetTester tester,
  ) async {
    final SimulationAkibaStore store = SimulationAkibaStore();
    final AkibaSettings settings = AkibaSettings(store);
    await settings.load();

    await tester.pumpWidget(AkibaApp(store: store, settings: settings));

    // Ouverture : 1 s d'animation seulement, puis l'onboarding.
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Bienvenue dans AKIBA'), findsOneWidget);
    expect(find.text('Étape 1 sur 11'), findsOneWidget);
    expect(tester.takeException(), isNull);

    Future<void> tapNext({String label = 'Continuer'}) async {
      final Finder button = find.text(label);
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    // E1 bienvenue -> E2 valeur -> E3 Google (avant toute saisie de nom).
    await tapNext();
    await tapNext();
    expect(find.text('Sauvegarde et restauration'), findsOneWidget);
    expect(find.text('Comment vous appelez-vous ?'), findsNothing);

    // E3 -> E4 devise -> E5 identité (aucun compte Google lié ici).
    await tapNext();
    await tapNext();
    expect(find.text('Comment vous appelez-vous ?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Ama');
    await tester.enterText(find.byType(TextField).at(1), 'Koffi');

    // E5 -> E6 comptes.
    await tapNext();
    expect(find.text('Vos comptes de départ'), findsOneWidget);

    // E6 -> E7 code PIN.
    await tapNext();
    expect(find.text('Protégez l’accès'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).at(0), '4821');
    await tester.enterText(find.byType(TextField).at(1), '4821');

    // Première saisie de code : c'est ici que l'assertion apparaissait.
    await tapNext();
    expect(tester.takeException(), isNull);
    expect(find.text('Des permissions expliquées'), findsOneWidget);

    // E8 permissions -> E9 habitudes -> E10 données -> E11 prêt.
    await tapNext();
    await tapNext();
    await tapNext();
    expect(find.text('Prêt et bienvenue'), findsOneWidget);

    // Fin du parcours : le logo zoome puis l'accueil se bascule.
    await tapNext(label: 'Entrer dans AKIBA');
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Le PIN enregistré pendant l'onboarding verrouille bien l'application.
    expect(find.text('AKIBA est verrouillé'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '4821');
    await tester.pump();
    await tester.tap(find.text('Déverrouiller'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('AKIBA est verrouillé'), findsNothing);
    expect(find.text('Accueil'), findsWidgets);

    // Laisse l'apparition en cascade de l'accueil se terminer (40 ms par bloc)
    // pour ne pas laisser de minuteur en attente à la fin du test.
    await tester.pump(const Duration(seconds: 2));
  });
}
