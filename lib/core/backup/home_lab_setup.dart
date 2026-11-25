import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/akiba_store.dart';
import '../state/akiba_settings.dart';
import 'backup_service.dart';
import 'google_account.dart';
import 'google_drive_backup.dart';

/// Coffre du jeton Home Lab.
///
/// Le jeton n'est **jamais** écrit en clair dans la base de réglages : il vit
/// dans le coffre du système (Keystore Android / DPAPI Windows), exactement
/// comme les jetons Google.
abstract interface class LabTokenStore {
  Future<String> read();

  Future<void> write(String token);

  Future<void> delete();
}

/// Coffre réel : `flutter_secure_storage`.
class SecureLabTokenStore implements LabTokenStore {
  const SecureLabTokenStore([this.storage = const FlutterSecureStorage()]);

  static const String keyName = 'akiba_lab_token';

  final FlutterSecureStorage storage;

  @override
  Future<String> read() async {
    try {
      final String? value = await storage.read(key: keyName);
      return value == null ? '' : value.trim();
    } catch (_) {
      return '';
    }
  }

  @override
  Future<void> write(String token) =>
      storage.write(key: keyName, value: token.trim());

  @override
  Future<void> delete() => storage.delete(key: keyName);
}

/// Coffre en mémoire, réservé aux tests : aucun greffon natif.
class InMemoryLabTokenStore implements LabTokenStore {
  InMemoryLabTokenStore([this._token = '']);

  String _token;

  @override
  Future<String> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token.trim();

  @override
  Future<void> delete() async => _token = '';
}

/// Étape du parcours de configuration du serveur Home Lab.
enum HomeLabStep {
  /// Étape 1 : adresse du serveur et test de communication.
  address,

  /// Étape 2 : jeton d'accès et sauvegarde automatique.
  token,

  /// Les deux étapes sont validées : la sauvegarde automatique est armée.
  ready,
}

/// Résultat d'une étape, prêt à afficher.
class HomeLabSetupResult {
  const HomeLabSetupResult({
    required this.ok,
    required this.message,
    this.latency,
  });

  final bool ok;
  final String message;
  final Duration? latency;
}

/// Configuration du Home Lab en **deux étapes**.
///
/// 1. `testAddress` : l'adresse (IP, `ip:port`, nom local ou URL) est
///    normalisée puis réellement interrogée **sans jeton** (GET en lecture
///    seule) : la latence et un diagnostic précis sont rendus.
/// 2. `activateToken` : une fois la communication confirmée, le jeton est
///    vérifié auprès du serveur, écrit dans le coffre du système, puis la
///    sauvegarde automatique chiffrée AES-256-GCM est armée et une première
///    sauvegarde est envoyée immédiatement.
class HomeLabSetup {
  HomeLabSetup({
    required this.service,
    required this.settings,
    LabTokenStore? tokens,
  }) : tokens = tokens ?? const SecureLabTokenStore();

  final BackupService service;
  final AkibaSettings settings;
  final LabTokenStore tokens;

  HomeLabStep _step = HomeLabStep.address;
  String _url = '';
  bool _reachable = false;
  bool _tokenSaved = false;
  Duration? _latency;
  HomeLabSetupResult? _last;

  HomeLabStep get step => _step;

  /// Adresse normalisée retenue pour le test et la sauvegarde.
  String get url => _url;

  /// Vrai quand la communication a été confirmée dans cette session.
  bool get reachable => _reachable;

  /// Vrai quand un jeton est déjà enregistré dans le coffre.
  bool get tokenSaved => _tokenSaved;

  /// Latence du dernier test réussi.
  Duration? get latency => _latency;

  /// Latence lisible : `18 ms` (vide si aucun test n'a abouti).
  String get latencyLabel =>
      _latency == null ? '' : '${_latency!.inMilliseconds} ms';

  HomeLabSetupResult? get last => _last;

  /// Vrai quand la zone « jeton » peut être affichée (étape 2 déverrouillée).
  bool get tokenStepUnlocked => _reachable || _tokenSaved;

  /// Relit la configuration enregistrée et migre au besoin l'ancien jeton
  /// resté en clair dans les réglages.
  Future<void> load() async {
    await migrateLegacyLabToken(settings, tokens);
    _url = settings.labUrl.trim();
    _tokenSaved = (await tokens.read()).isNotEmpty;
    _step = _url.isEmpty
        ? HomeLabStep.address
        : (_tokenSaved ? HomeLabStep.ready : HomeLabStep.token);
  }

  String _tokenCache = '';

  /// Lit le jeton courant dans le coffre (jamais dans les réglages).
  Future<String> currentToken() async {
    _tokenCache = await tokens.read();
    return _tokenCache;
  }

  /// Étape 1 — teste la joignabilité réelle du serveur, sans jeton.
  Future<HomeLabSetupResult> testAddress(String rawUrl) async {
    final String? normalized = BackupService.normalizeUrl(rawUrl);
    if (normalized == null) {
      return _fail(
        'Adresse invalide : utilisez par exemple 192.168.1.80:8080 ou '
        'https://akiba.local/backup.',
        step: HomeLabStep.address,
      );
    }
    final HomeLabProbe probe = await service.probeRemote(
      url: normalized,
      token: '',
    );
    _url = normalized;
    _latency = probe.latency;
    _reachable = probe.reachable;
    if (!probe.reachable) {
      _step = HomeLabStep.address;
      return _fail(probe.message, step: HomeLabStep.address);
    }
    // L'adresse est enregistrée dès qu'elle répond : la sauvegarde suivante
    // utilise exactement l'URL testée.
    await settings.set('lab_url', normalized);
    _step = HomeLabStep.token;
    final HomeLabSetupResult result = HomeLabSetupResult(
      ok: true,
      message: probe.message,
      latency: probe.latency,
    );
    _last = result;
    return result;
  }

  /// Étape 2 — vérifie le jeton, l'enregistre dans le coffre puis arme la
  /// sauvegarde automatique (et envoie immédiatement une sauvegarde).
  Future<HomeLabSetupResult> activateToken(String rawToken) async {
    final String token = rawToken.trim();
    if (token.isEmpty) {
      return _fail(
        'Saisissez le jeton fourni par le serveur Home Lab.',
        step: HomeLabStep.token,
      );
    }
    if (_url.isEmpty) {
      return _fail(
        'Testez d’abord la communication avec le serveur (étape 1).',
        step: HomeLabStep.address,
      );
    }
    final HomeLabProbe probe = await service.probeRemote(
      url: _url,
      token: token,
    );
    if (!probe.reachable) {
      _reachable = false;
      return _fail(probe.message, step: HomeLabStep.address);
    }
    _reachable = true;
    _latency = probe.latency;
    if (!probe.authenticated) {
      return _fail(probe.message, step: HomeLabStep.token);
    }
    try {
      await tokens.write(token);
    } catch (_) {
      return _fail(
        'Le jeton n’a pas pu être protégé dans le coffre du système.',
        step: HomeLabStep.token,
      );
    }
    _tokenCache = token;
    _tokenSaved = true;
    await settings.set('lab_url', _url);
    await settings.setFlag(HomeLabAutoBackup.flag, true);

    final HomeLabAutoBackup auto = HomeLabAutoBackup(
      service: service,
      settings: settings,
      tokens: tokens,
    );
    String suffix;
    try {
      await auto.runNow();
      suffix = ' Première sauvegarde chiffrée envoyée.';
    } on BackupException catch (error) {
      suffix = ' Envoi immédiat à refaire : ${error.message}';
    }
    _step = HomeLabStep.ready;
    final HomeLabSetupResult result = HomeLabSetupResult(
      ok: true,
      message:
          'Jeton enregistré, sauvegarde automatique chiffrée activée '
          '(toutes les ${HomeLabAutoBackup.minimumInterval.inHours} h).'
          '$suffix',
      latency: probe.latency,
    );
    _last = result;
    return result;
  }

  HomeLabSetupResult _fail(String message, {required HomeLabStep step}) {
    _step = step;
    final HomeLabSetupResult result = HomeLabSetupResult(
      ok: false,
      message: message,
    );
    _last = result;
    return result;
  }
}

/// Sauvegarde automatique chiffrée vers le Home Lab.
///
/// Aucun serveur maître : la cible est l'adresse locale choisie par la
/// personne, sur son Wi-Fi. L'enveloppe part déjà chiffrée en AES-256-GCM.
class HomeLabAutoBackup {
  HomeLabAutoBackup({
    required this.service,
    required this.settings,
    LabTokenStore? tokens,
  }) : tokens = tokens ?? const SecureLabTokenStore();

  /// Réglage marquant l'activation depuis la validation du jeton.
  static const String flag = 'lab_auto_backup';

  /// Une sauvegarde au plus toutes les six heures au démarrage.
  static const Duration minimumInterval = Duration(hours: 6);

  final BackupService service;
  final AkibaSettings settings;
  final LabTokenStore tokens;

  /// Envoie une sauvegarde chiffrée maintenant, avec le jeton du coffre.
  Future<bool> runNow({GoogleAccount account = GoogleAccount.none}) async {
    final String url = settings.labUrl.trim();
    if (url.isEmpty) {
      throw const BackupException('Aucun serveur Home Lab configuré.');
    }
    final String token = await tokens.read();
    if (token.isEmpty) {
      throw const BackupException(
        'Jeton Home Lab absent : ressaisissez-le à l’étape 2.',
      );
    }
    final Map<String, dynamic> envelope = await service.createEnvelope(
      deviceId: 'akiba-${settings.timezone}',
      account: account,
    );
    await service.putRemote(url: url, token: token, envelope: envelope);
    await settings.set(
      'last_backup_at',
      DateTime.now().toUtc().toIso8601String(),
    );
    await settings.set('last_backup_target', 'homeLab');
    return true;
  }

  /// Sauvegarde silencieuse si l'option est active et l'échéance atteinte.
  Future<bool> runIfDue({
    GoogleAccount account = GoogleAccount.none,
    DateTime? now,
  }) async {
    if (!settings.flag(flag)) return false;
    if (settings.labUrl.trim().isEmpty) return false;
    final DateTime moment = now ?? DateTime.now();
    final DateTime? last = DateTime.tryParse(settings.lastBackupAt)?.toLocal();
    if (last != null &&
        settings.lastBackupTarget == 'homeLab' &&
        moment.difference(last) < minimumInterval) {
      return false;
    }
    try {
      return await runNow(account: account);
    } catch (_) {
      // Serveur éteint, Wi-Fi absent : rien n'est affiché et l'échéance
      // suivante réessaiera.
      return false;
    }
  }
}

/// Déplace un jeton Home Lab hérité (écrit en clair dans les réglages) vers le
/// coffre du système, puis efface la valeur des réglages.
Future<void> migrateLegacyLabToken(
  AkibaSettings settings,
  LabTokenStore tokens,
) async {
  final String legacy = settings.raw('lab_token').trim();
  if (legacy.isEmpty) return;
  try {
    await tokens.write(legacy);
    await settings.set('lab_token', '');
  } catch (_) {
    // Coffre indisponible : la valeur reste en place, aucun jeton perdu.
  }
}

/// Sauvegarde automatique Home Lab au démarrage, hors du chemin critique.
///
/// Silencieuse par construction : sans serveur joignable, rien n'est affiché
/// et l'application reste pleinement utilisable.
Future<void> runLabAutoBackupOnStartup(
  AkibaStore store,
  AkibaSettings settings,
) async {
  try {
    final LabTokenStore tokens = const SecureLabTokenStore();
    await migrateLegacyLabToken(settings, tokens);
    final GoogleAccount account = await GoogleDriveService().currentAccount();
    await HomeLabAutoBackup(
      service: BackupService(store),
      settings: settings,
      tokens: tokens,
    ).runIfDue(account: account);
  } catch (_) {
    // Aucun blocage du démarrage.
  }
}
