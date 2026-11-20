/// Nature d'un coffre d'épargne.
enum SavingsKind {
  /// Fonds d'urgence.
  emergency,

  /// Objectif daté (voyage, achat…).
  goal,

  /// Épargne libre.
  free;

  static SavingsKind fromStorage(String value) {
    for (final SavingsKind kind in values) {
      if (kind.name == value) return kind;
    }
    return free;
  }
}

/// Coffre épargne accompagné de son montant épargné (dérivé des transactions).
class SavingsPotBalance {
  const SavingsPotBalance({required this.pot, required this.held});

  final SavingsPot pot;

  /// Montant actuellement dans le coffre, en FCFA entiers.
  final int held;

  double get ratio {
    if (pot.targetAmount <= 0) return 0;
    return held / pot.targetAmount;
  }

  /// Part affichée dans la jauge, bornée entre 0 et 1.
  double get progress {
    final double value = ratio;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  bool get isReached => pot.targetAmount > 0 && held >= pot.targetAmount;
}

/// Coffre épargne interne.
///
/// Le montant épargné n'est pas stocké ici : il est dérivé des transactions de
/// type [TransactionKind.savings] rattachées au coffre.
class SavingsPot {
  const SavingsPot({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
    this.targetAmount = 0,
    this.targetDate,
    this.archived = false,
  }) : assert(targetAmount >= 0, 'Un objectif ne peut pas être négatif');

  final String id;
  final String name;
  final SavingsKind kind;

  /// Objectif en FCFA entiers (0 : pas d'objectif chiffré).
  final int targetAmount;

  final DateTime? targetDate;
  final bool archived;
  final DateTime createdAt;

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'name': name,
    'kind': kind.name,
    'target_amount': targetAmount,
    'target_date': targetDate?.toUtc().toIso8601String(),
    'is_archived': archived ? 1 : 0,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory SavingsPot.fromRow(Map<String, Object?> row) => SavingsPot(
    id: row['id']! as String,
    name: row['name']! as String,
    kind: SavingsKind.fromStorage(row['kind']! as String),
    targetAmount: row['target_amount']! as int,
    targetDate: row['target_date'] == null
        ? null
        : DateTime.parse(row['target_date']! as String),
    archived: (row['is_archived']! as int) != 0,
    createdAt: DateTime.parse(row['created_at']! as String),
  );
}
