/// Niveau d'alerte d'un budget, selon les seuils du cahier des charges.
enum BudgetLevel {
  /// Consommation < 80 % : vert.
  safe,

  /// Consommation de 80 % à 100 % : orange.
  warning,

  /// Consommation > 100 % : rouge.
  exceeded,
}

/// Plafond mensuel récurrent pour une catégorie.
class Budget {
  const Budget({
    required this.id,
    required this.category,
    required this.monthlyLimit,
    required this.createdAt,
  }) : assert(monthlyLimit > 0, 'Un plafond doit être positif');

  final String id;

  /// Libellé de catégorie (une seule ligne de budget par catégorie).
  final String category;

  /// Plafond mensuel en FCFA entiers.
  final int monthlyLimit;

  final DateTime createdAt;

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'category': category,
    'monthly_limit': monthlyLimit,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory Budget.fromRow(Map<String, Object?> row) => Budget(
    id: row['id']! as String,
    category: row['category']! as String,
    monthlyLimit: row['monthly_limit']! as int,
    createdAt: DateTime.parse(row['created_at']! as String),
  );
}

/// Budget accompagné de la dépense réelle du mois en cours.
class BudgetStatus {
  const BudgetStatus({required this.budget, required this.spent});

  final Budget budget;

  /// Sorties du mois pour cette catégorie, hors transactions neutres.
  final int spent;

  int get limit => budget.monthlyLimit;

  int get remaining {
    final int rest = budget.monthlyLimit - spent;
    return rest < 0 ? 0 : rest;
  }

  /// Part consommée (peut dépasser 1).
  double get ratio => spent / budget.monthlyLimit;

  /// Part affichée dans une jauge, bornée à 1.
  double get progress => ratio > 1 ? 1 : (ratio < 0 ? 0 : ratio);

  bool get isExceeded => spent > budget.monthlyLimit;

  BudgetLevel get level {
    if (isExceeded) return BudgetLevel.exceeded;
    if (ratio >= 0.8) return BudgetLevel.warning;
    return BudgetLevel.safe;
  }
}
