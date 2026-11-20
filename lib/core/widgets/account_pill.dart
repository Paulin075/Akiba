import 'package:flutter/material.dart';

import '../../data/models/account.dart';
import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';
import 'brand_logo.dart';

/// Pilule de choix d'un compte : logo officiel + nom, état sélectionné.
class AccountPill extends StatelessWidget {
  const AccountPill({
    super.key,
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final Account account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: account.name,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AkibaDurations.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AkibaSpacing.sm,
            vertical: AkibaSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? c.iconTile : c.surfaceElevated,
            borderRadius: BorderRadius.circular(AkibaRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              BrandLogo(brand: account.brand, size: BrandLogoSize.compact),
              const SizedBox(width: AkibaSpacing.sm),
              Text(
                account.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? c.terracottaDeep : c.textPrimary,
                ),
              ),
              if (selected) ...<Widget>[
                const SizedBox(width: AkibaSpacing.xs),
                Icon(Icons.check_circle_rounded, size: 16, color: c.terracotta),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
