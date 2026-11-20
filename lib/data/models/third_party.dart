/// Tiers accompagné du montant détenu pour lui (entrées neutres − reversements).
class ThirdPartyBalance {
  const ThirdPartyBalance({required this.name, required this.held, this.id});

  final String? id;
  final String name;

  /// Montant en FCFA entiers qui ne lui appartient pas encore.
  final int held;
}

/// Personne ou entité dont l'argent transite par les comptes (tiers).
class ThirdParty {
  const ThirdParty({
    required this.id,
    required this.name,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String name;
  final String? note;
  final DateTime createdAt;

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'name': name,
    'note': note,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory ThirdParty.fromRow(Map<String, Object?> row) => ThirdParty(
    id: row['id']! as String,
    name: row['name']! as String,
    note: row['note'] as String?,
    createdAt: DateTime.parse(row['created_at']! as String),
  );
}
