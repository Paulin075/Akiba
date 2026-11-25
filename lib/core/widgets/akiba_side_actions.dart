import 'package:flutter/material.dart';

import '../state/akiba_l10n.dart';
import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';

/// Boutons d'action flottants de la colonne de droite.
///
/// Règles en dur : le bouton d'ajout rapide est l'emblème cochon AKIBA avec
/// son cauri, placé sur le côté droit au-dessus de la barre de navigation
/// (jamais au centre de la barre), et la petite icône de l'Assistant IA se
/// trouve juste au-dessus du cochon.
class AkibaSideActions extends StatelessWidget {
  const AkibaSideActions({
    super.key,
    this.onAdd,
    this.onLongPressAdd,
    this.onAssistant,
  });

  final VoidCallback? onAdd;
  final VoidCallback? onLongPressAdd;
  final VoidCallback? onAssistant;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _CircleAction(
          size: AkibaSizes.sideAiButton,
          background: c.terracotta,
          foreground: c.onTerracotta,
          tooltip: AkibaL10n.tr('ai_assistant'),
          semanticLabel: AkibaL10n.tr('ai_assistant'),
          onTap: onAssistant,
          child: const Icon(Icons.auto_awesome_rounded, size: 20),
        ),
        const SizedBox(height: AkibaSpacing.md),
        _PigAction(onTap: onAdd, onLongPress: onLongPressAdd),
      ],
    );
  }
}

class _PigAction extends StatelessWidget {
  const _PigAction({this.onTap, this.onLongPress});

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Semantics(
      button: true,
      label: AkibaL10n.tr('pig_semantics'),
      child: Tooltip(
        message: AkibaL10n.tr('quick_add'),
        child: Container(
          width: AkibaSizes.pigButton,
          height: AkibaSizes.pigButton,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface,
            boxShadow: c.floatingShadow,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Image.asset(
                  c.isDark
                      ? 'assets/brand/akiba_mark_dark.png'
                      : 'assets/brand/akiba_mark_light.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                  errorBuilder:
                      (
                        BuildContext context,
                        Object error,
                        StackTrace? stackTrace,
                      ) => Icon(Icons.savings_rounded, color: c.terracotta),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.size,
    required this.background,
    required this.foreground,
    required this.tooltip,
    required this.semanticLabel,
    required this.child,
    this.onTap,
  });

  final double size;
  final Color background;
  final Color foreground;
  final String tooltip;
  final String semanticLabel;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: background,
            boxShadow: c.floatingShadow,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: IconTheme(
                data: IconThemeData(color: foreground),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
