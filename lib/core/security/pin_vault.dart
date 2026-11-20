import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../data/akiba_store.dart';

/// Coffre du code PIN.
///
/// Le PIN n'est **jamais** stocké : seule une empreinte SHA-256 salée et
/// itérée est conservée dans la base chiffrée. Le sel est aléatoire (128 bits).
class PinVault {
  PinVault(this._store);

  final AkibaStore _store;

  static const int iterations = 20000;

  /// Un PIN trivial (0000, 1234, 1111…) est refusé.
  static bool isTrivial(String pin) {
    if (pin.length < 4) return true;
    if (pin.split('').every((String c) => c == pin[0])) return true;
    const List<String> sequences = <String>['0123456789', '9876543210'];
    for (final String sequence in sequences) {
      if (sequence.contains(pin)) return true;
    }
    return false;
  }

  static String _generateSalt() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Empreinte hexadécimale du PIN pour un sel donné (fonction pure, testée).
  static String hashPin(String pin, String saltHex, {int rounds = iterations}) {
    final List<int> salt = <int>[
      for (int i = 0; i + 1 < saltHex.length; i += 2)
        int.parse(saltHex.substring(i, i + 2), radix: 16),
    ];
    List<int> current = <int>[...salt, ...utf8.encode(pin)];
    for (int round = 0; round < rounds; round++) {
      current = sha256.convert(<int>[
        ...salt,
        ...current,
        ...utf8.encode(pin),
      ]).bytes;
    }
    return current.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<bool> isConfigured() async {
    try {
      return ((await _store.setting('pin_hash')) ?? '').isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Définit (ou remplace) le PIN.
  Future<void> setPin(String pin) async {
    if (pin.length < 4 || pin.length > 6) {
      throw ArgumentError('Le PIN doit contenir 4 à 6 chiffres');
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError('Le PIN ne contient que des chiffres');
    }
    if (isTrivial(pin)) {
      throw ArgumentError('Ce PIN est trop facile à deviner');
    }
    final String salt = _generateSalt();
    await _store.setSetting('pin_salt', salt);
    await _store.setSetting('pin_hash', hashPin(pin, salt));
  }

  Future<bool> verify(String pin) async {
    final String? hash = await _store.setting('pin_hash');
    final String? salt = await _store.setting('pin_salt');
    if (hash == null || salt == null || hash.isEmpty) return false;
    return hashPin(pin, salt) == hash;
  }

  Future<void> clear(AkibaStore store) async {
    await store.setSetting('pin_hash', '');
    await store.setSetting('pin_salt', '');
  }
}
