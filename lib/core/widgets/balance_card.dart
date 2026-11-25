import 'package:flutter/material.dart';

import '../format/akiba_money.dart';
import '../state/akiba_l10n.dart';
import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';
import '../theme/akiba_typography.dart';
import 'action_pill.dart';
import 'triangle_fringe.dart';

/// Carte de solde héroïne.
///
/// Dégradé terre cuite 135°, frise de triangles sable en haut et en bas, libellé
/// d'étiquette, montant héros en chiffres tabulaires, composition du solde et
/// deux pilules d'action (Transférer, Ajouter).
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.available,
    required this.totalAccounts,
    required this.savingsHeld,
    required this.thirdPartyHeld,
    required this.masked,
    this.onTransfer,
    this.onAdd,
  });

  final int available;
  final int totalAccounts;
  final int savingsHeld;
  final int thirdPartyHeld;
  final bool masked;
  final VoidCallback? onTransfer;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final Color soft = c.onTerracotta.withValues(alpha: 0.88);
    final Color faint = c.onTerracotta.withValues(alpha: 0.8);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: c.balanceGradient,
        borderRadius: BorderRadius.circular(AkibaRadii.hero),
        boxShadow: c.heroShadow,
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: TriangleFringe(
              alignTop: true,
              height: 16,
              color: c.sand.withValues(alpha: 0.35),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: TriangleFringe(
              alignTop: false,
              height: 16,
              color: c.sand.withValues(alpha: 0.35),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AkibaSpacing.xl,
              AkibaSpacing.xxxl + AkibaSpacing.sm,
              AkibaSpacing.xl,
              AkibaSpacing.xxl + AkibaSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  AkibaL10n.tr('available_balance_caps'),
                  style: AkibaTypography.label.copyWith(
                    color: soft,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AkibaSpacing.sm),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AkibaMoney.format(available, masked: masked),
                    maxLines: 1,
                    style: AkibaTypography.money(36, color: c.onTerracotta),
                  ),
                ),
                const SizedBox(height: AkibaSpacing.sm),
                Text(
                  masked
                      ? AkibaL10n.tr('accounts_savings_third_masked')
                      : AkibaL10n.tr('accounts_savings_third', <String, String>{
                          'accounts': AkibaMoney.format(totalAccounts),
                          'savings': AkibaMoney.format(savingsHeld),
                          'third': AkibaMoney.format(thirdPartyHeld),
                        }),
                  maxLines: 2,
                  style: AkibaTypography.legend.copyWith(
                    color: faint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AkibaSpacing.xl),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ActionPill(
                        icon: Icons.swap_horiz_rounded,
                        label: AkibaL10n.tr('transfer_action'),
                        tone: ActionPillTone.ochre,
                        onTap: onTransfer,
                      ),
                    ),
                    const SizedBox(width: AkibaSpacing.md),
                    Expanded(
                      child: ActionPill(
                        icon: Icons.add_rounded,
                        label: AkibaL10n.tr('add_action'),
                        tone: ActionPillTone.white,
                        onTap: onAdd,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
