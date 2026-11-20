import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Erreur du coffre système (jamais le secret lui-même).
class SecureKeyException implements Exception {
  const SecureKeyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Chiffrement authentifié AES-256-GCM d'une chaîne.
///
/// Une seule implémentation, partagée par la clé API (cf. `AiKeyVault`) et par
/// la photo de profil (cf. `ProfilePhotoStore`) : pas de crypto dupliquée.
abstract final class AesBox {
  static const int keyLength = 32;

  static final AesGcm _cipher = AesGcm.with256bits();

  /// Format : `base64(nonce).base64(mac).base64(chiffré)`.
  static Future<String> seal(String plain, List<int> key) async {
    final SecretBox box = await _cipher.encrypt(
      utf8.encode(plain),
      secretKey: SecretKey(key),
    );
    return <String>[
      base64Encode(box.nonce),
      base64Encode(box.mac.bytes),
      base64Encode(box.cipherText),
    ].join('.');
  }

  /// Renvoie `null` si la valeur est altérée ou chiffrée avec une autre clé.
  static Future<String?> open(String sealed, List<int> key) async {
    final List<String> parts = sealed.split('.');
    if (parts.length != 3) return null;
    try {
      final SecretBox box = SecretBox(
        base64Decode(parts[2]),
        nonce: base64Decode(parts[0]),
        mac: Mac(base64Decode(parts[1])),
      );
      final List<int> clear = await _cipher.decrypt(
        box,
        secretKey: SecretKey(key),
      );
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }
}

/// Clé maîtresse aléatoire de 32 octets, conservée par le coffre du système
/// (Keystore Android / DPAPI Windows) et jamais écrite en base.
class SecureMasterKey {
  const SecureMasterKey(this.storage, this.name);

  final FlutterSecureStorage storage;
  final String name;

  /// Relit la clé ; en crée une si [create] et qu'aucune n'existe encore.
  ///
  /// Renvoie une liste vide quand aucune clé n'est enregistrée et que
  /// [create] est faux.
  Future<List<int>> read({bool create = false}) async {
    String? stored;
    try {
      stored = await storage.read(key: name);
    } catch (_) {
      throw const SecureKeyException(
        'Le stockage sécurisé du système est indisponible : la clé ne peut pas '
        'être protégée sur cet appareil.',
      );
    }
    if (stored != null && stored.length == AesBox.keyLength * 2) {
      final List<int>? decoded = _decode(stored);
      if (decoded != null) return decoded;
    }
    if (!create) return const <int>[];

    final Random random = Random.secure();
    final List<int> fresh = List<int>.generate(
      AesBox.keyLength,
      (_) => random.nextInt(256),
    );
    try {
      await storage.write(key: name, value: _encode(fresh));
    } catch (_) {
      throw const SecureKeyException(
        'Le stockage sécurisé du système est indisponible : la clé ne peut pas '
        'être protégée sur cet appareil.',
      );
    }
    return fresh;
  }

  Future<void> delete() async {
    try {
      await storage.delete(key: name);
    } catch (_) {
      // Rien à effacer ou stockage indisponible : la valeur chiffrée reste
      // inutilisable sans cette clé.
    }
  }

  static String _encode(List<int> bytes) =>
      bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int>? _decode(String hex) {
    try {
      return <int>[
        for (int i = 0; i + 1 < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
    } catch (_) {
      return null;
    }
  }
}
