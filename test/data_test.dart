import 'package:flutter_test/flutter_test.dart';

import 'package:akiba/core/database/akiba_secure_key.dart';
import 'package:akiba/data/balance_summary.dart';
import 'package:akiba/data/models/account.dart';
import 'package:akiba/data/models/account_brand.dart';
import 'package:akiba/data/models/budget.dart';
import 'package:akiba/data/models/debt.dart';
import 'package:akiba/data/models/savings_pot.dart';
import 'package:akiba/data/models/third_party.dart';
import 'package:akiba/data/models/transaction_record.dart';

void main() {
  group('BalanceSummary', () {
    test('le solde disponible retire l’argent de tiers', () {
      final BalanceSummary summary = BalanceSummary.fromSums(
        accountsTotal: 165500,
        savingsTransfersSum: 0,
        neutralSum: 122647,
      );

      expect(summary.totalAccounts, 165500);
      expect(summary.thirdPartyHeld, 122647);
      expect(summary.available, 42853);
    });

    test('un versement d’épargne ne change pas le solde disponible', () {
      const BalanceSummary before = BalanceSummary(
        totalAccounts: 50000,
        savingsHeld: 0,
        thirdPartyHeld: 0,
      );
      final BalanceSummary after = BalanceSummary.fromSums(
        accountsTotal: 45000,
        savingsTransfersSum: -5000,
        neutralSum: 0,
      );

      expect(after.savingsHeld, 5000);
      expect(after.available, before.available);
    });

    test('les reversements réduisent l’argent de tiers', () {
      final BalanceSummary summary = BalanceSummary.fromSums(
        accountsTotal: 30000,
        savingsTransfersSum: 0,
        neutralSum: 30000,
      );

      // 50 000 reçus pour un client, 20 000 déjà reversés.
      expect(summary.thirdPartyHeld, 30000);
      expect(summary.available, 0);
    });
  });

  group('BudgetStatus', () {
    BudgetStatus status(int limit, int spent) => BudgetStatus(
      budget: Budget(
        id: 'b',
        category: 'Transport',
        monthlyLimit: limit,
        createdAt: DateTime.utc(2026, 11, 19),
      ),
      spent: spent,
    );

    test('applique les seuils 80 % et 100 %', () {
      expect(status(10000, 7999).level, BudgetLevel.safe);
      expect(status(10000, 8000).level, BudgetLevel.warning);
      expect(status(10000, 10000).level, BudgetLevel.warning);
      expect(status(10000, 10001).level, BudgetLevel.exceeded);
    });

    test('borne la jauge et le reste dû', () {
      expect(status(10000, 15000).progress, 1);
      expect(status(10000, 15000).remaining, 0);
      expect(status(10000, 2500).progress, closeTo(0.25, 0.0001));
    });
  });

  group('Modèles', () {
    test('un compte survit à un aller-retour en base', () {
      final Account account = Account(
        id: 'flooz',
        name: 'Flooz perso',
        brand: AccountBrand.flooz,
        createdAt: DateTime.utc(2026, 11, 19, 8, 30),
      );

      final Account rebuilt = Account.fromRow(account.toRow());

      expect(rebuilt.id, account.id);
      expect(rebuilt.name, account.name);
      expect(rebuilt.brand, AccountBrand.flooz);
      expect(rebuilt.archived, isFalse);
      expect(rebuilt.createdAt, account.createdAt);
    });

    test('une transaction neutre ne compte pas pour le budget', () {
      final TransactionRecord record = TransactionRecord(
        id: 't1',
        accountId: 'flooz',
        amount: 50000,
        kind: TransactionKind.income,
        occurredAt: DateTime.utc(2026, 11, 19),
        createdAt: DateTime.utc(2026, 11, 19),
        isNeutral: true,
      );

      expect(record.countsForBudget, isFalse);
      expect(TransactionRecord.fromRow(record.toRow()).isNeutral, isTrue);
    });

    test('le reste dû d’une dette est borné', () {
      final Debt debt = Debt(
        id: 'd1',
        direction: DebtDirection.owedToMe,
        counterparty: 'Ama',
        principal: 20000,
        settledAmount: 5000,
        createdAt: DateTime.utc(2026, 11, 19),
      );
      final Debt overpaid = Debt(
        id: 'd2',
        direction: DebtDirection.iOwe,
        counterparty: 'Kodjo',
        principal: 10000,
        settledAmount: 12000,
        createdAt: DateTime.utc(2026, 11, 19),
      );

      expect(debt.remaining, 15000);
      expect(debt.isSettled, isFalse);
      expect(overpaid.remaining, 0);
      expect(overpaid.isSettled, isTrue);
    });

    test('coffres et tiers conservent leurs champs', () {
      final SavingsPot pot = SavingsPot(
        id: 'p1',
        name: 'Fonds d’urgence',
        kind: SavingsKind.emergency,
        targetAmount: 100000,
        createdAt: DateTime.utc(2026, 11, 19),
      );
      final ThirdParty party = ThirdParty(
        id: 'c1',
        name: 'Client Ama',
        note: 'Cotisation tontine',
        createdAt: DateTime.utc(2026, 11, 19),
      );

      final SavingsPot potBack = SavingsPot.fromRow(pot.toRow());
      final ThirdParty partyBack = ThirdParty.fromRow(party.toRow());

      expect(potBack.kind, SavingsKind.emergency);
      expect(potBack.targetAmount, 100000);
      expect(partyBack.name, 'Client Ama');
      expect(partyBack.note, 'Cotisation tontine');
    });
  });

  group('Clé de base', () {
    test('les clés générées font 256 bits en hexadécimal', () {
      final String key = AkibaSecureKey.generateHexKey();

      expect(key.length, AkibaSecureKey.keyHexLength);
      expect(AkibaSecureKey.isHexKey(key), isTrue);
      expect(AkibaSecureKey.isHexKey('pas-une-cle'), isFalse);
    });
  });
}
