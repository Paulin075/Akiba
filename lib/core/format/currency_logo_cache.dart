import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'akiba_currency.dart';

/// Cache local des logos de devises.
///
/// Le logo est téléchargé **une seule fois** depuis le CDN public de la devise,
/// puis écrit dans le dossier de support de l'application. Hors ligne, le
/// fichier déjà présent est réutilisé ; s'il n'existe pas, `resolve` renvoie
/// `null` et l'interface affiche son repli typographique — aucune erreur n'est
/// remontée à la personne.
abstract final class CurrencyLogoCache {
  /// Mémoire de session : évite de relire le fichier à chaque reconstruction.
  static final Map<AkibaCurrency, File> _memory = <AkibaCurrency, File>{};

  /// Taille maximale acceptée pour un logo (un drapeau fait quelques Ko).
  static const int maxBytes = 512 * 1024;

  /// Délai maximal d'un téléchargement : au-delà, on garde le repli.
  static const Duration timeout = Duration(seconds: 6);

  static Future<File?> resolve(
    AkibaCurrency currency, {
    bool refresh = false,
  }) async {
    final File? known = _memory[currency];
    if (!refresh && known != null) return known;

    try {
      final Directory directory = await _directory();
      final File file = File(
        p.join(directory.path, '${currency.storageKey.toLowerCase()}.png'),
      );

      if (!refresh && await _isUsable(file)) {
        _memory[currency] = file;
        return file;
      }

      final List<int>? bytes = await _download(currency.logoUrl);
      if (bytes == null) {
        // Hors ligne : on sert l'ancienne copie si elle existe encore.
        return await _isUsable(file) ? file : null;
      }

      final File temporary = File('${file.path}.part');
      await temporary.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      _memory[currency] = file;
      return file;
    } catch (_) {
      // Aucun journal : le repli visuel suffit.
      return _memory[currency];
    }
  }

  /// Efface la copie locale (utilisé par les tests).
  static Future<void> clear(AkibaCurrency currency) async {
    _memory.remove(currency);
    try {
      final Directory directory = await _directory();
      final File file = File(
        p.join(directory.path, '${currency.storageKey.toLowerCase()}.png'),
      );
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Rien à effacer.
    }
  }

  static Future<bool> _isUsable(File file) async {
    try {
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  static Future<Directory> _directory() async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory directory = Directory(
      p.join(support.path, 'currency_logos'),
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static Future<List<int>?> _download(String url) async {
    final HttpClient client = HttpClient()..connectionTimeout = timeout;
    try {
      final HttpClientRequest request = await client.getUrl(Uri.parse(url));
      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );
      if (response.statusCode != HttpStatus.ok) return null;

      final List<int> bytes = <int>[];
      await for (final List<int> chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) return null;
      }
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
