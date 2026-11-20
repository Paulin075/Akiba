import 'package:flutter/material.dart';

import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';
import '../theme/akiba_typography.dart';

/// Ligne de transaction : avatar 44 dp, titre, sous-titre, montant aligné.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    required this.amountColor,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String amountLabel;
  final Color amountColor;

  /// Pastille discrète (« Tiers », « Épargne »…).
  final String? badge;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Semantics(
      button: onTap != null,
      label: '$title, $subtitle, $amountLabel',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AkibaRadii.field),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AkibaSpacing.md),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.iconTile,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: c.terracotta),
              ),
              const SizedBox(width: AkibaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        if (badge != null) ...<Widget>[
                          const SizedBox(width: AkibaSpacing.sm),
                          _StatusPill(label: badge!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AkibaTypography.legend.copyWith(
                        color: c.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AkibaSpacing.md),
              Text(
                amountLabel,
                style: AkibaTypography.money(
                  15,
                  weight: FontWeight.w600,
                  color: amountColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AkibaSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: c.iconTile,
        borderRadius: BorderRadius.circular(AkibaRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: c.terracottaDeep,
        ),
      ),
    );
  }
}
