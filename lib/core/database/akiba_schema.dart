import 'package:sqlite3/sqlite3.dart';

/// Schéma SQLite d'AKIBA, versionné par `PRAGMA user_version`.
///
/// Toutes les tables sont créées dans une base déjà chiffrée par SQLCipher
/// (AES-256). Les soldes ne sont jamais stockés : la vue
/// `v_account_balances` les recalcule à partir des transactions.
abstract final class AkibaSchema {
  /// Version courante du schéma.
  static const int version = 3;

  /// Applique les migrations manquantes (idempotent).
  static void migrate(Database db) {
    final int current = _userVersion(db);
    if (current >= version) return;

    if (current < 1) {
      db.execute('''
        CREATE TABLE third_parties (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          note TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      db.execute('''
        CREATE TABLE savings_pots (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          kind TEXT NOT NULL,
          target_amount INTEGER NOT NULL DEFAULT 0 CHECK (target_amount >= 0),
          target_date TEXT,
          is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
          created_at TEXT NOT NULL
        )
      ''');
      db.execute('''
        CREATE TABLE accounts (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          brand TEXT NOT NULL,
          is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
          created_at TEXT NOT NULL
        )
      ''');
      db.execute('''
        CREATE TABLE transactions (
          id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          amount INTEGER NOT NULL CHECK (amount <> 0),
          kind TEXT NOT NULL,
          category TEXT,
          note TEXT,
          occurred_at TEXT NOT NULL,
          is_neutral INTEGER NOT NULL DEFAULT 0 CHECK (is_neutral IN (0, 1)),
          third_party_id TEXT REFERENCES third_parties(id) ON DELETE SET NULL,
          transfer_account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
          savings_pot_id TEXT REFERENCES savings_pots(id) ON DELETE SET NULL,
          created_at TEXT NOT NULL
        )
      ''');
      db.execute('''
        CREATE TABLE debts (
          id TEXT PRIMARY KEY,
          direction TEXT NOT NULL,
          counterparty TEXT NOT NULL,
          principal INTEGER NOT NULL CHECK (principal > 0),
          settled_amount INTEGER NOT NULL DEFAULT 0 CHECK (settled_amount >= 0),
          due_date TEXT,
          note TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      db.execute('''
        CREATE TABLE settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

      db.execute(
        'CREATE INDEX idx_transactions_occurred '
        'ON transactions(occurred_at DESC)',
      );
      db.execute(
        'CREATE INDEX idx_transactions_account '
        'ON transactions(account_id, occurred_at DESC)',
      );
      db.execute(
        'CREATE INDEX idx_transactions_category '
        'ON transactions(category) WHERE category IS NOT NULL',
      );
      db.execute(
        'CREATE INDEX idx_transactions_neutral '
        'ON transactions(is_neutral) WHERE is_neutral = 1',
      );
      db.execute(
        'CREATE INDEX idx_transactions_savings '
        'ON transactions(savings_pot_id) WHERE savings_pot_id IS NOT NULL',
      );
      db.execute('CREATE INDEX idx_debts_direction ON debts(direction)');

      // Soldes toujours dérivés : aucune colonne « solde » modifiable.
      db.execute('''
        CREATE VIEW v_account_balances AS
        SELECT
          a.id AS id,
          a.name AS name,
          a.brand AS brand,
          a.is_archived AS is_archived,
          a.created_at AS created_at,
          COALESCE(SUM(t.amount), 0) AS balance
        FROM accounts a
        LEFT JOIN transactions t ON t.account_id = a.id
        GROUP BY a.id
      ''');
    }

    if (current < 2) {
      // Plafonds de budget mensuels, une ligne par catégorie.
      db.execute('''
        CREATE TABLE budgets (
          id TEXT PRIMARY KEY,
          category TEXT NOT NULL,
          monthly_limit INTEGER NOT NULL CHECK (monthly_limit > 0),
          created_at TEXT NOT NULL,
          UNIQUE (category)
        )
      ''');
    }

    if (current < 3) {
      // Besoins priorisés : le seuil de « payable » est calculé à la lecture.
      db.execute('''
        CREATE TABLE needs (
          id TEXT PRIMARY KEY,
          label TEXT NOT NULL,
          amount INTEGER NOT NULL CHECK (amount > 0),
          priority INTEGER NOT NULL DEFAULT 2 CHECK (priority BETWEEN 1 AND 3),
          due_date TEXT,
          is_settled INTEGER NOT NULL DEFAULT 0 CHECK (is_settled IN (0, 1)),
          created_at TEXT NOT NULL
        )
      ''');
    }

    db.execute('PRAGMA user_version = $version');
  }

  static int _userVersion(Database db) {
    final ResultSet rows = db.select('PRAGMA user_version');
    if (rows.isEmpty) return 0;
    final Object? value = rows.first.values.first;
    return value is int ? value : 0;
  }
}
