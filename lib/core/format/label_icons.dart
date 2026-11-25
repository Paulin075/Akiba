import 'package:flutter/material.dart';

/// Icône déduite du libellé d'une opération ou d'un objectif d'épargne.
///
/// Aucune IA ni réseau : un simple dictionnaire de mots-clés français couvre
/// les achats courants (« moniteur », « écran », « moto », « téléphone »,
/// « loyer »…). Un libellé inconnu retombe sur l'icône de son type.
abstract final class LabelIcons {
  static final Map<IconData, List<String>> _rules = <IconData, List<String>>{
    Icons.monitor_rounded: <String>[
      'moniteur',
      'ecran',
      'écran',
      'ordinateur',
      'pc ',
      'desktop',
      'imprimante',
    ],
    Icons.laptop_mac_rounded: <String>['laptop', 'portable', 'macbook'],
    Icons.smartphone_rounded: <String>[
      'telephone',
      'téléphone',
      'smartphone',
      'portable',
      'iphone',
      'android',
    ],
    Icons.two_wheeler_rounded: <String>[
      'moto',
      'scooter',
      'motocyclette',
      'zémidjan',
      'zemidjan',
    ],
    Icons.pedal_bike_rounded: <String>['velo', 'vélo', 'bicyclette'],
    Icons.directions_car_rounded: <String>[
      'voiture',
      'auto',
      'vehicule',
      'véhicule',
      'taxi',
    ],
    Icons.home_rounded: <String>[
      'loyer',
      'maison',
      'appartement',
      'bail',
      'logement',
    ],
    Icons.kitchen_rounded: <String>[
      'frigo',
      'refrigerateur',
      'réfrigérateur',
      'cuisine',
      'cuisiniere',
      'cuisinière',
    ],
    Icons.bed_rounded: <String>['lit', 'matelas', 'chambre', 'literie'],
    Icons.school_rounded: <String>[
      'ecole',
      'école',
      'scolarite',
      'scolarité',
      'frais scolaires',
      'fournitures',
      'universite',
      'université',
    ],
    Icons.medical_services_rounded: <String>[
      'sante',
      'santé',
      'pharmacie',
      'medecin',
      'médecin',
      'hopital',
      'hôpital',
      'soin',
    ],
    Icons.restaurant_rounded: <String>[
      'repas',
      'manger',
      'nourriture',
      'restaurant',
      'dejeuner',
      'déjeuner',
      'provende',
    ],
    Icons.bolt_rounded: <String>[
      'electricite',
      'électricité',
      'courant',
      'facture',
    ],
    Icons.water_drop_rounded: <String>['eau', 'forage', 'tde'],
    Icons.checkroom_rounded: <String>[
      'vetement',
      'vêtement',
      'habit',
      'pagne',
      'couture',
      'chaussure',
    ],
    Icons.flight_takeoff_rounded: <String>[
      'voyage',
      'billet',
      'vol ',
      'avion',
      'vacances',
    ],
    Icons.favorite_rounded: <String>[
      'mariage',
      'dot',
      'fiancailles',
      'fiançailles',
    ],
    Icons.child_friendly_rounded: <String>[
      'bebe',
      'bébé',
      'enfant',
      'naissance',
    ],
    Icons.groups_rounded: <String>['tontine', 'cotisation', 'association'],
    Icons.construction_rounded: <String>[
      'terrain',
      'construction',
      'ciment',
      'travaux',
      'outil',
    ],
    Icons.celebration_rounded: <String>['fete', 'fête', 'anniversaire'],
  };

  /// Icône d'une **catégorie** de budget ou de dépense.
  ///
  /// Une catégorie a une icône unique et lisible, la même dans Analyses, le
  /// budget et les ventilations : alimentation, transport, logement, santé,
  /// école, loisirs, épargne, factures, autre…
  static IconData forCategory(
    String? category, {
    IconData fallback = Icons.category_outlined,
  }) {
    if (category == null || category.trim().isEmpty) return fallback;
    final String key = _normalise(category);
    final IconData? exact = _categories[key];
    if (exact != null) return exact;
    // Repli sur les mots-clés du libellé (« Loyer mai », « Santé famille »).
    return forText(category, fallback: fallback);
  }

  static const Map<String, IconData> _categories = <String, IconData>{
    'alimentation': Icons.restaurant_rounded,
    'nourriture': Icons.restaurant_rounded,
    'repas': Icons.restaurant_rounded,
    'transport': Icons.directions_car_rounded,
    'deplacement': Icons.directions_car_rounded,
    'loyer': Icons.home_rounded,
    'logement': Icons.home_rounded,
    'maison': Icons.home_rounded,
    'sante': Icons.medical_services_rounded,
    'ecole': Icons.school_rounded,
    'education': Icons.school_rounded,
    'scolarite': Icons.school_rounded,
    'loisirs': Icons.celebration_rounded,
    'sorties': Icons.celebration_rounded,
    'epargne': Icons.savings_rounded,
    'factures': Icons.receipt_long_rounded,
    'services': Icons.receipt_long_rounded,
    'tontine': Icons.groups_rounded,
    'salaire': Icons.payments_rounded,
    'vente': Icons.storefront_rounded,
    'don': Icons.volunteer_activism_rounded,
    'autre': Icons.more_horiz_rounded,
  };

  /// Minuscules sans accents : « Santé » et « sante » donnent la même icône.
  static String _normalise(String value) {
    final StringBuffer out = StringBuffer();
    for (final int unit in value.toLowerCase().runes) {
      final String char = String.fromCharCode(unit);
      out.write(_accents[char] ?? char);
    }
    return out.toString().trim();
  }

  static const Map<String, String> _accents = <String, String>{
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'ô': 'o',
    'ö': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'œ': 'oe',
  };

  /// Icône correspondant au texte ; `fallback` si aucun mot-clé ne correspond.
  static IconData forText(
    String? text, {
    IconData fallback = Icons.savings_rounded,
  }) {
    if (text == null || text.trim().isEmpty) return fallback;
    final String lower = text.toLowerCase();
    for (final MapEntry<IconData, List<String>> rule in _rules.entries) {
      for (final String word in rule.value) {
        if (lower.contains(word)) return rule.key;
      }
    }
    return fallback;
  }
}
