/// Jetons non chromatiques du design system AKIBA.
///
/// Échelle d'espacement : 4, 8, 12, 16, 20, 24, 32 dp.
/// Marge d'écran 20 dp, entre blocs 24 dp, entre éléments liés 12 dp.
abstract final class AkibaSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Marge horizontale des écrans.
  static const double screen = 20;
}

abstract final class AkibaRadii {
  /// Carte de solde.
  static const double hero = 28;

  /// Cartes, feuilles, tuiles de mosaïque.
  static const double card = 24;

  /// Tuiles de mosaïque Paramètres.
  static const double tile = 24;

  /// Icônes en tuile.
  static const double iconTile = 14;

  /// Champs de saisie.
  static const double field = 16;

  /// Boutons, puces, segmented control : forme pilule.
  static const double pill = 999;
}

abstract final class AkibaSizes {
  /// Zone tactile minimale.
  static const double touchTarget = 48;

  /// Bouton Akiba (cochon) : 64 dp dans le cahier des charges.
  static const double akibaButton = 64;

  /// Hauteur de contenu de la barre de navigation basse (hors safe area).
  static const double bottomBar = 64;

  /// Petite icône Assistant IA au-dessus du bouton cochon.
  static const double sideAiButton = 44;

  /// Bouton cochon flottant sur le côté droit.
  static const double pigButton = 56;
}

abstract final class AkibaDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration page = Duration(milliseconds: 250);
  static const Duration sheet = Duration(milliseconds: 300);
  static const Duration cauri = Duration(milliseconds: 400);

  /// Ouverture : l'animation seule, 1 s au total avant l'accès à l'app.
  static const Duration splash = Duration(seconds: 1);

  /// Versement d'épargne : le geste complet cochon + cauri, 3 secondes.
  static const Duration cauriDrop = Duration(seconds: 3);
  static const Duration float = Duration(seconds: 3);
}
