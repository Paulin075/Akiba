import 'package:flutter/material.dart';

import '../format/akiba_currency.dart';
import '../format/akiba_date.dart';
import '../format/akiba_money.dart';
import '../theme/akiba_theme.dart';
import 'akiba_l10n.dart';

import '../../data/akiba_store.dart';

/// Réglages persistants d'AKIBA (table `settings`, donc dans la base chiffrée).
///
/// Un seul objet porte l'apparence, la sécurité, les préférences régionales et
/// les rappels ; il notifie l'interface après chaque écriture.
class AkibaSettings extends ChangeNotifier {
  AkibaSettings(this._store);

  final AkibaStore _store;

  /// Magasin qui porte les réglages (toujours la base réelle, même en mode
  /// simulation). Les modules de sécurité doivent écrire ici : sinon un PIN
  /// enregistré pendant la simulation n'activerait jamais le verrou.
  AkibaStore get store => _store;

  final Map<String, String> _values = <String, String>{};
  bool _loaded = false;

  /// Valeurs par défaut : thème clair, animations normales, FCFA, Lomé.
  static const Map<String, String> defaults = <String, String>{
    'akiba_theme': 'blanc',
    'reduce_animations': '0',
    'pin_hash': '',
    'pin_salt': '',
    'pin_failures': '0',
    'pin_locked_until': '',
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
    'notif_expense': '1',
    'notif_debt': '1',
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
    'lab_auto_backup': '0',
    'last_backup_at': '',
    'last_backup_target': '',
    'restore_pending_at': '',
    'restore_done': '0',
    // Horodatage d'une sauvegarde automatique qui a échoué (réseau absent).
    // Non vide = une nouvelle tentative est programmée / à faire au retour.
    'auto_backup_pending_at': '',
    'ai_quota_per_day': '20',
    'ai_quota_date': '',
    'ai_quota_used': '0',
    // Module IA : les clés ne sont stockées que chiffrées (cf. AiKeyVault),
    // une par fournisseur ; Gemini garde les noms historiques.
    'ai_provider': 'gemini',
    'ai_api_key_sealed': '',
    'ai_api_key_updated_at': '',
    'ai_api_key_sealed_deepseek': '',
    'ai_api_key_updated_at_deepseek': '',
    'ai_api_key_sealed_openrouter': '',
    'ai_api_key_updated_at_openrouter': '',
    'ai_api_key_sealed_ollama': '',
    'ai_api_key_updated_at_ollama': '',
    'ai_base_url_gemini': '',
    'ai_base_url_deepseek': '',
    'ai_base_url_openrouter': '',
    'ai_base_url_ollama': '',
    'ai_model_gemini': '',
    'ai_model_deepseek': '',
    'ai_model_openrouter': '',
    'ai_model_ollama': '',
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

  /// Part du solde proposée par défaut pour un versement d'épargne (0 → 30 %).
  int get savingsGoalPercent =>
      integer('savings_goal_percent', fallback: 10).clamp(0, 30);

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

  /// Le libellé des montants est mis à jour **avant** la notification : les
  /// écrans déjà reconstruits et ceux qui lisent l'état global affichent la
  /// nouvelle devise dès la frame suivante, sans redémarrage.
  Future<void> setCurrency(AkibaCurrency value) async {
    AkibaMoney.currency = value.symbol;
    await set('currency', value.storageKey);
  }

  /// Langue d'interface (`fr` par défaut). Toute valeur inconnue retombe sur
  /// le français.
  String get language => raw('language') == 'en' ? 'en' : 'fr';

  /// Change la langue **et** l'applique tout de suite aux globales lues par
  /// les widgets déjà reconstruits (`AkibaL10n`, dates). La notification qui
  /// suit reconstruit `MaterialApp` (locale + traductions), donc l'interface
  /// bascule sans redémarrage. On ne passe pas par `set()` seul : sans cette
  /// synchronisation, un réglage écrit pendant l'onboarding laissait l'arbre
  /// en français jusqu'au prochain lancement.
  Future<void> setLanguage(String value) async {
    final String normalized = value.trim().toLowerCase() == 'en' ? 'en' : 'fr';
    AkibaL10n.setLanguage(normalized);
    AkibaDate.english = AkibaL10n.isEnglish;
    await set('language', normalized);
  }

  String get dateStyle => raw('date_style');

  @override
  void notifyListeners() {
    // Relit les formats globaux à chaque notification : un réglage change,
    // tout ce qui s'affiche ensuite (même hors arbre Flutter) est à jour.
    AkibaMoney.currency = currencyLabel;
    AkibaL10n.setLanguage(language);
    AkibaDate.english = AkibaL10n.isEnglish;
    super.notifyListeners();
  }

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
  bool get expenseReminderEnabled => flag('notif_expense');

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

  /// Valeur héritée uniquement : le jeton vit désormais dans le coffre du
  /// système (`SecureLabTokenStore`). Cette valeur est migrée puis effacée.
  String get labToken => raw('lab_token');

  /// Sauvegarde automatique Home Lab armée après validation du jeton.
  bool get labAutoBackup => flag('lab_auto_backup');

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
