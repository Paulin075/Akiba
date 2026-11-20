import 'account.dart';

/// Total d'une catégorie sur une période (hors argent de tiers et épargne).
class CategoryTotal {
  const CategoryTotal({required this.label, required this.amount});

  final String label;
  final int amount;
}

/// Entrées et sorties d'un compte sur une période, hors argent de tiers.
class AccountPeriodTotal {
  const AccountPeriodTotal({
    required this.account,
    required this.income,
    required this.expense,
  });

  final Account account;
  final int income;
  final int expense;

  int get net => income - expense;

  bool get isEmpty => income == 0 && expense == 0;
}

/// Bilan d'un mois calendaire.
class MonthTotal {
  const MonthTotal({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
    required this.neutralIn,
    required this.neutralOut,
  });

  final int year;
  final int month;

  /// Entrées personnelles du mois.
  final int income;

  /// Sorties personnelles du mois (épargne et neutre exclues).
  final int expense;

  /// Entrées neutres reçues (argent de tiers).
  final int neutralIn;

  /// Reversements neutres sortis.
  final int neutralOut;

  int get net => income - expense;

  bool get hasNeutral => neutralIn != 0 || neutralOut != 0;
}
