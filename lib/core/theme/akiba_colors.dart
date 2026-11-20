import 'package:flutter/material.dart';

/// Palette AKIBA.
///
/// Cinq palettes persistantes : Blanc (par défaut, maquette de référence),
/// Sombre, Bleu, Vert et Jaune Or. Chaque palette garde un contraste élevé
/// (texte principal ≥ 12:1 sur le fond, texte secondaire ≥ 5:1, texte clair
/// ≥ 5:1 sur la couleur d'action) pour rester lisible en plein soleil comme
/// la nuit. Exposée via `ThemeExtension`, donc accessible par
/// `AkibaColors.of(context)`.
@immutable
class AkibaColors extends ThemeExtension<AkibaColors> {
  const AkibaColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.iconTile,
    required this.terracotta,
    required this.terracottaDeep,
    required this.ochre,
    required this.sand,
    required this.textPrimary,
    required this.textMuted,
    required this.onTerracotta,
    required this.success,
    required this.warning,
    required this.danger,
    required this.isDark,
  });

  /// Fond d'application.
  final Color background;

  /// Cartes, listes, barre d'onglets.
  final Color surface;

  /// Champs, puces non sélectionnées, blocs d'indicateurs.
  final Color surfaceElevated;

  /// Fond des icônes de catégories et d'actions.
  final Color iconTile;

  /// Action principale, onglet actif, alertes.
  final Color terracotta;

  /// Fin du dégradé de la carte de solde.
  final Color terracottaDeep;

  /// Boutons secondaires, jauges neutres, accents.
  final Color ochre;

  /// Montants sur surfaces sombres ou terre cuite, valeurs clés.
  final Color sand;

  /// Titres, montants.
  final Color textPrimary;

  /// Sous-titres, aides, libellés.
  final Color textMuted;

  /// Texte sur la carte de solde.
  final Color onTerracotta;

  final Color success;
  final Color warning;
  final Color danger;

  /// En sombre, aucune ombre : le relief vient de la teinte uniquement.
  final bool isDark;

  /// Thème **Blanc** (par défaut) : crème et terre cuite de la maquette.
  static const AkibaColors blanc = AkibaColors(
    background: Color(0xFFFAF4E6),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF3E9D6),
    iconTile: Color(0xFFF1DFC8),
    terracotta: Color(0xFFC7673D),
    terracottaDeep: Color(0xFF9E4B27),
    ochre: Color(0xFFC69F47),
    sand: Color(0xFFE8D5A8),
    textPrimary: Color(0xFF1A1816),
    textMuted: Color(0xFF6F685B),
    onTerracotta: Color(0xFFFFF8EC),
    success: Color(0xFF5E9E6E),
    warning: Color(0xFFE0963A),
    danger: Color(0xFFC94B3F),
    isDark: false,
  );

  /// Thème **Sombre** : noir chaud, aucun relief par ombre.
  static const AkibaColors sombre = AkibaColors(
    background: Color(0xFF0E0D0C),
    surface: Color(0xFF1A1816),
    surfaceElevated: Color(0xFF24211E),
    iconTile: Color(0xFF2E2A26),
    terracotta: Color(0xFFC7673D),
    terracottaDeep: Color(0xFF9E4B27),
    ochre: Color(0xFFC69F47),
    sand: Color(0xFFE8D5A8),
    textPrimary: Color(0xFFF3EEE2),
    textMuted: Color(0xFFA59E90),
    onTerracotta: Color(0xFFFFF8EC),
    success: Color(0xFF5E9E6E),
    warning: Color(0xFFE0963A),
    danger: Color(0xFFC94B3F),
    isDark: true,
  );

  /// Thème **Bleu** : bleu profond sur fond bleu glacier.
  static const AkibaColors bleu = AkibaColors(
    background: Color(0xFFEAF1FA),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFDCE8F7),
    iconTile: Color(0xFFCBDDF3),
    terracotta: Color(0xFF1E5FA8),
    terracottaDeep: Color(0xFF17477C),
    ochre: Color(0xFF6E9FD6),
    sand: Color(0xFFBFD6EF),
    textPrimary: Color(0xFF14202E),
    textMuted: Color(0xFF4E5F72),
    onTerracotta: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D4F),
    warning: Color(0xFFA96110),
    danger: Color(0xFFB23A2E),
    isDark: false,
  );

  /// Thème **Vert** : vert forêt sur fond végétal très clair.
  static const AkibaColors vert = AkibaColors(
    background: Color(0xFFEDF6EE),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFDDEDDF),
    iconTile: Color(0xFFCBE3CE),
    terracotta: Color(0xFF1F6B3A),
    terracottaDeep: Color(0xFF17502C),
    ochre: Color(0xFF6F9E7C),
    sand: Color(0xFFBFDCC4),
    textPrimary: Color(0xFF102315),
    textMuted: Color(0xFF3F5B47),
    onTerracotta: Color(0xFFFFFFFF),
    success: Color(0xFF1F6B3A),
    warning: Color(0xFFA96110),
    danger: Color(0xFFB23A2E),
    isDark: false,
  );

  /// Thème **Jaune Or** : or profond sur crème doré.
  static const AkibaColors or = AkibaColors(
    background: Color(0xFFFBF6E4),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF6EDD2),
    iconTile: Color(0xFFEFE0BA),
    terracotta: Color(0xFF8A6414),
    terracottaDeep: Color(0xFF6B4A0C),
    ochre: Color(0xFFC69F47),
    sand: Color(0xFFEAD8A6),
    textPrimary: Color(0xFF241C08),
    textMuted: Color(0xFF5F5330),
    onTerracotta: Color(0xFFFFFDF6),
    success: Color(0xFF2E7D4F),
    warning: Color(0xFF8A5A10),
    danger: Color(0xFFB23A2E),
    isDark: false,
  );

  /// Ancien nom du thème clair, conservé pour les appels existants.
  static const AkibaColors light = blanc;

  /// Ancien nom du thème sombre, conservé pour les appels existants.
  static const AkibaColors dark = sombre;

  /// Accès à la palette depuis un contexte (repli blanc si l'extension manque).
  static AkibaColors of(BuildContext context) =>
      Theme.of(context).extension<AkibaColors>() ?? blanc;

  /// Dégradé 135° de la carte de solde.
  LinearGradient get balanceGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [terracotta, terracottaDeep],
  );

  List<BoxShadow> get cardShadow => isDark
      ? const <BoxShadow>[]
      : const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F1A1816),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ];

  List<BoxShadow> get heroShadow => isDark
      ? const <BoxShadow>[]
      : const <BoxShadow>[
          BoxShadow(
            color: Color(0x479E4B27),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ];

  /// Ombre des boutons flottants latéraux.
  List<BoxShadow> get floatingShadow => isDark
      ? const <BoxShadow>[]
      : const <BoxShadow>[
          BoxShadow(
            color: Color(0x1F1A1816),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ];

  /// Relief de la barre de navigation ancrée en bas.
  List<BoxShadow> get barShadow => isDark
      ? const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ]
      : const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F1A1816),
            blurRadius: 20,
            offset: Offset(0, -6),
          ),
        ];

  @override
  AkibaColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? iconTile,
    Color? terracotta,
    Color? terracottaDeep,
    Color? ochre,
    Color? sand,
    Color? textPrimary,
    Color? textMuted,
    Color? onTerracotta,
    Color? success,
    Color? warning,
    Color? danger,
    bool? isDark,
  }) {
    return AkibaColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      iconTile: iconTile ?? this.iconTile,
      terracotta: terracotta ?? this.terracotta,
      terracottaDeep: terracottaDeep ?? this.terracottaDeep,
      ochre: ochre ?? this.ochre,
      sand: sand ?? this.sand,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      onTerracotta: onTerracotta ?? this.onTerracotta,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AkibaColors lerp(covariant AkibaColors? other, double t) {
    if (other == null) return this;
    return AkibaColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      iconTile: Color.lerp(iconTile, other.iconTile, t)!,
      terracotta: Color.lerp(terracotta, other.terracotta, t)!,
      terracottaDeep: Color.lerp(terracottaDeep, other.terracottaDeep, t)!,
      ochre: Color.lerp(ochre, other.ochre, t)!,
      sand: Color.lerp(sand, other.sand, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      onTerracotta: Color.lerp(onTerracotta, other.onTerracotta, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
