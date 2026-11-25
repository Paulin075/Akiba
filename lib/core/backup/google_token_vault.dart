import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Coffre du système réduit aux trois opérations utiles à Google.
///
/// Cette abstraction permet de tester les deux branches de connexion (Android
/// et ordinateur) sans greffon natif. Aucun jeton n'est jamais écrit ailleurs
/// que dans le coffre : pas de base, pas de fichier, pas de journal.
abstract interface class GoogleTokenVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Coffre réel : Keystore Android, DPAPI / Credential Manager Windows.
class SecureGoogleTokenVault implements GoogleTokenVault {
  const SecureGoogleTokenVault([this.storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}
