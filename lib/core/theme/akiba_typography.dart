import 'package:flutter/material.dart';

import 'akiba_colors.dart';

/// Typographie AKIBA.
///
/// Poppins pour les titres et le corps (identité du logo), Inter avec chiffres
/// tabulaires pour les montants, pourcentages et heures.
///
/// Les fichiers de police ne sont pas encore embarqués dans le projet : les
/// familles sont déclarées avec un repli système, en attendant le jalon
/// « polices embarquées » du plan (Phase 1, Étape 1.5).
abstract final class AkibaTypography {
  static const String uiFont = 'Poppins';
  static const String moneyFont = 'Inter';
  static const List<String> fallback = <String>[
    'Inter',
    'Segoe UI',
    'Roboto',
    'Arial',
  ];

  /// Style de montant : chiffres tabulaires, alignement des colonnes garanti.
  static TextStyle money(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = 0.2,
  }) {
    return TextStyle(
      fontFamily: moneyFont,
      fontFamilyFallback: fallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: 1.15,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }

  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  static const TextStyle legend = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle rowAmount = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle screenTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
  );

  /// Échelle de texte du thème (couleurs appliquées depuis la palette).
  static TextTheme textTheme(AkibaColors c) {
    return TextTheme(
      displaySmall: money(36, color: c.textPrimary),
      headlineSmall: screenTitle,
      titleMedium: sectionTitle,
      // `bodyLarge` est le style par défaut du texte saisi dans un TextField :
      // il doit porter la couleur de la palette, sinon le texte reste blanc et
      // illisible sur les thèmes clairs et colorés.
      bodyLarge: body,
      titleSmall: rowAmount,
      bodyMedium: body,
      bodySmall: legend,
      labelSmall: label,
      labelLarge: body,
    ).apply(
      fontFamily: uiFont,
      fontFamilyFallback: fallback,
      bodyColor: c.textPrimary,
      displayColor: c.textPrimary,
    );
  }
}
