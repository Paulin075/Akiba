import 'package:flutter_test/flutter_test.dart';

import 'package:akiba/core/format/akiba_money.dart';
import 'package:akiba/main.dart';

void main() {
  group('AkibaMoney', () {
    test('formate les FCFA sans décimales avec séparateur de milliers', () {
      expect(AkibaMoney.format(15000), '15\u00A0000\u00A0FCFA');
      expect(AkibaMoney.format(1250000), '1\u00A0250\u00A0000\u00A0FCFA');
      expect(AkibaMoney.format(0), '0\u00A0FCFA');
      expect(AkibaMoney.format(-3500), '−3\u00A0500\u00A0FCFA');
    });

    test('masque les montants', () {
      expect(AkibaMoney.format(42853, masked: true), '••••••\u00A0FCFA');
    });

    test('formate les montants signés', () {
      expect(AkibaMoney.formatSigned(10000), '+ 10\u00A0000\u00A0FCFA');
      expect(AkibaMoney.formatSigned(-3500), '− 3\u00A0500\u00A0FCFA');
    });
  });

  testWidgets('le premier démarrage ouvre l’onboarding', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AkibaApp());
    await tester.pump();
    // L'ouverture ne montre que l'animation cochon + cauri, 1 s, puis
    // l'onboarding prend le relais.
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Bienvenue dans AKIBA'), findsOneWidget);
    expect(find.text('Étape 1 sur 11'), findsOneWidget);
    // Pas de barre basse ni de solde avant la fin de l'onboarding.
    expect(find.text('Accueil'), findsNothing);
  });
}
