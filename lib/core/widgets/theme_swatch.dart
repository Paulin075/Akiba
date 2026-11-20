import 'package:flutter/material.dart';

import '../theme/akiba_colors.dart';
import '../theme/akiba_theme.dart';
import '../theme/akiba_tokens.dart';

/// Pastille d'un thème : aperçu immédiat de la palette et sélection.
///
/// La pastille montre le fond, la surface et la couleur d'action du thème ;
/// le libellé reste lisible sur le thème courant, donc quel que soit le
/// thème choisi. Rien n'est appliqué avant l'appui : l'appui lui-même écrit le
/// réglage, et l'arbre se reconstruit immédiatement avec la nouvelle palette.
class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch({
    super.key,
    required this.id,
    required this.selected,
    required this.onTap,
  });

  final AkibaThemeId id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final AkibaColors palette = id.palette;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Thème ${id.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AkibaRadii.field),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AkibaSpacing.xs,
            vertical: AkibaSpacing.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: palette.background,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? c.terracotta : c.surfaceElevated,
                    width: selected ? 2.5 : 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: palette.terracotta,
                    shape: BoxShape.circle,
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: palette.onTerracotta,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: AkibaSpacing.xs),
              Text(
                id.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? c.textPrimary : c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
