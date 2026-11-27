import 'package:akiba/core/ai/ai_command_parser.dart';
import 'package:akiba/core/savings/savings_projection.dart';
import 'package:akiba/data/models/savings_pot.dart';
import 'package:akiba/data/models/transaction_record.dart';
import 'package:flutter_test/flutter_test.dart';

/// « Je veux mettre 100 francs par jour de côté pour un moniteur » doit créer
/// une épargne, pas une dépense « Alimentation ».
void main() {
  final DateTime now = DateTime(2026, 11, 27, 16, 18);

  test('une phrase de rythme quotidien devient un objectif d’épargne', () {
    final AiDraft? draft = AiCommandParser.parse(
      'je veux commencer à mettre 100 francs par jour de côté pour pouvoir me '
      'payer un moniteur donc tu peux créer l’épargne pour moi et me dire dans '
      'combien de temps je peux atteindre l’objectif si je commence demain',
      now: now,
    );

    expect(draft, isNotNull);
    expect(draft!.isSavings, isTrue);
    expect(draft.isSavingsGoal, isTrue);
    expect(draft.kind, TransactionKind.savings);
    expect(draft.amount, 100);
    expect(draft.dailyAmount, 100);
    expect(draft.goalName, 'Moniteur');
    // « demain » devient le premier versement.
    expect(draft.occurredAt, DateTime(2026, 11, 28));
    expect(draft.debtDirection, isNull);
  });

  test('le montant quotidien est celui qui précède « par jour »', () {
    final AiDraft? draft = AiCommandParser.parse(
      'épargne 2 000 par jour pour un ordinateur de 300 000',
      now: now,
    );

    expect(draft, isNotNull);
    expect(draft!.isSavingsGoal, isTrue);
    expect(draft.dailyAmount, 2000);
    expect(draft.goalName, 'Ordinateur');
  });

  test('un versement unique reste un versement, pas un objectif', () {
    final AiDraft? draft = AiCommandParser.parse(
      'mets 5 000 de côté pour le voyage',
      now: now,
    );

    expect(draft, isNotNull);
    expect(draft!.isSavings, isTrue);
    expect(draft.isSavingsGoal, isFalse);
    expect(draft.amount, 5000);
    expect(draft.occurredAt, now);
  });

  test('une dépense ordinaire reste une dépense', () {
    final AiDraft? draft = AiCommandParser.parse(
      'j’ai payé 3 000 pour le transport',
      now: now,
    );

    expect(draft, isNotNull);
    expect(draft!.isSavingsGoal, isFalse);
    expect(draft.kind, TransactionKind.expense);
    expect(draft.category, 'Transport');
  });

  group('Projection à rythme fixe', () {
    test('100 FCFA par jour pour 100 000 FCFA : 1 000 versements', () {
      expect(SavingsProjection.depositsFor(target: 100000, daily: 100), 1000);
      expect(
        SavingsProjection.dateForDailyPlan(
          target: 100000,
          daily: 100,
          firstDeposit: DateTime(2026, 11, 28),
        ),
        DateTime(2026, 11, 28).add(const Duration(days: 999)),
      );
    });

    test('objectif déjà atteint ou rythme nul : aucune date', () {
      expect(
        SavingsProjection.dateForDailyPlan(
          target: 5000,
          daily: 100,
          firstDeposit: now,
          held: 5000,
        ),
        isNull,
      );
      expect(
        SavingsProjection.dateForDailyPlan(
          target: 5000,
          daily: 0,
          firstDeposit: now,
        ),
        isNull,
      );
    });

    test('un objectif irréaliste au-delà de dix ans reste sans date', () {
      expect(
        SavingsProjection.dateForDailyPlan(
          target: 10000000,
          daily: 1,
          firstDeposit: now,
        ),
        isNull,
      );
    });

    test('le coffre créé est un objectif chiffré', () {
      final SavingsPot pot = SavingsPot(
        id: 'pot-1',
        name: 'Moniteur',
        kind: SavingsKind.goal,
        targetAmount: 100000,
        targetDate: DateTime(2029, 8, 23),
        createdAt: now,
      );

      expect(pot.kind, SavingsKind.goal);
      expect(pot.targetAmount, 100000);
      expect(pot.toRow()['target_amount'], 100000);
    });
  });
}
