import 'package:flutter/material.dart';

import '../../data/models/account_brand.dart';
import '../format/akiba_currency.dart';
import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';
import '../theme/akiba_typography.dart';

export '../../data/models/account_brand.dart';

/// Présentation d'un support quand son logo n'est pas disponible.
extension AccountBrandPresentation on AccountBrand {
  IconData get fallbackIcon => switch (this) {
    AccountBrand.liquide => Icons.payments_rounded,
    AccountBrand.flooz => Icons.smartphone_rounded,
    AccountBrand.mixxByYas => Icons.phone_android_rounded,
    AccountBrand.orabank => Icons.account_balance_rounded,
  };
}

/// Préchauffage du cache d'images : logos officiels, avatar système et
/// emblème. Appelé une fois au démarrage, sans widget ni rebuild.
abstract final class BrandImages {
  static void warmUp() {
    final ImageConfiguration config = ImageConfiguration.empty;
    for (final AccountBrand brand in AccountBrand.values) {
      final String? asset = brand.asset;
      if (asset != null) AssetImage(asset).resolve(config);
    }
    const AssetImage('assets/profile/avatar_default.jpg').resolve(config);
    const AssetImage('assets/brand/app_icon.png').resolve(config);
    // Drapeaux de devises embarqués : tuile prête dès le premier affichage.
    for (final AkibaCurrency currency in AkibaCurrency.values) {
      AssetImage(currency.assetPath).resolve(config);
    }
    // Animation cochon + cauri : les deux images sont prêtes avant la première
    // image de l'ouverture et avant toute célébration d'épargne.
    const AssetImage('assets/brand/cochon.png').resolve(config);
    const AssetImage('assets/brand/cauri.png').resolve(config);
  }
}

/// Taille du logo, accordée à la hauteur de ligne ou de carte.
enum BrandLogoSize {
  /// Ligne compacte, puce, sous-titre.
  compact(32),

  /// Ligne de liste standard, champ de formulaire.
  regular(42),

  /// Carte de compte, écran de détail.
  large(56);

  const BrandLogoSize(this.value);

  final double value;
}

/// Logo officiel d'un support, dans une tuile arrondie de la taille de l'UI.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    required this.brand,
    this.size = BrandLogoSize.regular,
  });

  final AccountBrand brand;
  final BrandLogoSize size;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final double value = size.value;
    // Orabank est un logotype très large : il lui faut une tuile nettement
    // plus large (2×) pour ne pas paraître minuscule. Flooz et Mixx by Yas
    // gagnent un peu de place, sans perdre leur netteté.
    final bool wide = brand == AccountBrand.orabank;
    final bool mobileMoney =
        brand == AccountBrand.flooz || brand == AccountBrand.mixxByYas;
    final double scale = wide ? 1.08 : (mobileMoney ? 1.14 : 1);
    final double width = wide ? value * 2 : value * scale;
    final double height = value * scale;
    final double padding = wide ? value * 0.03 : value * 0.04;

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.symmetric(
        horizontal: padding,
        vertical: wide ? padding * 0.8 : padding,
      ),
      decoration: BoxDecoration(
        // Les logos officiels sont sur fond clair : la tuile reste blanche
        // dans tous les thèmes pour ne pas les dénaturer.
        color: Colors.white,
        borderRadius: BorderRadius.circular(value * 0.3),
        boxShadow: c.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: brand.asset == null
          ? Icon(brand.fallbackIcon, size: value * 0.55, color: c.terracotta)
          : Image.asset(
              brand.asset!,
              fit: BoxFit.contain,
              // Les logos sont mis en cache par le moteur d'images Flutter :
              // aucun scintillement ni requête quand on change d'onglet.
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              excludeFromSemantics: true,
              errorBuilder:
                  (
                    BuildContext context,
                    Object error,
                    StackTrace? stackTrace,
                  ) => Icon(
                    brand.fallbackIcon,
                    size: value * 0.55,
                    color: c.terracotta,
                  ),
            ),
    );
  }
}

/// Ligne « logo + nom » d'un support, avec sous-titre et montant optionnels.
class AccountBadge extends StatelessWidget {
  const AccountBadge({
    super.key,
    required this.brand,
    this.name,
    this.subtitle,
    this.amountLabel,
    this.amountColor,
    this.size = BrandLogoSize.regular,
    this.onTap,
  });

  final AccountBrand brand;

  /// Nom du compte ; par défaut le nom du support.
  final String? name;

  /// Précision affichée sous le nom (« Mobile money », « Compte courant »…).
  final String? subtitle;

  /// Montant déjà formaté (voir `AkibaMoney`), aligné à droite.
  final String? amountLabel;

  final Color? amountColor;
  final BrandLogoSize size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final String displayName = name ?? brand.label;
    final double nameSize = switch (size) {
      BrandLogoSize.compact => 13,
      BrandLogoSize.regular => 15,
      BrandLogoSize.large => 17,
    };

    final Widget content = Row(
      children: <Widget>[
        BrandLogo(brand: brand, size: size),
        const SizedBox(width: AkibaSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: nameSize,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AkibaTypography.legend.copyWith(color: c.textMuted),
                ),
              ],
            ],
          ),
        ),
        if (amountLabel != null) ...<Widget>[
          const SizedBox(width: AkibaSpacing.md),
          // Montant long sur petit écran : il réduit son corps au lieu de
          // pousser la ligne hors de la carte.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                amountLabel!,
                maxLines: 1,
                style: AkibaTypography.money(
                  nameSize,
                  weight: FontWeight.w600,
                  color: amountColor ?? c.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      button: onTap != null,
      label: <String>[displayName, ?subtitle, ?amountLabel].join(', '),
      excludeSemantics: true,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AkibaRadii.field),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AkibaSpacing.sm),
                child: content,
              ),
            ),
    );
  }
}
