import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../security/aes_box.dart';
import '../state/akiba_settings.dart';

/// Erreur lisible du coffre de clé (jamais le secret lui-même).
class AiKeyException implements Exception {
  const AiKeyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Coffre local de la clé API du fournisseur de modèles.
///
/// Deux couches : la clé est chiffrée en AES-256-GCM avec une clé maîtresse
/// aléatoire, et cette clé maîtresse vit dans le stockage sécurisé du système
/// (Keystore Android / DPAPI Windows), jamais dans la base.
///
/// La valeur chiffrée (`nonce.mac.chiffré`, base64) est la seule chose écrite
/// dans les réglages, donc dans la base SQLCipher. L'interface ne montre jamais
/// la clé en clair : ni dans un champ, ni dans un message, ni dans un journal.
class AiKeyVault {
  AiKeyVault(this._settings, {this.storage = const FlutterSecureStorage()});

  final AkibaSettings _settings;
  final FlutterSecureStorage storage;

  /// Clé de réglage qui porte la valeur chiffrée.
  static const String sealedSetting = 'ai_api_key_sealed';

  /// Date de dernier remplacement.
  static const String updatedSetting = 'ai_api_key_updated_at';

  /// Libellé affiché à la place de la clé.
  static const String maskedLabel = '••••••••';

  SecureMasterKey get _master =>
      SecureMasterKey(storage, 'akiba_ai_master_key');

  bool get isConfigured => _settings.raw(sealedSetting).isNotEmpty;

  DateTime? get updatedAt => DateTime.tryParse(_settings.raw(updatedSetting));

  /// Contrôle de forme, sans réseau : ne prouve pas que la clé est valide.
  static String? validate(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return 'Collez la clé fournie par le service de modèles.';
    }
    if (value.length < 20) return 'Cette clé semble trop courte.';
    if (value.length > 400) return 'Cette clé semble trop longue.';
    if (RegExp(r'\s').hasMatch(value)) {
      return 'La clé ne doit contenir aucun espace.';
    }
    return null;
  }

  /// Chiffre [plain] avec une clé maîtresse de 32 octets.
  ///
  /// Fonction pure, testable sans greffon système.
  static Future<String> seal(String plain, List<int> masterKey) =>
      AesBox.seal(plain, masterKey);

  /// Déchiffre une valeur produite par [seal] ; `null` si altérée ou étrangère.
  static Future<String?> open(String sealed, List<int> masterKey) =>
      AesBox.open(sealed, masterKey);

  /// Enregistre (ou remplace) la clé : chiffrement puis écriture des réglages.
  Future<void> save(String raw) async {
    final String? problem = validate(raw);
    if (problem != null) throw AiKeyException(problem);
    final List<int> master = await _readMaster(create: true);
    await _settings.set(sealedSetting, await AesBox.seal(raw.trim(), master));
    await _settings.set(updatedSetting, DateTime.now().toIso8601String());
  }

  /// Relit la clé en clair pour un appel réseau. `null` si absente ou illisible.
  Future<String?> read() async {
    final String sealed = _settings.raw(sealedSetting);
    if (sealed.isEmpty) return null;
    final List<int> master = await _readMaster();
    if (master.isEmpty) return null;
    return AesBox.open(sealed, master);
  }

  /// Efface la clé chiffrée et la clé maîtresse.
  Future<void> clear() async {
    await _settings.set(sealedSetting, '');
    await _settings.set(updatedSetting, '');
    await _master.delete();
  }

  Future<List<int>> _readMaster({bool create = false}) async {
    try {
      return await _master.read(create: create);
    } on SecureKeyException catch (error) {
      throw AiKeyException(error.message);
    }
  }
}
