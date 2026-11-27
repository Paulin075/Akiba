import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Code de sauvegarde à **4 chiffres** du serveur Home Lab.
///
/// Il remplace le compte Google pour les sauvegardes déposées sur le serveur
/// personnel : il est demandé une fois à la configuration, puis à chaque
/// restauration sur un autre appareil. Le code n'est jamais écrit dans la base
/// de réglages : il vit dans le coffre du système (Keystore Android / DPAPI
/// Windows), comme le jeton du serveur.
///
/// Oublié, il ne peut pas être retrouvé : la sauvegarde du serveur doit alors
/// être écrasée par une nouvelle sauvegarde portant un nouveau code, et la
/// personne repart de zéro.
abstract interface class BackupCodeStore {
  Future<String> read();

  Future<void> write(String code);

  Future<void> delete();
}

/// Coffre réel : `flutter_secure_storage`.
class SecureBackupCodeStore implements BackupCodeStore {
  const SecureBackupCodeStore([this.storage = const FlutterSecureStorage()]);

  static const String keyName = 'akiba_backup_code';

  final FlutterSecureStorage storage;

  @override
  Future<String> read() async {
    try {
      final String? value = await storage.read(key: keyName);
      return normalizeBackupCode(value ?? '');
    } catch (_) {
      return '';
    }
  }

  @override
  Future<void> write(String code) =>
      storage.write(key: keyName, value: normalizeBackupCode(code));

  @override
  Future<void> delete() => storage.delete(key: keyName);
}

/// Coffre en mémoire, réservé aux tests : aucun greffon natif.
class InMemoryBackupCodeStore implements BackupCodeStore {
  InMemoryBackupCodeStore([this._code = '']);

  String _code;

  @override
  Future<String> read() async => _code;

  @override
  Future<void> write(String code) async => _code = normalizeBackupCode(code);

  @override
  Future<void> delete() async => _code = '';
}

/// Retire les espaces de saisie sans jamais compléter ni tronquer le code.
String normalizeBackupCode(String raw) => raw.replaceAll(RegExp(r'\s'), '');

/// Vrai pour exactement quatre chiffres.
bool isValidBackupCode(String code) =>
    RegExp(r'^\d{4}$').hasMatch(normalizeBackupCode(code));

/// Libellé sûr pour les messages : jamais le code lui-même.
String backupCodeHint(String code) =>
    isValidBackupCode(code) ? '•••• (4 chiffres)' : 'aucun code';
