import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/akiba_store.dart';
import '../../data/models/account.dart';
import '../../data/models/budget.dart';
import '../../data/models/debt.dart';
import '../../data/models/need.dart';
import '../../data/models/savings_pot.dart';
import '../../data/models/third_party.dart';
import '../../data/models/transaction_record.dart';
import '../security/aes_box.dart';
import '../state/akiba_settings.dart';
import 'backup_code.dart';
import 'google_account.dart';

/// Étapes d'une sauvegarde ou d'une restauration, pour l'animation de suivi.
enum BackupStage {
  idle,
  preparing,
  encrypting,
  uploading,
  downloading,
  decrypting,
  verifying,
  done,
}

/// Libellé court d'une étape (aucune donnée financière).
String backupStageLabel(BackupStage stage) => switch (stage) {
  BackupStage.idle => 'Prêt',
  BackupStage.preparing => 'Préparation des données',
  BackupStage.encrypting => 'Chiffrement AES-256-GCM',
  BackupStage.uploading => 'Envoi de la sauvegarde',
  BackupStage.downloading => 'Téléchargement de la sauvegarde',
  BackupStage.decrypting => 'Déchiffrement AES-256-GCM',
  BackupStage.verifying => 'Vérification d’intégrité',
  BackupStage.done => 'Terminé',
};

/// Sauvegarde et synchronisation chiffrées.
///
/// **Aucune phrase secrète** : le contenu est sérialisé en JSON puis chiffré en
/// **AES-256-GCM** avec une clé de 256 bits conservée dans le coffre du système
/// (Keystore Android / DPAPI Windows). L'enveloppe ne contient en clair que des
/// métadonnées non sensibles (date, appareil, compteurs, empreinte SHA-256).
/// Résultat d'un test de connexion au Home Lab.
class HomeLabProbe {
  const HomeLabProbe({
    required this.reachable,
    required this.authenticated,
    required this.message,
    this.statusCode,
    this.latency,
  });

  final bool reachable;
  final bool authenticated;
  final String message;
  final int? statusCode;

  /// Temps de réponse mesuré (aller-retour HTTP), quand le serveur a répondu.
  final Duration? latency;

  bool get ok => reachable && authenticated;

  /// Latence lisible : `18 ms`.
  String get latencyLabel =>
      latency == null ? '' : '${latency!.inMilliseconds} ms';
}

class BackupService {
  BackupService(
    this._store, [
    this._directory,
    this._storage = const FlutterSecureStorage(),
    List<int>? keyOverride,
  ]) : _keyOverride = keyOverride;

  /// Variante de test : clé AES-256 fournie en mémoire (aucun coffre système).
  BackupService.withKey(this._store, List<int> key)
    : _directory = null,
      _storage = const FlutterSecureStorage(),
      _keyOverride = key;

  final AkibaStore _store;
  final Directory? _directory;
  final FlutterSecureStorage _storage;
  final List<int>? _keyOverride;

  static const int formatVersion = 4;
  static const int keyLength = 32;
  static const int _pbkdf2Iterations = 120000;
  static const String _applicationSalt = 'AKIBA|backup|AES-256-GCM|v3';
  static const String _keyName = 'akiba_backup_key';

  /// Réglages jamais sauvegardés ou jamais restaurés.
  static const Set<String> excludedSettings = <String>{
    'pin_hash',
    'pin_salt',
    'lab_token',
    'master_url',
    'master_token',
    'restore_pending_at',
    // Marqueur local d'une sauvegarde en attente : il ne doit jamais voyager
    // dans une enveloppe, sinon une restauration le recopierait.
    'auto_backup_pending_at',
    'ai_api_key_sealed',
    'ai_api_key_updated_at',
    'profile_photo_updated_at',
  };

  SecureMasterKey get _vault => SecureMasterKey(_storage, _keyName);

  Future<List<int>> _key({bool create = false}) async {
    final List<int>? override = _keyOverride;
    if (override != null) return override;
    try {
      return await _vault.read(create: create);
    } on SecureKeyException catch (error) {
      throw BackupException(error.message);
    }
  }

  Future<Directory> workDirectory() async {
    final Directory base =
        _directory ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'backups'),
        );
    await base.create(recursive: true);
    return base;
  }

  // ------------------------------------------------------------------ Créer

  /// Crée une enveloppe chiffrée.
  ///
  /// Trois dérivations possibles, dans cet ordre :
  /// 1. un **code à 4 chiffres** (serveur Home Lab) : la clé est dérivée du code
  ///    et d'un sel aléatoire, donc l'enveloppe se rouvre sur n'importe quel
  ///    appareil avec le même code, sans compte Google ;
  /// 2. le compte Google connecté (Drive), pour rester portable ;
  /// 3. la clé de l'appareil, quand aucune identité n'est disponible.
  Future<Map<String, dynamic>> createEnvelope({
    required String deviceId,
    GoogleAccount account = GoogleAccount.none,
    String code = '',
    void Function(BackupStage)? onStage,
  }) async {
    onStage?.call(BackupStage.preparing);
    final String backupCode = normalizeBackupCode(code);
    if (backupCode.isNotEmpty && !isValidBackupCode(backupCode)) {
      throw const BackupException(
        'Le code de sauvegarde doit comporter exactement 4 chiffres.',
      );
    }
    final Map<String, dynamic> payload = await collectPayload();
    final List<int> plain = utf8.encode(jsonEncode(payload));
    // Identité canonique : identifiant Google stable normalisé, à défaut
    // l'e-mail en minuscules. Elle sert seulement à dériver la clé et n'est
    // jamais écrite dans l'enveloppe.
    final List<String> identities = account.keyCandidates;
    final String identity = identities.isEmpty ? '' : identities.first;
    final bool perCode = backupCode.isNotEmpty;
    final bool perAccount =
        !perCode && identity.isNotEmpty && _keyOverride == null;
    final List<int> salt = (perCode || perAccount)
        ? List<int>.generate(16, (_) => Random.secure().nextInt(256))
        : const <int>[];
    final List<int> key = perCode
        ? _deriveKey(_codeIdentity(backupCode), salt)
        : perAccount
        ? _deriveKey(identity, salt)
        : await _key(create: true);
    if (key.length != keyLength) {
      throw const BackupException(
        'Clé de sauvegarde indisponible sur cet appareil.',
      );
    }

    onStage?.call(BackupStage.encrypting);
    final String sealed = await AesBox.seal(utf8.decode(plain), key);
    onStage?.call(BackupStage.verifying);

    return <String, dynamic>{
      'format': 'akiba-backup',
      'version': perCode ? 4 : (perAccount ? 3 : 2),
      'cipher': 'AES-256-GCM',
      'kdf': perCode
          ? 'PBKDF2-CODE'
          : (perAccount ? 'PBKDF2-HMAC-SHA256' : 'device-key'),
      if (salt.isNotEmpty) 'salt': base64Encode(salt),
      if (perAccount) 'account': account.toJson(),
      'keyId': hash.sha256.convert(key).toString().substring(0, 16),
      'ciphertext': sealed,
      'sha256': hash.sha256.convert(plain).toString(),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'deviceId': deviceId,
      'counts': payload['counts'],
      'lastMutationAt': payload['lastMutationAt'],
    };
  }

  Future<Map<String, dynamic>> collectPayload() async {
    final List<Account> accounts = await _store.accounts();
    final List<TransactionRecord> transactions = await _store.transactions(
      limit: 100000,
    );
    final List<SavingsPot> pots = await _store.savingsPots();
    final List<ThirdParty> parties = await _store.thirdParties();
    final List<Debt> debts = await _store.debts();
    final List<BudgetStatus> budgets = await _store.budgets();
    final List<Need> needs = await _store.needs();

    final Map<String, String> settings = <String, String>{};
    for (final String key in AkibaSettings.defaults.keys) {
      if (excludedSettings.contains(key)) continue;
      final String? value = await _store.setting(key);
      if (value != null) settings[key] = value;
    }
    final String? reserve = await _store.setting('reserve_securite');
    if (reserve != null) settings['reserve_securite'] = reserve;

    DateTime? lastMutation;
    for (final TransactionRecord record in transactions) {
      if (lastMutation == null || record.createdAt.isAfter(lastMutation)) {
        lastMutation = record.createdAt;
      }
    }

    return <String, dynamic>{
      'accounts': accounts.map((Account a) => a.toRow()).toList(),
      'transactions': transactions
          .map((TransactionRecord t) => t.toRow())
          .toList(),
      'savingsPots': pots.map((SavingsPot s) => s.toRow()).toList(),
      'thirdParties': parties.map((ThirdParty t) => t.toRow()).toList(),
      'debts': debts.map((Debt d) => d.toRow()).toList(),
      'budgets': budgets.map((BudgetStatus b) => b.budget.toRow()).toList(),
      'needs': needs.map((Need n) => n.toRow()).toList(),
      'settings': settings,
      'counts': <String, int>{
        'accounts': accounts.length,
        'transactions': transactions.length,
        'savingsPots': pots.length,
        'thirdParties': parties.length,
        'debts': debts.length,
        'budgets': budgets.length,
        'needs': needs.length,
      },
      'lastMutationAt': lastMutation?.toUtc().toIso8601String(),
    };
  }

  // ---------------------------------------------------------------- Lire

  Future<Map<String, dynamic>> decryptEnvelope(
    Map<String, dynamic> envelope, {
    GoogleAccount account = GoogleAccount.none,
    String code = '',
    void Function(BackupStage)? onStage,
  }) async {
    _checkEnvelope(envelope);
    final String kdf = envelope['kdf'] as String? ?? 'device-key';
    if (kdf == 'PBKDF2-CODE') {
      final List<int> salt = _envelopeSalt(envelope);
      final String backupCode = normalizeBackupCode(code);
      if (backupCode.isEmpty) {
        throw const BackupException(
          'Cette sauvegarde est protégée par un code à 4 chiffres : '
          'saisissez-le pour la restaurer.',
          codeRequired: true,
        );
      }
      if (!isValidBackupCode(backupCode)) {
        throw const BackupException(
          'Le code de sauvegarde comporte exactement 4 chiffres.',
          codeRequired: true,
        );
      }
      final List<int> key = _deriveKey(_codeIdentity(backupCode), salt);
      onStage?.call(BackupStage.decrypting);
      if (!_keyFits(envelope, key)) throw _codeMismatch();
      final String? clear = await AesBox.open(
        envelope['ciphertext'] as String,
        key,
      );
      if (clear == null) throw _codeMismatch();
      final String expected = envelope['sha256'] as String? ?? '';
      if (hash.sha256.convert(utf8.encode(clear)).toString() != expected) {
        throw const BackupException('Empreinte de sauvegarde invalide.');
      }
      onStage?.call(BackupStage.verifying);
      return jsonDecode(clear) as Map<String, dynamic>;
    }
    if (kdf == 'PBKDF2-HMAC-SHA256') {
      final Object? rawSalt = envelope['salt'];
      if (rawSalt is! String) {
        throw const BackupException('Sel de sauvegarde manquant ou invalide.');
      }
      final List<int> salt;
      try {
        salt = base64Decode(rawSalt);
      } catch (_) {
        throw const BackupException('Sel de sauvegarde invalide.');
      }
      // Chaque identité candidate du compte connecté est essayée : la
      // normalisation (minuscules, sans espaces) puis les variantes brutes
      // permettent de retrouver une sauvegarde faite avec le même compte.
      final List<String> candidates = account.keyCandidates;
      if (candidates.isEmpty) throw _accountMismatch(envelope, account);
      onStage?.call(BackupStage.decrypting);
      for (final String candidate in candidates) {
        final List<int> candidateKey = _deriveKey(candidate, salt);
        if (candidateKey.length != keyLength) continue;
        if (!_keyFits(envelope, candidateKey)) continue;
        final String? clear = await AesBox.open(
          envelope['ciphertext'] as String,
          candidateKey,
        );
        if (clear == null) continue;
        final String expected = envelope['sha256'] as String? ?? '';
        if (hash.sha256.convert(utf8.encode(clear)).toString() != expected) {
          throw const BackupException('Empreinte de sauvegarde invalide.');
        }
        onStage?.call(BackupStage.verifying);
        return jsonDecode(clear) as Map<String, dynamic>;
      }
      // Aucune variante n'a ouvert l'enveloppe : c'est une vraie différence.
      throw _accountMismatch(envelope, account);
    }

    final List<int> key = await _key();
    if (key.length != keyLength) {
      throw const BackupException(
        'Cette sauvegarde appartient à un autre appareil : sa clé AES-256 '
        'n’est pas disponible ici.',
      );
    }
    final String? keyId = envelope['keyId'] as String?;
    final String expectedKey = hash.sha256
        .convert(key)
        .toString()
        .substring(0, 16);
    if (keyId != null && keyId != expectedKey) {
      throw const BackupException(
        'Cette sauvegarde a été chiffrée avec la clé d’un autre appareil.',
      );
    }

    onStage?.call(BackupStage.decrypting);
    final String? clear = await AesBox.open(
      envelope['ciphertext'] as String,
      key,
    );
    if (clear == null) {
      throw const BackupException('Sauvegarde illisible ou altérée.');
    }

    onStage?.call(BackupStage.verifying);
    final String expected = envelope['sha256'] as String? ?? '';
    if (hash.sha256.convert(utf8.encode(clear)).toString() != expected) {
      throw const BackupException('Empreinte de sauvegarde invalide.');
    }
    return jsonDecode(clear) as Map<String, dynamic>;
  }

  /// Vrai si l'empreinte `keyId` de l'enveloppe correspond à cette clé.
  /// Une enveloppe sans `keyId` (ancienne) laisse le tag GCM décider.
  bool _keyFits(Map<String, dynamic> envelope, List<int> key) {
    final String? keyId = envelope['keyId'] as String?;
    if (keyId == null) return true;
    return keyId == hash.sha256.convert(key).toString().substring(0, 16);
  }

  /// Message de refus, avec l'e-mail attendu **seulement** si le compte
  /// connecté est réellement différent de celui de la sauvegarde.
  BackupException _accountMismatch(
    Map<String, dynamic> envelope,
    GoogleAccount account,
  ) {
    final GoogleAccount expected = GoogleAccount.fromJson(envelope['account']);
    final bool differentAccount =
        expected.email.isNotEmpty && expected.email != account.email;
    if (differentAccount) {
      return BackupException(
        'Cette sauvegarde appartient au compte Google ${expected.email} : '
        'connectez ce compte pour la restaurer.',
      );
    }
    if (account.isNotEmpty &&
        expected.email.isNotEmpty &&
        expected.email == account.email) {
      return const BackupException(
        'Compte Google identique, mais la clé de sauvegarde diffère sur cet '
        'appareil : déconnectez puis reconnectez ce compte Google, puis '
        'réessayez.',
      );
    }
    return const BackupException(
      'Connectez le même compte Google pour restaurer cette sauvegarde.',
    );
  }

  void _checkEnvelope(Map<String, dynamic> envelope) {
    if (envelope['format'] != 'akiba-backup' ||
        envelope['cipher'] != 'AES-256-GCM' ||
        envelope['ciphertext'] is! String) {
      throw const BackupException('Format de sauvegarde non reconnu.');
    }
    final int version = (envelope['version'] as num?)?.toInt() ?? 0;
    if (version > formatVersion) {
      throw const BackupException(
        'Sauvegarde créée par une version plus récente d’AKIBA.',
      );
    }
  }

  // -------------------------------------------------------------- Restaurer

  /// Restaure le contenu d'une enveloppe, sans jamais supprimer de données
  /// locales : les identifiants déjà présents sont ignorés.
  Future<Map<String, int>> restore(
    Map<String, dynamic> envelope, {
    GoogleAccount account = GoogleAccount.none,
    String code = '',
    void Function(BackupStage)? onStage,
  }) async {
    onStage?.call(BackupStage.downloading);
    final Map<String, dynamic> payload = await decryptEnvelope(
      envelope,
      account: account,
      code: code,
      onStage: onStage,
    );

    int accounts = 0;
    int transactions = 0;

    final Set<String> knownAccounts = (await _store.accounts())
        .map((Account a) => a.id)
        .toSet();
    for (final Object? row in (payload['accounts'] as List<dynamic>? ?? [])) {
      final Account account = Account.fromRow(
        Map<String, Object?>.from(row! as Map),
      );
      if (knownAccounts.add(account.id)) {
        await _store.saveAccount(account);
        accounts++;
      }
    }

    final Set<String> knownTransactions = (await _store.transactions(
      limit: 100000,
    )).map((TransactionRecord t) => t.id).toSet();
    for (final Object? row
        in (payload['transactions'] as List<dynamic>? ?? [])) {
      final TransactionRecord record = TransactionRecord.fromRow(
        Map<String, Object?>.from(row! as Map),
      );
      if (knownTransactions.add(record.id)) {
        await _store.saveTransaction(record);
        transactions++;
      }
    }

    for (final Object? row
        in (payload['savingsPots'] as List<dynamic>? ?? [])) {
      await _store.saveSavingsPot(
        SavingsPot.fromRow(Map<String, Object?>.from(row! as Map)),
      );
    }
    for (final Object? row
        in (payload['thirdParties'] as List<dynamic>? ?? [])) {
      await _store.saveThirdParty(
        ThirdParty.fromRow(Map<String, Object?>.from(row! as Map)),
      );
    }
    for (final Object? row in (payload['debts'] as List<dynamic>? ?? [])) {
      await _store.saveDebt(
        Debt.fromRow(Map<String, Object?>.from(row! as Map)),
      );
    }
    for (final Object? row in (payload['budgets'] as List<dynamic>? ?? [])) {
      await _store.saveBudget(
        Budget.fromRow(Map<String, Object?>.from(row! as Map)),
      );
    }
    for (final Object? row in (payload['needs'] as List<dynamic>? ?? [])) {
      await _store.saveNeed(
        Need.fromRow(Map<String, Object?>.from(row! as Map)),
      );
    }

    final Object? settings = payload['settings'];
    if (settings is Map) {
      for (final MapEntry<Object?, Object?> entry in settings.entries) {
        final String key = entry.key! as String;
        if (excludedSettings.contains(key)) continue;
        final Object? value = entry.value;
        if (value is String) await _store.setSetting(key, value);
      }
    }

    onStage?.call(BackupStage.done);
    return <String, int>{'accounts': accounts, 'transactions': transactions};
  }

  // ---------------------------------------------------------------- Transports

  /// Dossier local / Google Drive synchronisé sur l'appareil.
  Future<File> saveToFolder(
    Map<String, dynamic> envelope,
    String folderPath, {
    void Function(BackupStage)? onStage,
  }) async {
    onStage?.call(BackupStage.uploading);
    final Directory directory = folderPath.trim().isEmpty
        ? await workDirectory()
        : Directory(folderPath.trim());
    await directory.create(recursive: true);
    final DateTime now = DateTime.now();
    final String stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}-'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final File file = File(p.join(directory.path, 'akiba-$stamp.akiba'));
    await file.writeAsString(jsonEncode(envelope), flush: true);
    onStage?.call(BackupStage.done);
    return file;
  }

  Future<Map<String, dynamic>?> readFolder(
    String folderPath, {
    String? fileName,
    void Function(BackupStage)? onStage,
  }) async {
    onStage?.call(BackupStage.downloading);
    final Directory directory = folderPath.trim().isEmpty
        ? await workDirectory()
        : Directory(folderPath.trim());
    if (!await directory.exists()) return null;
    final List<File> files = await directory
        .list()
        .where((FileSystemEntity e) => e is File && e.path.endsWith('.akiba'))
        .cast<File>()
        .toList();
    if (files.isEmpty) return null;
    files.sort(
      (File a, File b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    final File chosen = fileName == null
        ? files.first
        : files.firstWhere(
            (File f) => p.basename(f.path) == fileName,
            orElse: () => files.first,
          );
    return jsonDecode(await chosen.readAsString()) as Map<String, dynamic>;
  }

  /// Envoi HTTP vers le Home Lab, avec jeton facultatif.
  Future<String> putRemote({
    required String url,
    required String token,
    required Map<String, dynamic> envelope,
    void Function(BackupStage)? onStage,
  }) async {
    onStage?.call(BackupStage.uploading);
    final Uri uri = _checkedUri(url);
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final HttpClientRequest request = await client.putUrl(uri);
      request.headers.contentType = ContentType.json;
      if (token.trim().isNotEmpty) {
        request.headers.set('Authorization', 'Bearer ${token.trim()}');
      }
      request.headers.set('X-Akiba-Backup', 'AES-256-GCM');
      // UTF-8 explicite : l'enveloppe contient des libellés accentués (noms de
      // tiers, catégories). Sans charset, `write` encoderait en latin1 et le
      // serveur recevrait un JSON invalide.
      request.add(utf8.encode(jsonEncode(envelope)));
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      // Le corps est lu pour récupérer le motif donné par le serveur (par
      // exemple « Jeton invalide ») : un 401 muet n'aide personne.
      final String body = await _readBody(response, maxBytes: 16384);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String? detail = serverDetail(body, secret: token);
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw BackupException(_accessMessage(response.statusCode, detail));
        }
        throw BackupException(
          'Le serveur a refusé la sauvegarde (HTTP ${response.statusCode}).'
          '${detail == null ? '' : ' $detail'}',
        );
      }
      onStage?.call(BackupStage.verifying);
      return uri.toString();
    } on BackupException {
      rethrow;
    } on HandshakeException {
      throw const BackupException(
        'Certificat HTTPS refusé : utilisez un certificat reconnu par '
        'l’appareil, ou l’adresse http:// sur le réseau local.',
      );
    } on SocketException {
      throw const BackupException(
        'Serveur injoignable : vérifiez l’adresse et le Wi-Fi.',
      );
    } on TimeoutException {
      throw const BackupException('Le serveur n’a pas répondu à temps.');
    } on HttpException catch (error) {
      throw BackupException(
        'Connexion interrompue (${error.message}) : vérifiez le schéma '
        'http/https et le port du serveur.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> fetchRemote({
    required String url,
    required String token,
    void Function(BackupStage)? onStage,
  }) async {
    onStage?.call(BackupStage.downloading);
    final Uri uri = _checkedUri(url);
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      if (token.trim().isNotEmpty) {
        request.headers.set('Authorization', 'Bearer ${token.trim()}');
      }
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final String body = await _readBody(response);
      // 404 et 204 signifient « aucune sauvegarde » : un corps vide ne doit
      // jamais être analysé, sinon l'utilisateur lit « format non reconnu »
      // alors qu'il n'y a simplement rien à restaurer.
      if (response.statusCode == 404 || response.statusCode == 204) {
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String? detail = serverDetail(body, secret: token);
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw BackupException(_accessMessage(response.statusCode, detail));
        }
        throw BackupException(
          'Lecture impossible (HTTP ${response.statusCode}).'
          '${detail == null ? '' : ' $detail'}',
        );
      }
      if (body.trim().isEmpty) return null;
      return decodeRemoteBackup(body);
    } on BackupException {
      rethrow;
    } on FormatException {
      throw const BackupException('Réponse du serveur illisible.');
    } on HandshakeException {
      throw const BackupException(
        'Certificat HTTPS refusé : vérifiez le certificat du serveur.',
      );
    } on SocketException {
      throw const BackupException('Serveur injoignable.');
    } on TimeoutException {
      throw const BackupException('Le serveur n’a pas répondu à temps.');
    } on HttpException catch (error) {
      throw BackupException(
        'Connexion interrompue (${error.message}) : vérifiez l’adresse et le '
        'port du serveur.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Teste l'accessibilité **et** l'authentification du serveur Home Lab,
  /// sans rien écrire : un simple GET en lecture seule.
  ///
  /// Le résultat est toujours rendu en clair (serveur joignable ou non, jeton
  /// accepté ou refusé) pour que l'utilisateur sache quoi corriger.
  Future<HomeLabProbe> probeRemote({
    required String url,
    required String token,
  }) async {
    final Uri uri;
    try {
      uri = _checkedUri(url);
    } on BackupException catch (error) {
      return HomeLabProbe(
        reachable: false,
        authenticated: false,
        message: error.message,
      );
    }
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'AKIBA-probe/1.0';
    final Stopwatch watch = Stopwatch()..start();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      if (token.trim().isNotEmpty) {
        request.headers.set('Authorization', 'Bearer ${token.trim()}');
      }
      request.headers.set('X-Akiba-Probe', '1');
      request.headers.set('Accept', 'application/json');
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      // Le corps porte le motif d'un refus (« Jeton invalide », « Jeton
      // manquant ») : c'est exactement ce que la personne doit lire pour
      // corriger son jeton.
      final String body = await _readBody(response, maxBytes: 8192);
      final Duration latency = watch.elapsed;
      final int status = response.statusCode;
      final bool withToken = token.trim().isNotEmpty;
      final String timing = ' en ${latency.inMilliseconds} ms';
      final String? detail = serverDetail(body, secret: token);
      final String reason = detail == null ? '' : ' $detail';
      if (status == 200 || status == 204) {
        return HomeLabProbe(
          reachable: true,
          authenticated: true,
          statusCode: status,
          latency: latency,
          message: withToken
              ? 'Communication OK$timing : jeton accepté (HTTP $status).'
              : 'Communication OK$timing (HTTP $status) : serveur joignable, '
                    'aucun jeton exigé.',
        );
      }
      if (status == 404) {
        return HomeLabProbe(
          reachable: true,
          authenticated: true,
          statusCode: status,
          latency: latency,
          message:
              'Communication OK$timing (HTTP 404) : serveur joignable, aucune '
              'sauvegarde à cette adresse. La première sauvegarde la créera.',
        );
      }
      if (status == 401 || status == 403) {
        return HomeLabProbe(
          reachable: true,
          authenticated: false,
          statusCode: status,
          latency: latency,
          message: withToken
              ? _accessMessage(status, detail)
              : 'Serveur joignable$timing, mais il exige un jeton '
                    '(HTTP $status).$reason Passez à l’étape 2 : saisissez le '
                    'jeton, puis « Enregistrer et activer ».',
        );
      }
      return HomeLabProbe(
        reachable: true,
        authenticated: false,
        statusCode: status,
        latency: latency,
        message:
            'Serveur joignable$timing, mais il répond HTTP $status.$reason '
            'Vérifiez l’adresse exacte de la sauvegarde AKIBA.',
      );
    } on HandshakeException {
      return const HomeLabProbe(
        reachable: false,
        authenticated: false,
        message:
            'Certificat HTTPS refusé : utilisez un certificat reconnu par '
            'l’appareil, ou l’adresse http:// sur le réseau local.',
      );
    } on SocketException catch (error) {
      // Refus de connexion (port fermé) et hôte introuvable sont deux causes
      // différentes : on le dit, au lieu d'un « injoignable » générique.
      final int? code = error.osError?.errorCode;
      final String detail =
          code == 111 ||
              code == 61 ||
              code == 10061 ||
              error.message.toLowerCase().contains('refused') ||
              InternetAddress.tryParse(uri.host) != null
          ? 'connexion refusée (port fermé) : vérifiez le port et que le '
                'service Home Lab écoute'
          : code == 11001 || code == 8
          ? 'nom introuvable : saisissez l’IP du serveur sur le même Wi-Fi'
          : 'aucune route vers le serveur : vérifiez que l’appareil est sur le '
                'même réseau, sans VPN';
      return HomeLabProbe(
        reachable: false,
        authenticated: false,
        message: 'Serveur injoignable — $detail.',
      );
    } on TimeoutException {
      return const HomeLabProbe(
        reachable: false,
        authenticated: false,
        message:
            'Aucune réponse en 8 s : le serveur est peut-être éteint, filtré '
            'par le pare-feu ou sur un autre réseau.',
      );
    } on HttpException catch (error) {
      return HomeLabProbe(
        reachable: false,
        authenticated: false,
        message:
            'Connexion interrompue (${error.message}). Vérifiez le schéma '
            'http/https et le port du serveur.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Normalise une adresse Home Lab saisie à la main.
  ///
  /// Une IP seule (`192.168.1.80`), un hôte avec port (`192.168.1.80:8080`)
  /// ou un nom (`akiba.local`) sont acceptés : le schéma `http://` est ajouté
  /// quand il manque. Sans cette tolérance, `Uri.parse` lisait `192.168…`
  /// comme un schéma et le test répondait « adresse invalide ».
  static String? normalizeUrl(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    String candidate = trimmed;
    final bool hasScheme = RegExp(
      r'^[a-zA-Z][a-zA-Z0-9+.-]*://',
    ).hasMatch(candidate);
    if (!hasScheme) candidate = 'http://$candidate';
    final Uri? uri = Uri.tryParse(candidate);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty ||
        !uri.hasAuthority) {
      return null;
    }
    // Un URI du type « http:///chemin » n'a pas d'hôte exploitable.
    if (uri.host.contains(' ') || uri.host == 'localhost.') return null;
    return candidate;
  }

  Uri _checkedUri(String raw) {
    final String? normalized = normalizeUrl(raw);
    if (normalized == null) {
      throw const BackupException(
        'Adresse invalide : saisissez une IP ou un nom, par exemple '
        '192.168.1.80:8080 ou https://akiba.local/backup.',
      );
    }
    return Uri.parse(normalized);
  }

  /// Sel de l'enveloppe, validé avant toute dérivation.
  List<int> _envelopeSalt(Map<String, dynamic> envelope) {
    final Object? rawSalt = envelope['salt'];
    if (rawSalt is! String) {
      throw const BackupException('Sel de sauvegarde manquant ou invalide.');
    }
    try {
      final List<int> salt = base64Decode(rawSalt);
      if (salt.length != 16) {
        throw const BackupException('Sel de sauvegarde invalide.');
      }
      return salt;
    } on FormatException {
      throw const BackupException('Sel de sauvegarde invalide.');
    }
  }

  /// Séparation de domaine : un code de sauvegarde ne peut jamais produire la
  /// même clé qu'une identité Google, même si les deux chaînes se ressemblent.
  static String _codeIdentity(String code) => 'code|$code';

  /// Code refusé : le message dit quoi faire, sans exposer le code saisi.
  ///
  /// Le code à 4 chiffres n'est pas une phrase secrète : il protège la
  /// sauvegarde contre une lecture accidentelle, pas contre un attaquant qui
  /// détiendrait le fichier et disposerait de temps de calcul. Ce compromis est
  /// documenté (REVUE_SECURITE.md) et remplace la dépendance au compte Google.
  BackupException _codeMismatch() => const BackupException(
    'Code à 4 chiffres incorrect. Si vous l’avez oublié, cette sauvegarde ne '
    'peut pas être rouverte : créez une nouvelle sauvegarde avec un nouveau '
    'code, elle remplacera celle du serveur et vous repartirez de zéro.',
    codeWrong: true,
  );

  List<int> _deriveKey(String googleAccountId, List<int> salt) {
    if (googleAccountId.trim().isEmpty || salt.length != 16) {
      throw const BackupException(
        'Compte Google ou sel de sauvegarde invalide.',
      );
    }
    final List<int> password = utf8.encode(
      '$_applicationSalt|${googleAccountId.trim()}',
    );
    final List<int> block = <int>[...salt, 0, 0, 0, 1];
    List<int> u = hash.Hmac(hash.sha256, password).convert(block).bytes;
    final List<int> output = List<int>.from(u);
    for (int iteration = 1; iteration < _pbkdf2Iterations; iteration++) {
      u = hash.Hmac(hash.sha256, password).convert(u).bytes;
      for (int i = 0; i < output.length; i++) {
        output[i] ^= u[i];
      }
    }
    return output;
  }

  // ------------------------------------------------------------------ Outils

  /// Analyse le corps renvoyé par un serveur de sauvegarde.
  ///
  /// Tolérant par construction : un corps vide vaut `null`, une chaîne JSON
  /// qui contient l'enveloppe est redécodée, et une enveloppe rangée sous
  /// `backup` / `envelope` / `latest` / `data` est dépliée. Un corps qui n'est
  /// pas une enveloppe AKIBA donne un message explicite, distinct du
  /// « format non reconnu » réservé à une enveloppe réellement altérée.
  static Map<String, dynamic>? decodeRemoteBackup(String body) {
    final String text = body.trim();
    if (text.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      if (text.startsWith('<')) {
        throw const BackupException(
          'Le serveur a renvoyé une page web au lieu d’une sauvegarde : '
          'vérifiez l’adresse exacte (chemin compris).',
        );
      }
      throw const BackupException('Réponse du serveur illisible.');
    }

    // Certains proxys renvoient le JSON sous forme de chaîne échappée.
    Object? value = decoded;
    for (int pass = 0; pass < 2 && value is String; pass++) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        throw const BackupException('Réponse du serveur illisible.');
      }
    }
    if (value is! Map) {
      throw const BackupException(
        'Le serveur n’a pas renvoyé une sauvegarde AKIBA : vérifiez '
        'l’adresse et le jeton.',
      );
    }

    Map<String, dynamic> envelope = Map<String, dynamic>.from(value);
    if (envelope['format'] != 'akiba-backup') {
      for (final String key in const <String>[
        'backup',
        'envelope',
        'latest',
        'data',
      ]) {
        final Object? nested = envelope[key];
        if (nested is Map && nested['format'] == 'akiba-backup') {
          envelope = Map<String, dynamic>.from(nested);
          break;
        }
      }
    }
    if (envelope['format'] != 'akiba-backup') {
      throw const BackupException(
        'Le serveur n’a pas renvoyé une sauvegarde AKIBA : vérifiez '
        'l’adresse et le jeton de cet utilisateur.',
      );
    }
    return envelope;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// Motif renvoyé par le serveur (`{"detail": "…"}`), s'il est lisible.
  ///
  /// Il permet de distinguer « jeton manquant », « jeton invalide » et « aucun
  /// jeton configuré » — les trois causes d'un 401 — au lieu d'un code HTTP
  /// seul. Aucun corps binaire ni page web n'est repris.
  static String? serverDetail(String body, {String secret = ''}) {
    final String text = body.trim();
    if (text.isEmpty || text.startsWith('<')) return null;
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map) {
        final Object? detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return _clipDetail(_redact(detail.trim(), secret));
        }
        if (detail is List && detail.isNotEmpty) {
          final Object? first = detail.first;
          if (first is Map && first['msg'] is String) {
            return _clipDetail(
              _redact((first['msg'] as String).trim(), secret),
            );
          }
        }
      }
    } on FormatException {
      // Corps non JSON : aucun motif exploitable.
    }
    return null;
  }

  static String _clipDetail(String value) =>
      value.length <= 180 ? value : '${value.substring(0, 177)}…';

  /// Retire un secret d'un texte destiné à l'écran.
  ///
  /// Un serveur ou un proxy peut recopier l'en-tête reçu dans son message
  /// d'erreur : sans ce filtre, le jeton s'afficherait dans l'application.
  static String _redact(String value, String secret) {
    final String token = secret.trim();
    if (token.length < 4) return value;
    return value.replaceAll(token, '••••');
  }

  /// Corps de la réponse, décodé en UTF-8.
  ///
  /// [maxBytes] plafonne la lecture quand seul un motif d'erreur est cherché
  /// (réponse à un envoi, test de communication) : inutile d'absorber la page
  /// entière d'un proxy captif. Sans plafond, la sauvegarde est lue en entier.
  static Future<String> _readBody(
    HttpClientResponse response, {
    int? maxBytes,
  }) async {
    final BytesBuilder bytes = BytesBuilder(copy: false);
    await for (final List<int> chunk in response.timeout(
      const Duration(seconds: 20),
    )) {
      bytes.add(chunk);
      final int? cap = maxBytes;
      if (cap != null && bytes.length >= cap) break;
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  /// Refus d'authentification expliqué, avec le motif venu du serveur.
  static String _accessMessage(int status, String? detail) {
    final String reason = detail == null || detail.isEmpty ? '' : ' $detail';
    return 'Jeton refusé par le serveur (HTTP $status).$reason '
        'Vérifiez le jeton d’accès (s’il est partagé, gardez « :mon_nom ») : '
        'côté serveur, SHARED_TOKEN doit être identique et le conteneur recréé '
        '(docker compose up -d).';
  }

  /// Métadonnées lisibles sans clé.
  static BackupMetadata metadata(Map<String, dynamic> envelope) {
    final Map<String, dynamic> counts = Map<String, dynamic>.from(
      envelope['counts'] as Map? ?? const <String, dynamic>{},
    );
    return BackupMetadata(
      createdAt:
          DateTime.tryParse(envelope['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      deviceId: envelope['deviceId'] as String? ?? '',
      lastMutationAt: DateTime.tryParse(
        envelope['lastMutationAt'] as String? ?? '',
      ),
      transactions: (counts['transactions'] as num?)?.toInt() ?? 0,
      accounts: (counts['accounts'] as num?)?.toInt() ?? 0,
    );
  }
}

class BackupMetadata {
  const BackupMetadata({
    required this.createdAt,
    required this.deviceId,
    required this.transactions,
    required this.accounts,
    this.lastMutationAt,
  });

  final DateTime createdAt;
  final String deviceId;
  final DateTime? lastMutationAt;
  final int transactions;
  final int accounts;

  /// Vrai si cette sauvegarde contient des mouvements plus récents que ceux
  /// connus localement : un conflit doit alors être confirmé.
  bool isNewerThan(DateTime? localLastMutation) {
    if (localLastMutation == null) return false;
    return lastMutationAt != null && lastMutationAt!.isAfter(localLastMutation);
  }
}

class BackupException implements Exception {
  const BackupException(
    this.message, {
    this.codeRequired = false,
    this.codeWrong = false,
  });

  final String message;

  /// Vrai quand le code à 4 chiffres manque pour ouvrir l'enveloppe.
  final bool codeRequired;

  /// Vrai quand le code saisi n'ouvre pas l'enveloppe.
  final bool codeWrong;

  @override
  String toString() => message;
}

/// Utilitaire de test : sérialise une enveloppe pour un fichier.
Uint8List encodeEnvelope(Map<String, dynamic> envelope) =>
    Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
