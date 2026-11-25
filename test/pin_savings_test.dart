import 'package:flutter_test/flutter_test.dart';

import 'package:akiba/core/ai/ai_command_parser.dart';
import 'package:akiba/core/security/pin_attempts.dart';
import 'package:akiba/core/savings/savings_projection.dart';
import 'package:akiba/data/models/transaction_record.dart';
import 'package:akiba/data/simulation_store.dart';

void main() {
  group('Saisie vocale : « on me doit » / « je dois »', () {
    test('« Guy me doit 3000 fr » devient une créance « On me doit »', () {
      final AiDraft draft = AiCommandParser.parse('Guy me doit 3000 fr')!;

      expect(draft.debtDirection, 'owedToMe');
      expect(draft.amount, 3000);
      expect(draft.counterparty, 'Guy');
      // Jamais une sortie d'argent, jamais une ligne neutre.
      expect(draft.kind, TransactionKind.income);
      expect(draft.kind, isNot(TransactionKind.expense));
      expect(draft.isNeutral, isFalse);
    });

    test('« Je dois 3000 fr à Guy » devient une dette « Je dois »', () {
      final AiDraft draft = AiCommandParser.parse('Je dois 3000 fr à Guy')!;

      expect(draft.debtDirection, 'iOwe');
      expect(draft.amount, 3000);
      expect(draft.counterparty, 'Guy');
      expect(draft.isNeutral, isFalse);
    });

    test('la dictée en lettres est comprise : « trois mille francs »', () {
      final AiDraft draft = AiCommandParser.parse(
        'Guy me doit trois mille francs',
      )!;

      expect(draft.debtDirection, 'owedToMe');
      expect(draft.amount, 3000);
      expect(draft.counterparty, 'Guy');
    });

    test('nombres en lettres composés et contact sans tiers configuré', () {
      final AiDraft owed = AiCommandParser.parse(
        'Je dois douze mille cinq cents à Ama',
      )!;
      expect(owed.debtDirection, 'iOwe');
      expect(owed.amount, 12500);
      expect(owed.counterparty, 'Ama');

      final AiDraft anonymous = AiCommandParser.parse(
        'on me doit quatre-vingt mille',
      )!;
      expect(anonymous.debtDirection, 'owedToMe');
      expect(anonymous.amount, 80000);
      expect(anonymous.counterparty, isNull);

      final AiDraft plain = AiCommandParser.parse('Guy me doit 3000 fr')!;
      expect(plain.debtDirection, 'owedToMe');
    });

    test('une dépense dictée en lettres reste une sortie catégorisée', () {
      final AiDraft draft = AiCommandParser.parse(
        'j’ai payé cinq mille pour le transport',
      )!;

      expect(draft.debtDirection, isNull);
      expect(draft.kind, TransactionKind.expense);
      expect(draft.amount, 5000);
      expect(draft.category, 'Transport');
    });

    test('un mot sans multiplicateur ne fabrique pas un montant', () {
      // « un café » ne doit jamais devenir 1 FCFA.
      expect(AiCommandParser.parse('j’ai bu un café'), isNull);
    });
  });

  group('Limitation des essais de PIN', () {
    test('les trois premiers essais sont libres, puis le délai croît', () {
      expect(PinAttempts.delayFor(0), Duration.zero);
      expect(PinAttempts.delayFor(2), Duration.zero);
      expect(PinAttempts.delayFor(3), const Duration(seconds: 30));
      expect(PinAttempts.delayFor(4), const Duration(seconds: 60));
      expect(PinAttempts.delayFor(5), const Duration(seconds: 120));
      expect(PinAttempts.delayFor(6), const Duration(seconds: 300));
      expect(PinAttempts.delayFor(20), const Duration(seconds: 300));
    });

    test('les secondes restantes ne sont jamais négatives', () {
      final DateTime now = DateTime(2026, 11, 23, 12);
      expect(PinAttempts.remainingSeconds(null, now), 0);
      expect(
        PinAttempts.remainingSeconds(
          now.subtract(const Duration(seconds: 5)),
          now,
        ),
        0,
      );
      expect(
        PinAttempts.remainingSeconds(now.add(const Duration(seconds: 42)), now),
        42,
      );
    });

    test(
      'le compteur persiste et se remet à zéro après un code correct',
      () async {
        final SimulationAkibaStore store = SimulationAkibaStore();
        final PinAttempts attempts = PinAttempts(store);
        final DateTime now = DateTime(2026, 11, 23, 12);

        expect(await attempts.failures(), 0);
        expect(await attempts.registerFailure(now: now), Duration.zero);
        expect(await attempts.registerFailure(now: now), Duration.zero);
        expect(
          await attempts.registerFailure(now: now),
          const Duration(seconds: 30),
        );
        expect(await attempts.failures(), 3);
        expect(await attempts.remaining(now: now), const Duration(seconds: 30));

        // Un nouveau coffre sur le même magasin relit l'état : quitter
        // l'application ne remet pas les essais à zéro.
        expect(
          await PinAttempts(store).remaining(now: now),
          isNot(Duration.zero),
        );

        await attempts.reset();
        expect(await attempts.failures(), 0);
        expect(await attempts.remaining(now: now), Duration.zero);
      },
    );
  });

  group('Épargne : proposition et date d’atteinte', () {
    test('la proposition est bornée entre 0 et 30 % du solde', () {
      expect(
        SavingsProjection.suggestedDeposit(accountBalance: 100000, percent: 10),
        10000,
      );
      expect(
        SavingsProjection.suggestedDeposit(accountBalance: 100000, percent: 0),
        0,
      );
      expect(
        SavingsProjection.suggestedDeposit(accountBalance: 100000, percent: 35),
        30000,
      );
      expect(
        SavingsProjection.suggestedDeposit(accountBalance: -5000, percent: 20),
        0,
      );
    });

    test('la date d’atteinte suit le rythme observé', () {
      final DateTime now = DateTime(2026, 11, 23);

      final DateTime? eta = SavingsProjection.estimateTargetDate(
        held: 10000,
        target: 20000,
        createdAt: now.subtract(const Duration(days: 10)),
        now: now,
      );
      expect(eta, isNotNull);
      expect(eta!.difference(now).inDays, 10);

      expect(
        SavingsProjection.estimateTargetDate(
          held: 0,
          target: 20000,
          createdAt: now.subtract(const Duration(days: 10)),
          now: now,
        ),
        isNull,
      );
      expect(
        SavingsProjection.estimateTargetDate(
          held: 20000,
          target: 20000,
          createdAt: now.subtract(const Duration(days: 10)),
          now: now,
        ),
        isNull,
      );
      expect(
        SavingsProjection.estimateTargetDate(
          held: 500,
          target: 20000,
          createdAt: now,
          now: now,
        ),
        isNull,
      );
    });
  });
}
