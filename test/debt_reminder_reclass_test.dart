import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:akiba/core/notifications/reminder_planner.dart';
import 'package:akiba/core/state/akiba_data_revision.dart';
import 'package:akiba/core/theme/akiba_theme.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:akiba/data/models/account.dart';
import 'package:akiba/data/models/account_brand.dart';
import 'package:akiba/data/models/transaction_record.dart';
import 'package:akiba/data/simulation_store.dart';
import 'package:akiba/data/transaction_reclassifier.dart';
import 'package:akiba/features/portfolio/movement_detail_sheet.dart';

void main() {
  group('Rappel d’échéance de créance et de dette', () {
    test('un rappel par échéance à venir, sans montant ni nom', () {
      final DateTime now = DateTime(2026, 11, 23, 10);
      final List<ReminderPlan> plans = ReminderPlanner.planDebts(<DebtDue>[
        // Créance à échéance demain.
        DebtDue(
          id: 'd1',
          dueDate: DateTime(2026, 11, 24),
          owedToMe: true,
          remaining: 5000,
        ),
        // Dette à échéance demain.
        DebtDue(
          id: 'd2',
          dueDate: DateTime(2026, 11, 24),
          owedToMe: false,
          remaining: 3000,
        ),
        // Soldée : aucun rappel.
        DebtDue(
          id: 'd3',
          dueDate: DateTime(2026, 11, 25),
          owedToMe: true,
          remaining: 0,
        ),
        // Au-delà de l'horizon de 30 jours : aucun rappel.
        DebtDue(
          id: 'd4',
          dueDate: DateTime(2027, 2, 1),
          owedToMe: false,
          remaining: 9000,
        ),
        // Échéance du jour déjà passée (9 h) : aucun rappel.
        DebtDue(
          id: 'd5',
          dueDate: DateTime(2026, 11, 23),
          owedToMe: true,
          remaining: 1000,
        ),
      ], now: now);

      expect(plans.length, 2);
      expect(plans.first.slot, 'echeance');
      expect(plans.first.when, DateTime(2026, 11, 24, 9));
      expect(plans.last.when, DateTime(2026, 11, 24, 9));

      for (final ReminderPlan plan in plans) {
        // Le message ne contient ni montant ni nom de contact.
        expect(RegExp(r'\d').hasMatch(plan.body), isFalse);
        expect(plan.body.contains('FCFA'), isFalse);
        expect(plan.body.contains('FCFA'), isFalse);
        expect(plan.festive, isFalse);
      }
      expect(plans.first.title, contains('Créance'));
      expect(plans.last.title, contains('Dette'));
      expect(plans.first.body, contains('créance'));
      expect(plans.last.body, contains('dette'));
    });

    test('une date d’échéance lointaine reste dans l’horizon demandé', () {
      final DateTime now = DateTime(2026, 11, 23, 8);
      final List<ReminderPlan> plans = ReminderPlanner.planDebts(
        <DebtDue>[
          DebtDue(
            id: 'd1',
            dueDate: DateTime(2026, 12, 20),
            owedToMe: false,
            remaining: 12000,
          ),
        ],
        now: now,
        horizonDays: 60,
      );

      expect(plans, hasLength(1));
      expect(plans.single.when, DateTime(2026, 12, 20, 9));
    });
  });

  group('Reclassement d’une transaction', () {
    final DateTime now = DateTime(2026, 11, 23, 12);
    final TransactionRecord expense = TransactionRecord(
      id: 't1',
      accountId: 'a1',
      amount: -5000,
      kind: TransactionKind.expense,
      category: 'Alimentation',
      note: 'Déjeuner',
      occurredAt: now,
      createdAt: now,
    );

    test('seules les entrées et sorties réelles sont reclassables', () {
      expect(TransactionReclassifier.canReclassify(expense), isTrue);

      final TransactionRecord neutral = TransactionRecord(
        id: 't2',
        accountId: 'a1',
        amount: -5000,
        kind: TransactionKind.expense,
        isNeutral: true,
        occurredAt: now,
        createdAt: now,
      );
      expect(TransactionReclassifier.canReclassify(neutral), isFalse);

      for (final TransactionKind kind in <TransactionKind>[
        TransactionKind.transfer,
        TransactionKind.savings,
        TransactionKind.opening,
      ]) {
        expect(
          TransactionReclassifier.canReclassify(
            TransactionRecord(
              id: 'k-${kind.name}',
              accountId: 'a1',
              amount: 4000,
              kind: kind,
              occurredAt: now,
              createdAt: now,
            ),
          ),
          isFalse,
        );
      }
    });

    test('la copie ne change que la catégorie', () {
      final TransactionRecord updated = TransactionReclassifier.withCategory(
        expense,
        'Transport',
      );

      expect(updated.category, 'Transport');
      expect(updated.id, expense.id);
      expect(updated.amount, -5000);
      expect(updated.kind, TransactionKind.expense);
      expect(updated.accountId, expense.accountId);
      expect(updated.note, 'Déjeuner');
      expect(updated.occurredAt, expense.occurredAt);
      expect(updated.isNeutral, isFalse);

      expect(
        TransactionReclassifier.withCategory(expense, null).category,
        isNull,
      );
    });

    test('les catégories proposées suivent le sens du mouvement', () {
      expect(
        TransactionReclassifier.categoriesFor(expense),
        TransactionReclassifier.expenseCategories,
      );
      expect(
        TransactionReclassifier.categoriesFor(
          TransactionRecord(
            id: 'i1',
            accountId: 'a1',
            amount: 20000,
            kind: TransactionKind.income,
            occurredAt: now,
            createdAt: now,
          ),
        ),
        TransactionReclassifier.incomeCategories,
      );
    });
  });

  testWidgets('la fiche de détail reclasse sans changer le montant', (
    WidgetTester tester,
  ) async {
    final SimulationAkibaStore store = SimulationAkibaStore();
    final AkibaDataRevision revision = AkibaDataRevision();
    addTearDown(revision.dispose);

    final DateTime now = DateTime(2026, 11, 23, 12);
    final Account account = Account(
      id: 'a1',
      name: 'Liquide',
      brand: AccountBrand.liquide,
      createdAt: now,
    );
    final TransactionRecord transaction = TransactionRecord(
      id: 't1',
      accountId: 'a1',
      amount: -5000,
      kind: TransactionKind.expense,
      category: 'Alimentation',
      note: 'Déjeuner',
      occurredAt: now,
      createdAt: now,
    );
    await store.saveTransaction(transaction);

    await tester.pumpWidget(
      MaterialApp(
        theme: AkibaTheme.light(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showMovementDetail(
                  context,
                  line: TransactionLine(
                    transaction: transaction,
                    account: account,
                  ),
                  store: store,
                  revision: revision,
                  masked: true,
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    expect(find.text('DÉTAIL DU MOUVEMENT'), findsOneWidget);
    // Masquage : le montant n'apparaît nulle part.
    expect(find.text('5 000 FCFA'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Transport'));
    await tester.pumpAndSettle();

    final TransactionRecord saved = (await store.transactions()).firstWhere(
      (TransactionRecord record) => record.id == 't1',
    );
    expect(saved.category, 'Transport');
    expect(saved.amount, -5000);
    expect(saved.id, 't1');
  });
}
