import '../state/akiba_settings.dart';

/// Quota local d'analyses distantes, remis à zéro chaque jour civil.
///
/// Une analyse distante consomme **une** unité, quel que soit le nombre de
/// modèles essayés en cascade : c'est la demande de la personne qui compte,
/// pas la mécanique interne. Un échec compte aussi, puisque l'appel a bien
/// été envoyé. Une fois le quota épuisé, l'assistant repasse en analyse locale
/// sans bloquer ni afficher d'erreur.
class AiQuota {
  AiQuota(this._settings, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AkibaSettings _settings;
  final DateTime Function() _now;

  static const String daySetting = 'ai_quota_date';
  static const String usedSetting = 'ai_quota_used';

  /// Plafond du jour, réglable ; 0 signifie « aucun appel distant ».
  int get limit =>
      _settings.integer('ai_quota_per_day', fallback: 20).clamp(0, 200);

  String get today => day(_now());

  /// Date au format `aaaa-mm-jj`, sans dépendre du fuseau du système.
  static String day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// Unités consommées aujourd'hui (0 si le compteur date d'hier).
  int get used => _settings.raw(daySetting) == today
      ? _settings.integer(usedSetting).clamp(0, limit)
      : 0;

  int get remaining => (limit - used).clamp(0, limit);

  bool get exhausted => remaining == 0;

  /// Réserve une unité ; faux si le quota du jour est atteint.
  ///
  /// Le compteur n'est jamais réécrit pour un autre jour : la remise à zéro est
  /// implicite (la date enregistrée ne correspond plus à aujourd'hui).
  Future<bool> consume() async {
    final int current = used;
    if (current >= limit) return false;
    await _settings.set(daySetting, today);
    await _settings.set(usedSetting, '${current + 1}');
    return true;
  }

  /// Mention discrète pour les réglages et le repli local.
  String get label => '$used / $limit aujourd’hui';
}
