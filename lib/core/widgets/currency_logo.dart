import 'package:flutter/material.dart';

import '../format/akiba_currency.dart';
import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';
import '../theme/akiba_typography.dart';

/// Logo d'une devise, dans une tuile blanche de la taille de l'interface.
///
/// Le drapeau est **embarqué dans les assets** (`assets/logos/currencies/`) :
/// il s'affiche même hors ligne et dès le premier lancement. Si l'asset manque
/// (plateforme sans bundle), un jeton typographique aux couleurs d'AKIBA prend
/// sa place, sans trou visuel ni erreur.
class CurrencyLogo extends StatelessWidget {
  const CurrencyLogo({super.key, required this.currency, this.size = 32});

  final AkibaCurrency currency;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Semantics(
      label: 'Devise ${currency.name}',
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.1),
        decoration: BoxDecoration(
          color: c.isDark ? Colors.white : Colors.white,
          borderRadius: BorderRadius.circular(size * 0.32),
          boxShadow: c.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          currency.assetPath,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
          excludeFromSemantics: true,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) =>
                  _fallback(c),
        ),
      ),
    );
  }

  /// Repli hors ligne : le symbole de la devise, jamais une image cassée.
  Widget _fallback(AkibaColors c) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        currency.symbol,
        style: AkibaTypography.money(
          size * 0.4,
          weight: FontWeight.w700,
          color: c.terracotta,
        ),
      ),
    );
  }
}

/// Ligne « logo + nom + code » d'une devise, pour les listes de réglages.
class CurrencyBadge extends StatelessWidget {
  const CurrencyBadge({
    super.key,
    required this.currency,
    this.selected = false,
    this.onTap,
    this.size = 28,
  });

  final AkibaCurrency currency;
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: 'Devise ${currency.name}',
      excludeSemantics: true,
      child: Material(
        color: selected ? c.iconTile : c.surfaceElevated,
        borderRadius: BorderRadius.circular(AkibaRadii.field),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AkibaRadii.field),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AkibaSpacing.sm,
              vertical: AkibaSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CurrencyLogo(currency: currency, size: size),
                const SizedBox(width: AkibaSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      currency.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      currency.code,
                      style: AkibaTypography.legend.copyWith(
                        color: c.textMuted,
                      ),
                    ),
                  ],
                ),
                if (selected) ...<Widget>[
                  const SizedBox(width: AkibaSpacing.xs),
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: c.terracotta,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
