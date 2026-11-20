import 'package:flutter/material.dart';

import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';
import '../theme/akiba_typography.dart';
import 'akiba_surface_card.dart';

/// Bloc de conseil IA : tuile d'icône 40 dp, titre 15 pt/600, texte 13 pt.
///
/// [highlight] est la portion du texte mise en valeur (chiffre clé coloré).
class AIInsightCard extends StatelessWidget {
  const AIInsightCard({
    super.key,
    required this.title,
    required this.message,
    this.highlight,
    this.icon = Icons.auto_awesome_rounded,
    this.footnote,
    this.onTap,
  });

  final String title;
  final String message;
  final String? highlight;
  final IconData icon;
  final String? footnote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final TextStyle body = AkibaTypography.body.copyWith(
      fontSize: 13,
      color: c.textMuted,
      height: 1.45,
    );

    return AkibaSurfaceCard(
      padding: const EdgeInsets.all(AkibaSpacing.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AkibaRadii.field),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.iconTile,
                    borderRadius: BorderRadius.circular(AkibaRadii.iconTile),
                  ),
                  child: Icon(icon, size: 20, color: c.terracotta),
                ),
                const SizedBox(width: AkibaSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          _buildMessage(body, c),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (footnote != null) ...<Widget>[
              const SizedBox(height: AkibaSpacing.md),
              Text(
                footnote!,
                style: AkibaTypography.legend.copyWith(
                  color: c.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  TextSpan _buildMessage(TextStyle body, AkibaColors c) {
    final String? key = highlight;
    if (key == null || key.isEmpty) return TextSpan(text: message, style: body);

    final int index = message.indexOf(key);
    if (index < 0) return TextSpan(text: message, style: body);

    return TextSpan(
      style: body,
      children: <InlineSpan>[
        TextSpan(text: message.substring(0, index)),
        TextSpan(
          text: key,
          style: body.copyWith(
            color: c.terracottaDeep,
            fontWeight: FontWeight.w700,
          ),
        ),
        TextSpan(text: message.substring(index + key.length)),
      ],
    );
  }
}
