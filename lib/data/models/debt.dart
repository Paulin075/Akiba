/// Sens d'une créance ou d'une dette.
enum DebtDirection {
  /// On me doit (créance).
  owedToMe,

  /// Je dois (dette).
  iOwe;

  static DebtDirection fromStorage(String value) {
    for (final DebtDirection direction in values) {
      if (direction.name == value) return direction;
    }
    return iOwe;
  }
}

/// État affiché d'une créance ou d'une dette.
///
/// L'ordre de priorité est : soldé, en retard, partiellement remboursé,
/// en cours. Un retard prime sur un remboursement partiel, parce que c'est
/// l'information utile pour agir.
enum DebtStatus {
  ongoing('En cours'),
  partiallySettled('Partiellement remboursé'),
  settled('Soldé'),
  overdue('En retard');

  const DebtStatus(this.label);

  final String label;
}

/// Créance (« on me doit ») ou dette (« je dois »).
class Debt {
  const Debt({
    required this.id,
    required this.direction,
    required this.counterparty,
    required this.principal,
    required this.createdAt,
    this.settledAmount = 0,
    this.dueDate,
    this.note,
  }) : assert(principal > 0, 'Le montant initial doit être positif'),
       assert(settledAmount >= 0, 'Le montant réglé ne peut pas être négatif');

  final String id;
  final DebtDirection direction;

  /// Nom du tiers concerné.
  final String counterparty;

  /// Montant initial en FCFA entiers.
  final int principal;

  /// Montant déjà réglé en FCFA entiers.
  final int settledAmount;

  final DateTime? dueDate;
  final String? note;
  final DateTime createdAt;

  /// Reste dû, jamais négatif.
  int get remaining {
    final int rest = principal - settledAmount;
    return rest < 0 ? 0 : rest;
  }

  bool get isSettled => remaining == 0;

  /// Pourcentage remboursé (0 à 100), sans division par zéro.
  int get progressPercent =>
      principal <= 0 ? 0 : ((settledAmount * 100) ~/ principal).clamp(0, 100);

  /// État à la date [now] : l'échéance est comparée au jour, pas à l'heure.
  DebtStatus statusAt(DateTime now) {
    if (isSettled) return DebtStatus.settled;
    final DateTime? due = dueDate;
    if (due != null) {
      final DateTime limit = DateTime(due.year, due.month, due.day);
      final DateTime today = DateTime(now.year, now.month, now.day);
      if (limit.isBefore(today)) return DebtStatus.overdue;
    }
    if (settledAmount > 0) return DebtStatus.partiallySettled;
    return DebtStatus.ongoing;
  }

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'direction': direction.name,
    'counterparty': counterparty,
    'principal': principal,
    'settled_amount': settledAmount,
    'due_date': dueDate?.toUtc().toIso8601String(),
    'note': note,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory Debt.fromRow(Map<String, Object?> row) => Debt(
    id: row['id']! as String,
    direction: DebtDirection.fromStorage(row['direction']! as String),
    counterparty: row['counterparty']! as String,
    principal: row['principal']! as int,
    settledAmount: row['settled_amount']! as int,
    dueDate: row['due_date'] == null
        ? null
        : DateTime.parse(row['due_date']! as String),
    note: row['note'] as String?,
    createdAt: DateTime.parse(row['created_at']! as String),
  );
}
