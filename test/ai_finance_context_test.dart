import 'package:akiba/core/ai/ai_finance_context.dart';
import 'package:akiba/core/format/akiba_money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AkibaMoney.currency = 'FCFA';
  });

  const AiFinanceSummary summary = AiFinanceSummary(
    language: 'fr',
    masked: false,
    available: 12000,
    totalAccounts: 35000,
    savingsHeld: 8000,
    thirdPartyHeld: 5000,
    receivable: 3000,
    payable: 2000,
    budgets: <String>['Transport 4000 / 10000'],
    savingsPots: <String>['Fonds d’urgence 8000 / 20000'],
    recent: <String>['24/11/2026 · Transport · -2 000 FCFA'],
  );

  test('le résumé non masqué expose les montants et isole les tiers', () {
    final String text = summary.toPrompt();
    expect(text, contains(AkibaMoney.format(12000)));
    expect(text, contains(AkibaMoney.format(5000)));
    expect(text, contains('jamais le sien'));
    expect(text, contains('Transport 4000 / 10000'));
  });

  test('le mode masqué ne laisse filtrer aucun chiffre', () {
    const AiFinanceSummary masked = AiFinanceSummary(
      language: 'fr',
      masked: true,
      available: 12000,
      totalAccounts: 35000,
      savingsHeld: 8000,
      thirdPartyHeld: 5000,
      receivable: 3000,
      payable: 2000,
      budgets: <String>['Transport •••• FCFA / •••• FCFA'],
      savingsPots: <String>['Fonds d’urgence •••• FCFA'],
    );
    final String text = masked.toPrompt();
    expect(text, contains('mode masqué'));
    expect(text, contains('•••• FCFA'));
    expect(text, isNot(contains('12 000')));
    expect(text, isNot(contains('35 000')));
  });

  test('le résumé anglais suit la langue choisie', () {
    const AiFinanceSummary english = AiFinanceSummary(
      language: 'en',
      masked: false,
      available: 1000,
    );
    expect(english.toPrompt(), contains('Available balance'));
  });
}
