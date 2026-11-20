import 'package:flutter/material.dart';

import '../state/akiba_l10n.dart';
import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';

/// Barre de navigation inférieure AKIBA.
///
/// Règles en dur (akiba_animations_notifications_regles) :
/// toujours ancrée en bas, pleine largeur, sans barre flottante ni bords
/// arrondis, épurée type WhatsApp. Le bouton cochon n'y figure pas : il vit
/// sur le côté droit (`AkibaSideActions`).
class AkibaBottomBar extends StatelessWidget {
  const AkibaBottomBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  /// Hauteur de contenu, hors safe area.
  static const double height = AkibaSizes.bottomBar;

  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const List<({IconData icon, IconData selectedIcon, String labelKey})>
  destinations = <({IconData icon, IconData selectedIcon, String labelKey})>[
    (
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      labelKey: 'nav_home',
    ),
    (
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights_rounded,
      labelKey: 'nav_analysis',
    ),
    (
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet_rounded,
      labelKey: 'nav_wallet',
    ),
    (
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      labelKey: 'nav_profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Container(
      decoration: BoxDecoration(color: c.surface, boxShadow: c.barShadow),
      child: Material(
        color: c.surface,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: height,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < destinations.length; i++)
                  Expanded(child: _item(context, c, i)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, AkibaColors c, int index) {
    final ({IconData icon, IconData selectedIcon, String labelKey})
    destination = destinations[index];
    final String label = AkibaL10n.t(context, destination.labelKey);
    final bool selected = index == currentIndex;
    final Color color = selected ? c.terracotta : c.textMuted;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: () => onSelected(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              selected ? destination.selectedIcon : destination.icon,
              size: 24,
              color: color,
            ),
            const SizedBox(height: AkibaSpacing.xs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
