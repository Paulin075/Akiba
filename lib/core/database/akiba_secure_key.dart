import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Clé AES-256 de la base locale.
///
/// La clé est générée aléatoirement sur l'appareil puis conservée dans le
/// stockage sécurisé du système (Keystore Android, DPAPI/Credential Manager
/// Windows). Elle ne transite jamais par un fichier du projet ni par un journal.
class AkibaSecureKey {
  AkibaSecureKey({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _storageKey = 'akiba.db.key.v1';

  /// Longueur d'une clé AES-256 exprimée en caractères hexadécimaux.
  static const int keyHexLength = 64;

  final FlutterSecureStorage _storage;

  /// Lit la clé existante ou en crée une nouvelle, sans jamais la journaliser.
  Future<String> databaseKey() async {
    final String? existing = await _storage.read(key: _storageKey);
    if (existing != null && isHexKey(existing)) return existing;

    final String generated = generateHexKey();
    await _storage.write(key: _storageKey, value: generated);
    return generated;
  }

  /// Vrai si [value] est une clé hexadécimale de 256 bits.
  static bool isHexKey(String value) {
    if (value.length != keyHexLength) return false;
    return RegExp(r'^[0-9a-f]+$').hasMatch(value);
  }

  /// Génère 32 octets aléatoires cryptographiques en hexadécimal.
  static String generateHexKey() {
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 32; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
