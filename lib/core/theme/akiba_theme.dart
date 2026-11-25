import 'package:flutter/material.dart';

import 'akiba_colors.dart';
import 'akiba_tokens.dart';
import 'akiba_typography.dart';

/// Les cinq thèmes persistants d'AKIBA.
///
/// L'ordre de l'énumération est celui du sélecteur du Profil : Blanc
/// (par défaut), Sombre, Bleu, Vert, Jaune Or. Chaque thème porte sa propre
/// palette, donc son contraste, sa barre basse et ses boutons latéraux ; aucun
/// réglage n'est partagé entre deux thèmes.
enum AkibaThemeId {
  blanc('blanc', 'Blanc', AkibaColors.blanc),
  sombre('sombre', 'Sombre', AkibaColors.sombre),
  bleu('bleu', 'Bleu', AkibaColors.bleu),
  vert('vert', 'Vert', AkibaColors.vert),
  or('or', 'Jaune Or', AkibaColors.or);

  const AkibaThemeId(this.storageKey, this.label, this.palette);

  /// Valeur écrite dans la table `settings` (base chiffrée).
  final String storageKey;

  /// Libellé affiché dans le sélecteur d'apparence.
  final String label;

  /// Palette complète du thème.
  final AkibaColors palette;

  Brightness get brightness =>
      palette.isDark ? Brightness.dark : Brightness.light;

  /// Relit un thème enregistré ; toute valeur inconnue retombe sur Blanc
  /// (aucun écran ne peut rester sans thème).
  static AkibaThemeId fromStorage(String? value) {
    for (final AkibaThemeId id in values) {
      if (id.storageKey == value) return id;
    }
    return AkibaThemeId.blanc;
  }
}

/// Thèmes AKIBA : cinq palettes, une seule construction de `ThemeData`.
abstract final class AkibaTheme {
  static ThemeData light() => forId(AkibaThemeId.blanc);

  static ThemeData dark() => forId(AkibaThemeId.sombre);

  static ThemeData forId(AkibaThemeId id) => _build(id.palette, id.brightness);

  static ThemeData _build(AkibaColors c, Brightness brightness) {
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: c.terracotta,
      onPrimary: c.onTerracotta,
      primaryContainer: c.iconTile,
      onPrimaryContainer: c.textPrimary,
      secondary: c.ochre,
      onSecondary: c.textPrimary,
      error: c.danger,
      onError: c.onTerracotta,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceElevated,
      outline: c.textMuted,
      outlineVariant: c.surfaceElevated,
    );

    final ThemeData base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AkibaTypography.uiFont,
      fontFamilyFallback: AkibaTypography.fallback,
    );

    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      textTheme: AkibaTypography.textTheme(
        c,
      ).apply(bodyColor: c.textPrimary, displayColor: c.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AkibaTypography.screenTitle.copyWith(
          color: c.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AkibaRadii.card),
        ),
      ),
      iconTheme: IconThemeData(color: c.textMuted, size: 22),
      // Texte saisi lisible dans **tous** les thèmes : couleur de la palette,
      // curseur et sélection contrastés, champ rempli avec la surface élevée.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceElevated,
        // Le texte saisi hérite du `textTheme` appliqué à la palette ci-dessus;
        // hint, labels et icônes gardent ici leurs couleurs dédiées.
        hintStyle: AkibaTypography.body.copyWith(
          color: c.textMuted.withValues(alpha: 0.85),
        ),
        labelStyle: AkibaTypography.body.copyWith(color: c.textMuted),
        floatingLabelStyle: AkibaTypography.body.copyWith(
          color: c.terracotta,
          fontWeight: FontWeight.w600,
        ),
        counterStyle: AkibaTypography.legend.copyWith(color: c.textMuted),
        helperStyle: AkibaTypography.legend.copyWith(color: c.textMuted),
        errorStyle: AkibaTypography.legend.copyWith(color: c.danger),
        prefixIconColor: c.textMuted,
        suffixIconColor: c.textMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AkibaSpacing.md,
          vertical: AkibaSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AkibaRadii.field),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AkibaRadii.field),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AkibaRadii.field),
          borderSide: BorderSide(color: c.terracotta, width: 1.6),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.terracotta,
        selectionColor: c.terracotta.withValues(alpha: 0.25),
        selectionHandleColor: c.terracotta,
      ),
      // `DefaultTextStyle` de secours pour les widgets qui ne passent pas par
      // le `TextTheme` (champs personnalisés, dialogues).
      extensions: <ThemeExtension<dynamic>>[c],
      primaryColor: c.terracotta,
      hintColor: c.textMuted,
      dividerTheme: const DividerThemeData(
        color: Colors.transparent,
        thickness: 0,
        space: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.textPrimary,
        contentTextStyle: AkibaTypography.body.copyWith(color: c.background),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AkibaRadii.field),
        ),
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
  }
}
