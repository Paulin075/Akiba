import 'package:flutter/material.dart';

import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';

/// Variantes de couleur d'une `ActionPill`.
enum ActionPillTone { ochre, white, terracotta }

/// Pilule d'action 48 dp : icône 20 dp + libellé 14 pt/600.
class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.icon,
    required this.label,
    this.tone = ActionPillTone.ochre,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final ActionPillTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final (Color background, Color foreground) = switch (tone) {
      ActionPillTone.ochre => (c.ochre, c.textPrimary),
      ActionPillTone.white => (Colors.white, c.terracottaDeep),
      ActionPillTone.terracotta => (c.terracotta, c.onTerracotta),
    };

    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: AkibaSizes.touchTarget,
        child: Material(
          color: background,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AkibaSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(width: AkibaSpacing.sm),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
