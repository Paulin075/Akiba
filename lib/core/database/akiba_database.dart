import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'akiba_schema.dart';
import 'akiba_secure_key.dart';

/// Ouverture de la base SQLite locale **chiffrée** (SQLCipher, AES-256).
///
/// Le paquet `sqlite3` est compilé avec la source `sqlcipher` déclarée dans les
/// `hooks` de `pubspec.yaml` : `PRAGMA key` chiffre réellement le fichier, qui
/// reste illisible sans la clé conservée dans le stockage sécurisé.
abstract final class AkibaDatabase {
  static const String fileName = 'akiba.db';

  /// Dernière base ouverte : permet un arrêt propre de l'application.
  static Database? _current;

  /// Ouvre (ou crée) la base dans le dossier de données de l'application.
  static Future<Database> open({AkibaSecureKey? keyStore}) async {
    final Directory directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final String key = await (keyStore ?? AkibaSecureKey()).databaseKey();
    return openEncrypted(p.join(directory.path, fileName), keyHex: key);
  }

  /// Ouvre un fichier chiffré avec [keyHex] et applique les migrations.
  ///
  /// Exposé pour les tests et pour la restauration d'une sauvegarde.
  static Database openEncrypted(String path, {required String keyHex}) {
    if (!AkibaSecureKey.isHexKey(keyHex)) {
      throw ArgumentError.value(
        keyHex,
        'keyHex',
        'La clé doit être hexadécimale sur 256 bits',
      );
    }

    final Database db = sqlite3.open(path);
    try {
      // Clé brute : SQLCipher n'applique pas de dérivation supplémentaire.
      db.execute('PRAGMA key = "x\'$keyHex\'"');
      db.execute('PRAGMA cipher_memory_security = ON');
      db.execute('PRAGMA foreign_keys = ON');
      db.execute('PRAGMA journal_mode = WAL');
      // Toute lecture échoue si la clé est fausse ou si le fichier est corrompu.
      db.select('SELECT count(*) FROM sqlite_master');
      AkibaSchema.migrate(db);
      _current = db;
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// Contrôle d'intégrité **non bloquant** (appelé après le démarrage).
  ///
  /// Seul le résultat (`ok` ou non) est journalisé : aucun contenu.
  static Future<void> integrityCheck() async {
    final Database? db = _current;
    if (db == null) return;
    try {
      final ResultSet rows = db.select('PRAGMA quick_check');
      final String result = rows.isEmpty
          ? 'inconnu'
          : '${rows.first.values.first}';
      if (result != 'ok') {
        debugPrint('AKIBA : contrôle d’intégrité non concluant.');
      }
    } catch (error) {
      debugPrint('AKIBA : contrôle d’intégrité (${error.runtimeType}).');
    }
  }

  /// Checkpoint WAL puis fermeture, sur demande de l'OS.
  static void close() {
    final Database? db = _current;
    if (db == null) return;
    try {
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // La fermeture reste possible même si le checkpoint échoue.
    }
    try {
      db.close();
    } catch (_) {
      // Déjà fermée.
    }
    _current = null;
  }
}
