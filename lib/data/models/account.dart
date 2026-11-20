import 'account_brand.dart';

/// Compte support (Liquide, Flooz, Mixx by Yas, Orabank).
///
/// Le solde n'est **jamais** stocké sur le compte : il est toujours dérivé des
/// transactions (voir `v_account_balances` et `AccountBalance`).
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.brand,
    required this.createdAt,
    this.archived = false,
  });

  final String id;
  final String name;
  final AccountBrand brand;
  final bool archived;
  final DateTime createdAt;

  Account copyWith({String? name, AccountBrand? brand, bool? archived}) {
    return Account(
      id: id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      archived: archived ?? this.archived,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'name': name,
    'brand': brand.name,
    'is_archived': archived ? 1 : 0,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory Account.fromRow(Map<String, Object?> row) => Account(
    id: row['id']! as String,
    name: row['name']! as String,
    brand: AccountBrand.fromStorage(row['brand']! as String),
    archived: (row['is_archived']! as int) != 0,
    createdAt: DateTime.parse(row['created_at']! as String),
  );
}

/// Solde d'un compte, calculé à la lecture.
class AccountBalance {
  const AccountBalance({required this.account, required this.balance});

  final Account account;

  /// Somme signée des transactions du compte, en FCFA entiers.
  final int balance;
}
