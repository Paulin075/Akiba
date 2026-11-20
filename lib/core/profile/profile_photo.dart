import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../security/aes_box.dart';

/// Erreur lisible autour de la photo de profil.
class ProfilePhotoException implements Exception {
  const ProfilePhotoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Photo de profil locale, chiffrée sur l'appareil.
///
/// L'image est encodée en base64 puis chiffrée en **AES-256-GCM** avec une clé
/// maîtresse conservée par le coffre du système. Le fichier écrit dans le
/// dossier de l'application ne contient donc aucun pixel lisible, et l'image
/// n'est jamais envoyée sur le réseau ni incluse dans une sauvegarde.
class ProfilePhotoStore {
  ProfilePhotoStore({this.storage = const FlutterSecureStorage()});

  final FlutterSecureStorage storage;

  /// Une photo au-delà de 4 Mo est refusée : inutile pour un avatar.
  static const int maxBytes = 4 * 1024 * 1024;

  static const String _keyName = 'akiba_profile_photo_key';

  SecureMasterKey get _master => SecureMasterKey(storage, _keyName);

  Future<File> _file() async {
    final Directory base = await getApplicationSupportDirectory();
    final Directory directory = Directory(p.join(base.path, 'profile'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, 'avatar.sealed'));
  }

  /// Relit la photo ; `null` si absente, illisible ou déchiffrement impossible.
  Future<Uint8List?> load() async {
    try {
      final File file = await _file();
      if (!await file.exists()) return null;
      final String sealed = await file.readAsString();
      final List<int> key = await _master.read();
      if (key.isEmpty) return null;
      final String? clear = await AesBox.open(sealed, key);
      if (clear == null) return null;
      return base64Decode(clear);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const ProfilePhotoException('Cette image est vide.');
    }
    if (bytes.length > maxBytes) {
      throw const ProfilePhotoException(
        'Image trop lourde (4 Mo maximum). Choisissez une photo plus légère.',
      );
    }
    final List<int> key;
    try {
      key = await _master.read(create: true);
    } on SecureKeyException catch (error) {
      throw ProfilePhotoException(error.message);
    }
    final String sealed = await AesBox.seal(base64Encode(bytes), key);
    final File file = await _file();
    await file.writeAsString(sealed, flush: true);
  }

  Future<void> clear() async {
    try {
      final File file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Rien à effacer : l'avatar par défaut reprend sa place.
    }
    await _master.delete();
  }
}

/// Photo de profil partagée par l'en-tête, le Profil et l'écran de verrou.
///
/// Les écrans lisent [bytes] : `null` affiche l'avatar par défaut (initiale du
/// prénom, ou silhouette). Aucun accès disque n'est fait au moment du rendu.
class ProfilePhotoController extends ChangeNotifier {
  ProfilePhotoController(this._store);

  final ProfilePhotoStore _store;

  Uint8List? _bytes;

  Uint8List? get bytes => _bytes;

  bool get hasPhoto => _bytes != null;

  Future<void> load() async {
    _bytes = await _store.load();
    notifyListeners();
  }

  Future<void> update(Uint8List bytes) async {
    await _store.save(bytes);
    _bytes = bytes;
    notifyListeners();
  }

  Future<void> remove() async {
    await _store.clear();
    _bytes = null;
    notifyListeners();
  }
}

/// Accès à la photo de profil depuis n'importe quel écran.
class ProfilePhotoScope extends InheritedNotifier<ProfilePhotoController> {
  const ProfilePhotoScope({
    super.key,
    required ProfilePhotoController photo,
    required super.child,
  }) : super(notifier: photo);

  static ProfilePhotoController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProfilePhotoScope>()?.notifier;
}
