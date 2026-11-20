import 'package:flutter/material.dart';

import '../format/akiba_currency.dart';
import '../theme/akiba_theme.dart';

import '../../data/akiba_store.dart';

/// Réglages persistants d'AKIBA (table `settings`, donc dans la base chiffrée).
///
/// Un seul objet porte l'apparence, la sécurité, les préférences régionales et
/// les rappels ; il notifie l'interface après chaque écriture.
class AkibaSettings extends ChangeNotifier {
  AkibaSettings(this._store);

  final AkibaStore _store;
  final Map<String, String> _values = <String, String>{};
  bool _loaded = false;

  /// Valeurs par défaut : thème clair, animations normales, FCFA, Lomé.
  static const Map<String, String> defaults = <String, String>{
    'akiba_theme': 'blanc',
    'reduce_animations': '0',
    'pin_hash': '',
    'pin_salt': '',
    'biometrics': '0',
    'lock_on_resume': '1',
    'first_name': '',
    'last_name': '',
    'currency': 'FCFA',
    'date_style': 'jj/mm/aaaa',
    'timezone': 'Africa/Lome',
    'onboarding_done': '0',
    'onboarding_step': '0',
    'language': 'fr',
    'notif_morning': '1',
    'notif_noon': '1',
    'notif_evening': '1',
    'notif_morning_time': '07:30',
    'notif_noon_time': '12:30',
    'notif_evening_time': '20:30',
    'dnd_enabled': '1',
    'dnd_start': '22:00',
    'dnd_end': '07:00',
    'festive_enabled': '1',
    'festive_label': '',
    'festive_start': '',
    'festive_end': '',
    'simulation_mode': '0',
    'permission_notifications': '0',
    'permission_sms': '0',
    'permission_micro': '0',
    'permission_wifi': '0',
    'savings_goal_percent': '10',
    'google_linked': '0',
    'profile_photo_updated_at': '',
    'backup_drive_folder': '',
    'lab_url': '',
    'lab_token': '',
    'last_backup_at': '',
    'last_backup_target': '',
    'restore_pending_at': '',
    'ai_quota_per_day': '20',
    'ai_quota_date': '',
    'ai_quota_used': '0',
    // Module IA : la clé n'est stockée que chiffrée (cf. AiKeyVault).
    'ai_api_key_sealed': '',
    'ai_api_key_updated_at': '',
    'ai_remote_enabled': '0',
    'ai_models_cache': '',
    'ai_models_cached_at': '',
    'ai_model_priority': '',
    'ai_max_attempts': '3',
  };

  bool get loaded => _loaded;

  Future<void> load() async {
    for (final String key in defaults.keys) {
      try {
        final String? stored = await _store.setting(key);
        if (stored != null) _values[key] = stored;
      } catch (_) {
        // Base absente : on garde la valeur par défaut.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  String raw(String key) => _values[key] ?? defaults[key] ?? '';

  bool flag(String key) => raw(key) == '1';

  int integer(String key, {int fallback = 0}) =>
      int.tryParse(raw(key)) ?? fallback;

  Future<void> set(String key, String value) async {
    _values[key] = value;
    notifyListeners();
    try {
      await _store.setSetting(key, value);
    } catch (_) {
      // Repli sans base : le réglage reste valable pour la session.
    }
  }

  Future<void> setFlag(String key, bool value) => set(key, value ? '1' : '0');

  // Apparence -----------------------------------------------------------

  /// Thème persistant (Blanc par défaut, Sombre, Bleu, Vert, Jaune Or).
  AkibaThemeId get themeId => AkibaThemeId.fromStorage(_values['akiba_theme']);

  Future<void> setThemeId(AkibaThemeId id) => set('akiba_theme', id.storageKey);

  /// Thème suivant dans l'ordre du sélecteur (bouton d'apparence de l'accueil).
  AkibaThemeId get nextThemeId {
    final List<AkibaThemeId> all = AkibaThemeId.values;
    return all[(all.indexOf(themeId) + 1) % all.length];
  }

  bool get reduceAnimations => flag('reduce_animations');

  Future<void> setReduceAnimations(bool value) =>
      setFlag('reduce_animations', value);

  // Sécurité ------------------------------------------------------------

  bool get pinEnabled => raw('pin_hash').isNotEmpty;

  String get pinHash => raw('pin_hash');

  String get pinSalt => raw('pin_salt');

  bool get biometrics => flag('biometrics');

  bool get lockOnResume => flag('lock_on_resume');

  Future<void> clearPin() async {
    await set('pin_hash', '');
    await set('pin_salt', '');
    await setFlag('biometrics', false);
  }

  // Identité et préférences ---------------------------------------------

  String get firstName => raw('first_name');

  String get lastName => raw('last_name');

  String get displayName {
    final String name = firstName.trim();
    if (name.isNotEmpty) return name;
    return 'vous';
  }

  String get currency => raw('currency');

  /// Devise d'affichage choisie (FCFA par défaut, repli sur toute valeur
  /// inconnue enregistrée par une version antérieure).
  AkibaCurrency get currencyCode => AkibaCurrency.fromStorage(currency);

  Future<void> setCurrency(AkibaCurrency value) =>
      set('currency', value.storageKey);

  String get dateStyle => raw('date_style');

  String get timezone => raw('timezone');

  /// Suffixe collé aux montants (`FCFA`, `€`, `$`, `¥`).
  ///
  /// Aucun taux de change n'est appliqué : la valeur des montants ne change
  /// pas, seul leur libellé suit ce réglage.
  String get currencyLabel => currencyCode.symbol;

  // Onboarding ----------------------------------------------------------

  bool get onboardingDone => flag('onboarding_done');

  int get onboardingStep => integer('onboarding_step');

  Future<void> setOnboardingStep(int step) => set('onboarding_step', '$step');

  Future<void> setOnboardingDone(bool value) async {
    await setFlag('onboarding_done', value);
    if (!value) await setOnboardingStep(0);
  }

  // Notifications -------------------------------------------------------

  bool get morningEnabled => flag('notif_morning');

  bool get noonEnabled => flag('notif_noon');

  bool get eveningEnabled => flag('notif_evening');

  String get morningTime => raw('notif_morning_time');

  String get noonTime => raw('notif_noon_time');

  String get eveningTime => raw('notif_evening_time');

  bool get dndEnabled => flag('dnd_enabled');

  String get dndStart => raw('dnd_start');

  String get dndEnd => raw('dnd_end');

  bool get festiveEnabled => flag('festive_enabled');

  String get festiveLabel => raw('festive_label');

  bool get simulationMode => flag('simulation_mode');

  // Aide et modules -----------------------------------------------------

  String get driveFolder => raw('backup_drive_folder');

  String get labUrl => raw('lab_url');

  String get labToken => raw('lab_token');

  String get lastBackupAt => raw('last_backup_at');

  String get lastBackupTarget => raw('last_backup_target');

  bool get googleLinked => flag('google_linked');

  // Module IA -----------------------------------------------------------

  /// Une clé API est présente (chiffrée) dans les réglages.
  bool get aiKeyConfigured => raw('ai_api_key_sealed').isNotEmpty;

  /// Appels distants autorisés par la personne.
  bool get aiRemoteEnabled => flag('ai_remote_enabled');

  /// Nombre maximal de modèles essayés avant le repli local.
  int get aiMaxAttempts => integer('ai_max_attempts', fallback: 3);

  /// Plafond d'analyses distantes par jour (compteur daté, cf. `AiQuota`).
  int get aiQuotaPerDay => integer('ai_quota_per_day', fallback: 20);
}

/// Accès aux réglages depuis n'importe quel écran.
class AkibaSettingsScope extends InheritedNotifier<AkibaSettings> {
  const AkibaSettingsScope({
    super.key,
    required AkibaSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AkibaSettings of(BuildContext context) {
    final AkibaSettingsScope? scope = context
        .dependOnInheritedWidgetOfExactType<AkibaSettingsScope>();
    assert(scope != null, 'AkibaSettingsScope absent de l’arbre');
    return scope!.notifier!;
  }

  static AkibaSettings? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AkibaSettingsScope>()
        ?.notifier;
  }
}
