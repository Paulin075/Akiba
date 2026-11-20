import 'package:flutter/widgets.dart';

import 'akiba_settings.dart';

/// Traductions appliquées à la navigation et aux actions principales.
///
/// Le français reste la langue de référence et de tous les écrans détaillés.
/// L'anglais couvre la barre basse, l'accueil et les actions rapides, pour que
/// le choix de langue de l'onboarding ait un effet immédiat et vérifiable.
abstract final class AkibaL10n {
  static const Map<String, Map<String, String>> _values =
      <String, Map<String, String>>{
        'fr': <String, String>{
          'nav_home': 'Accueil',
          'nav_analysis': 'Analyses',
          'nav_wallet': 'Portefeuille',
          'nav_profile': 'Profil',
          'hello': 'Bonjour',
          'add': 'Ajouter',
          'transfer': 'Transférer',
          'see_all': 'Voir tout',
          'welcome': 'Bienvenue',
        },
        'en': <String, String>{
          'nav_home': 'Home',
          'nav_analysis': 'Insights',
          'nav_wallet': 'Wallet',
          'nav_profile': 'Profile',
          'hello': 'Hello',
          'add': 'Add',
          'transfer': 'Transfer',
          'see_all': 'See all',
          'welcome': 'Welcome',
        },
      };

  static String languageOf(BuildContext context) =>
      AkibaSettingsScope.maybeOf(context)?.raw('language') ?? 'fr';

  static String t(BuildContext context, String key) {
    final String language = languageOf(context);
    return _values[language]?[key] ?? _values['fr']![key] ?? key;
  }
}
