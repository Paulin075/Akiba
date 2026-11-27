import 'dart:convert';

import 'package:akiba/core/backup/google_profile.dart';
import 'package:akiba/core/state/akiba_data_revision.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/core/theme/akiba_theme.dart';
import 'package:akiba/data/simulation_store.dart';
import 'package:akiba/features/onboarding/onboarding_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// L'ordre du parcours est un engagement : Google d'abord, saisie manuelle du
/// nom ensuite (et seulement si aucun compte Google n'est lié).
void main() {
  late SimulationAkibaStore store;
  late AkibaSettings settings;

  Future<void> mountAt(WidgetTester tester, int step) async {
    store = SimulationAkibaStore();
    settings = AkibaSettings(store);
    await settings.load();
    await settings.setOnboardingStep(step);
    await tester.pumpWidget(
      MaterialApp(
        theme: AkibaTheme.forId(AkibaThemeId.blanc),
        home: OnboardingFlow(
          store: store,
          settings: settings,
          revision: AkibaDataRevision(),
          onFinished: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('le profil Google fournit prénom et nom, sans invention', () {
    final GoogleProfile split = GoogleProfile.fromDisplayName('Ama Koffi');
    expect(split.givenName, 'Ama');
    expect(split.familyName, 'Koffi');

    final String payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode(<String, String>{
              'given_name': 'Ama',
              'family_name': 'Kodjo Koffi',
            }),
          ),
        )
        .replaceAll('=', '');
    final GoogleProfile claims = GoogleProfile.fromIdToken('h.$payload.s');
    expect(claims.givenName, 'Ama');
    expect(claims.familyName, 'Kodjo Koffi');
    expect(GoogleProfile.fromIdToken('illisible'), GoogleProfile.empty);
  });

  testWidgets('la connexion Google précède la demande du prénom et du nom', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await mountAt(tester, 2);

    Future<void> tapText(String label) async {
      final Finder target = find.text(label);
      await tester.ensureVisible(target);
      await tester.pump();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    expect(find.text('Sauvegarde et restauration'), findsOneWidget);
    expect(find.text('Se connecter avec Google'), findsOneWidget);
    expect(find.text('Comment vous appelez-vous ?'), findsNothing);
    expect(find.text('Étape 3 sur 11'), findsOneWidget);

    // Sans connexion Google, AKIBA propose le serveur de sauvegarde local
    // avant de passer à la devise. La page reste facultative.
    await tapText('Continuer');
    expect(find.text('Serveur de sauvegarde'), findsOneWidget);
    expect(find.text('Continuer sans restaurer'), findsOneWidget);

    await tapText('Continuer sans restaurer');
    expect(find.text('Votre devise et votre fuseau'), findsOneWidget);

    await tapText('Continuer');
    expect(find.text('Comment vous appelez-vous ?'), findsOneWidget);
    expect(find.text('Votre prénom apparaîtra sur l’accueil.'), findsOneWidget);
  });
}
