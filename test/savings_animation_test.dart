import 'package:akiba/core/savings/savings_projection.dart';
import 'package:akiba/core/theme/akiba_theme.dart';
import 'package:akiba/core/theme/akiba_tokens.dart';
import 'package:akiba/core/widgets/cauri_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(WidgetTester tester, {required int cauriCount}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AkibaTheme.light(),
        home: Scaffold(
          body: Center(
            child: CauriDropAnimation(
              size: 200,
              duration: AkibaDurations.cauriDrop,
              cauriCount: cauriCount,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<String> cauriKeys(WidgetTester tester) {
    return tester
        .widgetList<Image>(find.byType(Image))
        .map((Image image) => image.key)
        .whereType<ValueKey<String>>()
        .map((ValueKey<String> key) => key.value)
        .where((String value) => value.startsWith('cauri-'))
        .toList(growable: false);
  }

  testWidgets('2 000 FCFA font tomber 20 cauris, sans badge « ×20 »', (
    WidgetTester tester,
  ) async {
    final int count = SavingsProjection.cauriCountForAmount(2000);
    expect(count, 20);

    bool completed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AkibaTheme.light(),
        home: Scaffold(
          body: Center(
            child: CauriDropAnimation(
              size: 200,
              duration: AkibaDurations.cauriDrop,
              cauriCount: count,
              onCompleted: () => completed = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(cauriKeys(tester).length, 20);
    expect(cauriKeys(tester), contains('cauri-19'));
    // Plus aucun multiplicateur textuel à côté d'un cauri unique.
    expect(find.textContaining('×'), findsNothing);

    // Durée totale inchangée : 3 secondes, puis le message peut apparaître.
    await tester.pump(const Duration(milliseconds: 3100));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });

  testWidgets('un très gros montant reste fluide et sans compteur texte', (
    WidgetTester tester,
  ) async {
    await mount(tester, cauriCount: 5000);

    final List<String> keys = cauriKeys(tester);
    expect(keys.length, CauriDropAnimation.maxVisibleCauris);
    expect(find.textContaining('×'), findsNothing);
    expect(find.textContaining('5000'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
