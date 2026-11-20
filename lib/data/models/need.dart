/// Priorité d'un besoin.
enum NeedPriority {
  high(1, 'Haute'),
  medium(2, 'Moyenne'),
  low(3, 'Basse');

  const NeedPriority(this.value, this.label);

  /// Valeur stockée en base (1 = haute).
  final int value;
  final String label;

  static NeedPriority fromStorage(int value) {
    for (final NeedPriority priority in values) {
      if (priority.value == value) return priority;
    }
    return medium;
  }
}

/// Besoin à financer, priorisé selon le solde disponible.
class Need {
  const Need({
    required this.id,
    required this.label,
    required this.amount,
    required this.createdAt,
    this.priority = NeedPriority.medium,
    this.dueDate,
    this.isSettled = false,
  }) : assert(amount > 0, 'Un besoin doit avoir un montant positif');

  final String id;
  final String label;

  /// Montant nécessaire en FCFA entiers.
  final int amount;

  final NeedPriority priority;
  final DateTime? dueDate;
  final bool isSettled;
  final DateTime createdAt;

  Need copyWith({bool? isSettled}) => Need(
    id: id,
    label: label,
    amount: amount,
    priority: priority,
    dueDate: dueDate,
    isSettled: isSettled ?? this.isSettled,
    createdAt: createdAt,
  );

  /// Un besoin est payable si son montant tient dans la capacité d'achat
  /// (solde disponible − réserve de sécurité).
  bool isAffordable(int capacity) => isSettled || amount <= capacity;

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'label': label,
    'amount': amount,
    'priority': priority.value,
    'due_date': dueDate?.toUtc().toIso8601String(),
    'is_settled': isSettled ? 1 : 0,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory Need.fromRow(Map<String, Object?> row) => Need(
    id: row['id']! as String,
    label: row['label']! as String,
    amount: row['amount']! as int,
    priority: NeedPriority.fromStorage(row['priority']! as int),
    dueDate: row['due_date'] == null
        ? null
        : DateTime.parse(row['due_date']! as String),
    isSettled: (row['is_settled']! as int) != 0,
    createdAt: DateTime.parse(row['created_at']! as String),
  );
}
