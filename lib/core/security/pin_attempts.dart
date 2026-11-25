import '../../data/akiba_store.dart';

/// Limitation des essais de PIN.
///
/// Le compteur et l'instant de déblocage sont écrits dans la base chiffrée
/// (table `settings`), donc ils survivent à un redémarrage : quitter
/// l'application ne remet pas les essais à zéro.
///
/// Trois essais sont libres, puis le délai croît : 30 s, 1 min, 2 min, 5 min.
/// Le message affiché reste neutre : aucun nombre d'essais restants n'est
/// révélé, et aucune donnée n'est jamais effacée.
class PinAttempts {
  PinAttempts(this._store);

  final AkibaStore _store;

  static const String failuresKey = 'pin_failures';
  static const String lockedUntilKey = 'pin_locked_until';

  /// Essais gratuits avant le premier délai.
  static const int freeAttempts = 3;

  /// Paliers de délai, du 3e échec au-delà.
  static const List<int> lockSeconds = <int>[30, 60, 120, 300];

  /// Délai imposé après [failures] échecs consécutifs.
  static Duration delayFor(int failures) {
    if (failures < freeAttempts) return Duration.zero;
    final int index = (failures - freeAttempts).clamp(
      0,
      lockSeconds.length - 1,
    );
    return Duration(seconds: lockSeconds[index]);
  }

  /// Secondes restantes avant un nouvel essai (0 si aucun verrou).
  static int remainingSeconds(DateTime? until, DateTime now) {
    if (until == null) return 0;
    final int seconds = until.difference(now).inSeconds;
    return seconds > 0 ? seconds : 0;
  }

  Future<int> failures() async {
    try {
      return int.tryParse(await _store.setting(failuresKey) ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<DateTime?> lockedUntil() async {
    try {
      final String raw = await _store.setting(lockedUntilKey) ?? '';
      return raw.isEmpty ? null : DateTime.tryParse(raw)?.toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Délai encore actif au moment de l'appel.
  Future<Duration> remaining({DateTime? now}) async {
    final int seconds = remainingSeconds(
      await lockedUntil(),
      now ?? DateTime.now(),
    );
    return Duration(seconds: seconds);
  }

  /// Enregistre un échec et renvoie le délai à appliquer (zéro avant le
  /// troisième échec).
  Future<Duration> registerFailure({DateTime? now}) async {
    final DateTime clock = now ?? DateTime.now();
    final int next = await failures() + 1;
    final Duration delay = delayFor(next);
    try {
      await _store.setSetting(failuresKey, '$next');
      if (delay > Duration.zero) {
        await _store.setSetting(
          lockedUntilKey,
          clock.add(delay).toUtc().toIso8601String(),
        );
      }
    } catch (_) {
      // Base absente : la limitation reste valable pour la session.
    }
    return delay;
  }

  /// Remet le compteur à zéro après un code correct.
  Future<void> reset() async {
    try {
      await _store.setSetting(failuresKey, '0');
      await _store.setSetting(lockedUntilKey, '');
    } catch (_) {
      // Rien à réinitialiser.
    }
  }
}
