/// Nature d'un mouvement.
enum TransactionKind {
  /// Entrée d'argent (salaire, dépôt, cadeau…).
  income,

  /// Sortie d'argent (dépense, retrait…).
  expense,

  /// Transfert entre deux comptes de l'utilisateur.
  transfer,

  /// Transaction d'ouverture : matérialise un solde de départ.
  opening,

  /// Versement (négatif) ou retrait (positif) du coffre épargne.
  savings;

  static TransactionKind fromStorage(String value) {
    for (final TransactionKind kind in values) {
      if (kind.name == value) return kind;
    }
    return expense;
  }
}

/// Mouvement financier d'un compte.
///
/// [amount] est signé, en FCFA entiers : positif quand l'argent entre sur le
/// compte, négatif quand il en sort. Une transaction neutre
/// ([isNeutral] = vrai) est de l'argent de tiers : elle traverse les comptes
/// mais n'appartient pas à l'utilisateur.
class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.accountId,
    required this.amount,
    required this.kind,
    required this.occurredAt,
    required this.createdAt,
    this.category,
    this.note,
    this.isNeutral = false,
    this.thirdPartyId,
    this.transferAccountId,
    this.savingsPotId,
  }) : assert(amount != 0, 'Un mouvement ne peut pas valoir 0 FCFA');

  final String id;
  final String accountId;

  /// Montant signé en FCFA entiers.
  final int amount;

  final TransactionKind kind;

  /// Libellé de catégorie libre (la table des catégories arrive en Phase 4).
  final String? category;

  final String? note;
  final DateTime occurredAt;
  final DateTime createdAt;

  /// Vrai pour une entrée ou un reversement d'argent de tiers.
  final bool isNeutral;

  /// Tiers concerné (client, proche) quand [isNeutral] est vrai.
  final String? thirdPartyId;

  /// Compte crédité/débité en face d'un transfert.
  final String? transferAccountId;

  /// Coffre épargne concerné.
  final String? savingsPotId;

  /// Vrai si le mouvement entre dans le budget, l'épargne et les statistiques.
  bool get countsForBudget =>
      !isNeutral &&
      kind != TransactionKind.savings &&
      kind != TransactionKind.opening;

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'account_id': accountId,
    'amount': amount,
    'kind': kind.name,
    'category': category,
    'note': note,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'is_neutral': isNeutral ? 1 : 0,
    'third_party_id': thirdPartyId,
    'transfer_account_id': transferAccountId,
    'savings_pot_id': savingsPotId,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory TransactionRecord.fromRow(Map<String, Object?> row) =>
      TransactionRecord(
        id: row['id']! as String,
        accountId: row['account_id']! as String,
        amount: row['amount']! as int,
        kind: TransactionKind.fromStorage(row['kind']! as String),
        category: row['category'] as String?,
        note: row['note'] as String?,
        occurredAt: DateTime.parse(row['occurred_at']! as String),
        isNeutral: (row['is_neutral']! as int) != 0,
        thirdPartyId: row['third_party_id'] as String?,
        transferAccountId: row['transfer_account_id'] as String?,
        savingsPotId: row['savings_pot_id'] as String?,
        createdAt: DateTime.parse(row['created_at']! as String),
      );
}
