import '../../data/akiba_store.dart';
import '../../data/models/budget.dart';
import '../../data/models/debt.dart';
import '../../data/models/savings_pot.dart';
import '../../data/models/transaction_record.dart';
import '../format/akiba_money.dart';

/// Résumé local de la situation financière, destiné à l'assistant IA.
///
/// Règles AKIBA :
/// - les montants viennent **uniquement** de la base locale (réelle ou
///   simulation), jamais d'un total inventé ;
/// - en mode masqué, aucun chiffre n'est écrit : le résumé ne contient que la
///   structure (nombre de comptes, de coffres, de budgets) ;
/// - l'argent de tiers, l'épargne et les créances/dettes restent présentés
///   séparément, jamais additionnés au solde disponible.
class AiFinanceSummary {
  const AiFinanceSummary({
    required this.language,
    required this.masked,
    this.available = 0,
    this.totalAccounts = 0,
    this.savingsHeld = 0,
    this.thirdPartyHeld = 0,
    this.receivable = 0,
    this.payable = 0,
    this.budgets = const <String>[],
    this.savingsPots = const <String>[],
    this.recent = const <String>[],
  });

  final String language;
  final bool masked;
  final int available;
  final int totalAccounts;
  final int savingsHeld;
  final int thirdPartyHeld;
  final int receivable;
  final int payable;

  /// Une ligne par budget : « Alimentation 12 000 / 30 000 ».
  final List<String> budgets;

  /// Une ligne par coffre : « Fonds d'urgence 15 000 / 50 000 ».
  final List<String> savingsPots;

  /// Derniers mouvements lisibles (date, libellé, montant signé).
  final List<String> recent;

  bool get isEnglish => language == 'en';

  /// Montant rendu lisible, ou masqué si le mode masqué est actif.
  String amount(int value) => masked ? '•••• FCFA' : AkibaMoney.format(value);

  /// Lit la base et construit le résumé. Aucun appel réseau.
  static Future<AiFinanceSummary> build(
    AkibaStore store, {
    required bool masked,
    required String language,
  }) async {
    final DashboardSnapshot snapshot = await store.loadDashboard();
    final List<BudgetStatus> budgets = await store.budgets();
    final List<SavingsPotBalance> pots = await store.savingsBalances();
    final List<Debt> debts = await store.debts();
    final List<TransactionRecord> movements = await store.transactions(
      limit: 10,
    );

    int receivable = 0;
    int payable = 0;
    for (final Debt debt in debts) {
      if (debt.direction == DebtDirection.owedToMe) {
        receivable += debt.remaining;
      } else {
        payable += debt.remaining;
      }
    }

    return AiFinanceSummary(
      language: language,
      masked: masked,
      available: snapshot.balance.available,
      totalAccounts: snapshot.balance.totalAccounts,
      savingsHeld: snapshot.balance.savingsHeld,
      thirdPartyHeld: snapshot.balance.thirdPartyHeld,
      receivable: receivable,
      payable: payable,
      budgets: <String>[
        for (final BudgetStatus status in budgets)
          '${status.budget.category} ${_money(status.spent, masked)} / '
              '${_money(status.limit, masked)}',
      ],
      savingsPots: <String>[
        for (final SavingsPotBalance pot in pots)
          '${pot.pot.name} ${_money(pot.held, masked)}'
              '${pot.pot.targetAmount > 0 ? ' / ${_money(pot.pot.targetAmount, masked)}' : ''}',
      ],
      recent: <String>[
        for (final TransactionRecord record in movements)
          if (record.kind != TransactionKind.opening)
            '${_date(record.occurredAt)} · '
                '${record.category ?? record.note ?? record.kind.name} · '
                '${_money(record.amount, masked, signed: true)}',
      ],
    );
  }

  /// Résumé compact envoyé au modèle ou affiché localement.
  String toPrompt() {
    final bool en = isEnglish;
    final StringBuffer buffer = StringBuffer();
    buffer.writeln(en ? 'AKIBA local summary:' : 'Résumé local AKIBA :');
    if (masked) {
      buffer.writeln(
        en
            ? 'Masked mode is active: amounts are deliberately hidden.'
            : 'Le mode masqué est actif : les montants sont volontairement '
                  'masqués.',
      );
    }
    buffer.writeln(
      en
          ? 'Available balance: ${amount(available)}; total accounts: '
                '${amount(totalAccounts)}; savings vault: ${amount(savingsHeld)}.'
          : 'Solde disponible : ${amount(available)} ; total des comptes : '
                '${amount(totalAccounts)} ; coffre épargne : ${amount(savingsHeld)}.',
    );
    buffer.writeln(
      en
          ? 'Money owed to the user: ${amount(receivable)}; money the user '
                'owes: ${amount(payable)}; third-party money held (never the '
                'user’s): ${amount(thirdPartyHeld)}.'
          : 'On doit à l’utilisateur : ${amount(receivable)} ; l’utilisateur '
                'doit : ${amount(payable)} ; argent de tiers détenu (jamais le '
                'sien) : ${amount(thirdPartyHeld)}.',
    );
    if (budgets.isNotEmpty) {
      buffer.writeln('${en ? 'Budgets' : 'Budgets'} : ${budgets.join(' · ')}');
    }
    if (savingsPots.isNotEmpty) {
      buffer.writeln(
        '${en ? 'Savings pots' : 'Coffres'} : ${savingsPots.join(' · ')}',
      );
    }
    if (recent.isNotEmpty) {
      buffer.writeln(
        '${en ? 'Last movements' : 'Derniers mouvements'} : '
        '${recent.join(' | ')}',
      );
    }
    return buffer.toString().trim();
  }

  static String _money(int value, bool masked, {bool signed = false}) {
    if (masked) return '•••• FCFA';
    return signed ? AkibaMoney.formatSigned(value) : AkibaMoney.format(value);
  }

  static String _date(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }
}
