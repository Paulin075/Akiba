import 'package:flutter/material.dart';

import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';

/// Carte AKIBA : surface arrondie, zéro bordure, ombre très douce en clair,
/// aucun relief en sombre.
class AkibaSurfaceCard extends StatelessWidget {
  const AkibaSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AkibaSpacing.xl),
    this.radius = AkibaRadii.card,
    this.background,
    this.showShadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? background;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: showShadow ? c.cardShadow : const <BoxShadow>[],
      ),
      child: child,
    );
  }
}
