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
