import 'package:flutter/material.dart';

/// Zoom maximal autorisé par les vues zoomables (aperçu PDF, documents).
///
/// Volontairement très élevé : un pincement doit pouvoir agrandir le document
/// jusqu'à lire un chiffre isolé, sans buter sur un facteur faible. La valeur
/// reste finie pour que la matrice de transformation ne parte jamais à
/// l'infini.
abstract final class AkibaZoom {
  static const double minScale = 1;
  static const double maxScale = 50;
  static const EdgeInsets boundaryMargin = EdgeInsets.all(160);
}

/// Enveloppe de pincement (*pinch-to-zoom*) réutilisable.
///
/// Elle expose le [InteractiveViewer] sous-jacent pour que les écrans gardent
/// la main sur le panoramique (par exemple : le défilement vertical reste à la
/// page tant que rien n'est agrandi).
class PinchZoom extends StatelessWidget {
  const PinchZoom({
    super.key,
    required this.child,
    this.controller,
    this.onZoomChanged,
    this.panEnabled = true,
    this.minScale = AkibaZoom.minScale,
    this.maxScale = AkibaZoom.maxScale,
    this.boundaryMargin = AkibaZoom.boundaryMargin,
  });

  final Widget child;
  final TransformationController? controller;
  final ValueChanged<bool>? onZoomChanged;
  final bool panEnabled;
  final double minScale;
  final double maxScale;
  final EdgeInsets boundaryMargin;

  void _handleInteraction(ScaleUpdateDetails details) {
    final ValueChanged<bool>? listener = onZoomChanged;
    if (listener == null) return;
    listener((controller?.value.getMaxScaleOnAxis() ?? 1) > 1.01);
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: controller,
      minScale: minScale,
      maxScale: maxScale,
      panEnabled: panEnabled,
      boundaryMargin: boundaryMargin,
      onInteractionUpdate: onZoomChanged == null ? null : _handleInteraction,
      child: child,
    );
  }
}
