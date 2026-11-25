import 'package:akiba/core/format/akiba_currency.dart';
import 'package:akiba/core/format/akiba_money.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:akiba/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Réglages transverses : la langue et la devise choisies doivent changer
/// l'interface immédiatement, sans redémarrage.
void main() {
  Future<void> pumpApp(WidgetTester tester, AkibaSettings settings) async {
    tester.view.physicalSize = const Size(1500, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await settings.load();
    await settings.setFlag('onboarding_done', true);
    await tester.pumpWidget(AkibaApp(settings: settings));
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('la devise choisie se reflète sur l’accueil et le profil', (
    WidgetTester tester,
  ) async {
    final AkibaSettings settings = AkibaSettings(const EmptyAkibaStore());
    await pumpApp(tester, settings);
    expect(AkibaMoney.currency, 'FCFA');

    await settings.setCurrency(AkibaCurrency.euro);
    await tester.pump(const Duration(milliseconds: 300));

    expect(settings.currencyCode, AkibaCurrency.euro);
    expect(AkibaMoney.currency, '€');
    expect(find.textContaining('€'), findsWidgets);
    expect(find.textContaining('FCFA'), findsNothing);

    // Changement depuis la tuile Préférences du Profil (chemin réel).
    await tester.tap(find.text('Profil').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Dollar').first);
    await tester.pump(const Duration(milliseconds: 500));

    expect(settings.currencyCode, AkibaCurrency.dollar);
    expect(AkibaMoney.currency, r'$');
    expect(tester.takeException(), isNull);
  });

  testWidgets('le passage à l’anglais change la navigation et l’accueil', (
    WidgetTester tester,
  ) async {
    final AkibaSettings settings = AkibaSettings(const EmptyAkibaStore());
    await pumpApp(tester, settings);

    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Mon argent'), findsOneWidget);

    await settings.setLanguage('en');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('My money'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Accueil'), findsNothing);

    // La tuile Préférences du Profil expose bien le choix de langue.
    await tester.tap(find.text('Profile').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);

    await settings.setLanguage('fr');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Préférences'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
