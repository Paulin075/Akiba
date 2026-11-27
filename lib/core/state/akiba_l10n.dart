import 'package:flutter/widgets.dart';

import 'akiba_settings.dart';

/// Traductions AKIBA (français de référence, anglais).
///
/// La langue est portée par une valeur statique, appliquée au build racine en
/// même temps que le format des montants (`AkibaMoney.currency`). Ainsi, un
/// changement de langue se propage à toute l'arborescence sans dépendre d'un
/// `BuildContext` : les widgets qui reconstruisent lisent la nouvelle table.
///
/// Ce qui est couvert : navigation, accueil, profil/réglages et formatage des
/// dates. Les écrans métier détaillés (Analyses, Portefeuille, saisie rapide,
/// onboarding) restent en français.
abstract final class AkibaL10n {
  /// Langues proposées dans les réglages.
  static const List<String> supported = <String>['fr', 'en'];

  static String _language = 'fr';

  static String get language => _language;

  static bool get isEnglish => _language == 'en';

  /// Normalise et enregistre la langue active. Toute valeur inconnue retombe
  /// sur le français.
  static void setLanguage(String? value) {
    final String normalized = (value ?? '').trim().toLowerCase();
    _language = supported.contains(normalized) ? normalized : 'fr';
  }

  static const Map<String, Map<String, String>>
  _values = <String, Map<String, String>>{
    'fr': <String, String>{
      // Navigation et coquille
      'nav_home': 'Accueil',
      'nav_analysis': 'Analyses',
      'nav_wallet': 'Portefeuille',
      'nav_profile': 'Profil',
      'sim_banner': 'Mode simulation · données d’essai locales',
      'ai_assistant': 'Assistant IA',
      'quick_add': 'Ajout rapide',
      'pig_semantics':
          'Ajout rapide. Toucher pour ajouter, maintenir pour parler.',
      // Accueil
      'my_money': 'Mon argent',
      'show_amounts': 'Afficher les montants',
      'hide_amounts': 'Masquer les montants',
      'appearance_tooltip': 'Apparence : {theme}',
      'ai_preview': 'Aperçu IA',
      'ai_footnote': 'Conseils personnalisés · module M12',
      'third_party': 'Argent de tiers',
      'third_party_short': 'Tiers',
      'isolated': 'Isolé',
      'none': 'Aucun',
      'third_party_note':
          'Cet argent transite par vos comptes mais ne vous appartient '
          'pas : il est exclu du budget, de l’épargne et des statistiques.',
      'total_accounts': 'Total des comptes',
      'savings_vault': 'Épargne (coffre)',
      'available_balance': 'Solde disponible',
      'quick_actions': 'Actions rapides',
      'entry': 'Entrée',
      'expense': 'Sortie',
      'transfer': 'Transfert',
      'savings': 'Épargne',
      'latest_transactions': 'Dernières transactions',
      'see_all': 'Voir tout',
      'edit': 'Modifier',
      'delete': 'Supprimer',
      'swipe_hint':
          'Glissez une ligne pour la modifier (droite) ou la supprimer '
          '(gauche).',
      'no_movement': 'Aucun mouvement pour l’instant',
      'no_movement_note':
          'Touchez le cochon AKIBA pour ajouter votre première ligne.',
      'movement_deleted': 'Mouvement supprimé',
      'delete_failed':
          'Suppression impossible : le mouvement est conservé. Réessayez.',
      'cancel': 'Annuler',
      'planned_in': '{label} — prévu en {phase}.',
      'db_unreadable': 'Base locale illisible',
      'db_unreadable_note':
          'La base chiffrée n’a pas pu être ouverte. Vos données ne sont '
          'pas modifiées.',
      'retry': 'Réessayer',
      'available_balance_caps': 'SOLDE DISPONIBLE',
      'accounts_savings_third':
          'Comptes {accounts} + épargne {savings} '
          '− tiers {third}',
      'accounts_savings_third_masked': 'Comptes + épargne − argent de tiers',
      'transfer_action': 'Transférer',
      'add_action': 'Ajouter',
      // Aperçus
      'insight_welcome_title': 'Bienvenue dans AKIBA',
      'insight_welcome_message':
          'Touchez le cochon pour enregistrer une première entrée : vos '
          'tendances et vos conseils apparaîtront ici.',
      'insight_masked_title': 'Vos chiffres restent privés',
      'insight_masked_message':
          'Le masquage est actif : aucun montant ne s’affiche, y compris '
          'dans cet aperçu.',
      'insight_month_title': 'Votre mois en un regard',
      'insight_month_message':
          'Vous avez dépensé {amount} ce mois-ci, hors argent de tiers. '
          'Le détail par catégorie est dans Analyses.',
      'insight_none_title': 'Aucune sortie ce mois-ci',
      'insight_none_message':
          'Rien n’a été dépensé depuis le début du mois. C’est le bon '
          'moment pour verser un peu au coffre épargne.',
      // Mouvements
      'third_party_money': 'Argent de tiers',
      'opening_balance': 'Solde de départ',
      // Profil et réglages
      'profile_label': 'PROFIL',
      'my_profile': 'Votre profil',
      'change_photo': 'Changer la photo',
      'add_photo': 'Ajouter une photo',
      'remove': 'Retirer',
      'security': 'Sécurité',
      'privacy': 'Confidentialité',
      'appearance': 'Apparence',
      'preferences': 'Préférences',
      'daily_reminders': 'Rappels quotidiens',
      'sms_title': 'SMS financiers',
      'backup_sync': 'Sauvegarde & synchronisation',
      'data_demo': 'Données & démonstration',
      'theme': 'Thème',
      'currency': 'Devise',
      'language': 'Langue',
      'language_note':
          'La langue s’applique immédiatement à la navigation, à '
          'l’accueil et aux réglages.',
      'dates': 'Dates',
      'timezone': 'Fuseau',
      'currency_note':
          'Seul l’affichage change : aucun taux de change n’est appliqué '
          'aux montants.',
      'timezone_note':
          'Le fuseau sert aux rappels ; les dates restent celles de '
          'l’appareil.',
      'appearance_note':
          'L’aperçu est immédiat : palettes à contraste élevé, logos '
          'officiels intacts, barre basse ancrée et boutons latéraux '
          'identiques dans les cinq thèmes.',
      'reduce_animations': 'Réduire les animations',
      // Onboarding : la langue doit être visible immédiatement.
      'continue_label': 'Continuer',
      'back_label': 'Retour',
      'enter_app': 'Entrer dans AKIBA',
      'step_of': 'Étape {step} sur {total}',
      'language_heading': 'Votre langue',
      'language_immediate':
          'La langue s’applique immédiatement, y compris pendant ce '
          'parcours. Tout reste enregistré.',
      'theme_heading': 'Votre thème',
      'theme_immediate':
          'Il s’applique immédiatement à ce parcours et reste enregistré.',
      // Dates
      'today': "Aujourd'hui",
      'yesterday': 'Hier',
    },
    'en': <String, String>{
      'nav_home': 'Home',
      'nav_analysis': 'Insights',
      'nav_wallet': 'Wallet',
      'nav_profile': 'Profile',
      'sim_banner': 'Simulation mode · local test data',
      'ai_assistant': 'AI assistant',
      'quick_add': 'Quick add',
      'pig_semantics': 'Quick add. Tap to add, hold to speak.',
      'my_money': 'My money',
      'show_amounts': 'Show amounts',
      'hide_amounts': 'Hide amounts',
      'appearance_tooltip': 'Theme: {theme}',
      'ai_preview': 'AI preview',
      'ai_footnote': 'Personal tips · M12 module',
      'third_party': 'Third-party money',
      'third_party_short': 'Third party',
      'isolated': 'Isolated',
      'none': 'None',
      'third_party_note':
          'This money passes through your accounts but is not yours: it '
          'is excluded from budget, savings and statistics.',
      'total_accounts': 'Total accounts',
      'savings_vault': 'Savings (vault)',
      'available_balance': 'Available balance',
      'quick_actions': 'Quick actions',
      'entry': 'Income',
      'expense': 'Expense',
      'transfer': 'Transfer',
      'savings': 'Savings',
      'latest_transactions': 'Latest transactions',
      'see_all': 'See all',
      'edit': 'Edit',
      'delete': 'Delete',
      'swipe_hint': 'Swipe a row right to edit it, left to delete it.',
      'no_movement': 'No transactions yet',
      'no_movement_note': 'Tap the AKIBA pig to add your first entry.',
      'movement_deleted': 'Transaction deleted',
      'delete_failed':
          'Could not delete: the transaction is kept. Please try again.',
      'cancel': 'Cancel',
      'planned_in': '{label} — planned for {phase}.',
      'db_unreadable': 'Local database unreadable',
      'db_unreadable_note':
          'The encrypted database could not be opened. Your data is '
          'unchanged.',
      'retry': 'Try again',
      'available_balance_caps': 'AVAILABLE BALANCE',
      'accounts_savings_third':
          'Accounts {accounts} + savings {savings} − third party {third}',
      'accounts_savings_third_masked': 'Accounts + savings − third-party money',
      'transfer_action': 'Transfer',
      'add_action': 'Add',
      'insight_welcome_title': 'Welcome to AKIBA',
      'insight_welcome_message':
          'Tap the pig to record your first income: your trends and tips '
          'will appear here.',
      'insight_masked_title': 'Your figures stay private',
      'insight_masked_message':
          'Masking is on: no amount is shown, including in this preview.',
      'insight_month_title': 'Your month at a glance',
      'insight_month_message':
          'You spent {amount} this month, excluding third-party money. '
          'The breakdown by category is in Insights.',
      'insight_none_title': 'No spending this month',
      'insight_none_message':
          'Nothing has been spent since the start of the month. A good '
          'time to put a little into the savings vault.',
      'third_party_money': 'Third-party money',
      'opening_balance': 'Opening balance',
      'profile_label': 'PROFILE',
      'my_profile': 'Your profile',
      'change_photo': 'Change photo',
      'add_photo': 'Add a photo',
      'remove': 'Remove',
      'security': 'Security',
      'privacy': 'Privacy',
      'appearance': 'Appearance',
      'preferences': 'Preferences',
      'daily_reminders': 'Daily reminders',
      'sms_title': 'Bank SMS',
      'backup_sync': 'Backup & sync',
      'data_demo': 'Data & demo',
      'theme': 'Theme',
      'currency': 'Currency',
      'language': 'Language',
      'language_note':
          'The language applies immediately to navigation, home and '
          'settings.',
      'dates': 'Dates',
      'timezone': 'Time zone',
      'currency_note': 'Display only: no exchange rate is applied to amounts.',
      'timezone_note':
          'The time zone drives reminders; dates stay those of the '
          'device.',
      'appearance_note':
          'The preview is immediate: high-contrast palettes, untouched '
          'official logos, anchored bottom bar and identical side buttons '
          'across all five themes.',
      'reduce_animations': 'Reduce animations',
      'continue_label': 'Continue',
      'back_label': 'Back',
      'enter_app': 'Enter AKIBA',
      'step_of': 'Step {step} of {total}',
      'language_heading': 'Your language',
      'language_immediate':
          'The language applies immediately, including during this '
          'setup. Everything stays saved.',
      'theme_heading': 'Your theme',
      'theme_immediate':
          'It applies to this setup immediately and stays saved.',
      'today': 'Today',
      'yesterday': 'Yesterday',
    },
  };

  /// Traduction d'une clé, avec remplacement des jetons `{nom}`.
  static String tr(
    String key, [
    Map<String, String> params = const <String, String>{},
  ]) {
    String value = _values[_language]?[key] ?? _values['fr']![key] ?? key;
    for (final MapEntry<String, String> entry in params.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  }

  /// Langue lue dans les réglages, pour les widgets déjà liés au périmètre.
  static String languageOf(BuildContext context) =>
      AkibaSettingsScope.maybeOf(context)?.raw('language') ?? _language;

  static String t(BuildContext context, String key) {
    final String language = languageOf(context);
    return _values[language]?[key] ?? _values['fr']![key] ?? key;
  }
}
