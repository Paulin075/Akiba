import 'package:flutter/material.dart';

/// Frise de triangles AKIBA, posée en haut ou en bas d'une carte.
///
/// Motif signature du design system : triangles pleins, jamais derrière un
/// texte (les cartes qui l'utilisent réservent une marge supérieure et
/// inférieure).
class TriangleFringe extends StatelessWidget {
  const TriangleFringe({
    super.key,
    required this.alignTop,
    this.height = 16,
    this.color,
  });

  final bool alignTop;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _TriangleFringePainter(
            color: color ?? Theme.of(context).colorScheme.primary,
            alignTop: alignTop,
          ),
        ),
      ),
    );
  }
}

class _TriangleFringePainter extends CustomPainter {
  _TriangleFringePainter({required this.color, required this.alignTop});

  final Color color;
  final bool alignTop;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final Paint paint = Paint()..color = color;
    final double step = 18;
    final int count = (size.width / step).ceil() + 1;
    final double width = size.width / count;

    final Path path = Path();
    for (int i = 0; i < count; i++) {
      final double left = i * width;
      if (alignTop) {
        path
          ..moveTo(left, 0)
          ..lineTo(left + width, 0)
          ..lineTo(left + width / 2, size.height);
      } else {
        path
          ..moveTo(left, size.height)
          ..lineTo(left + width, size.height)
          ..lineTo(left + width / 2, 0);
      }
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TriangleFringePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.alignTop != alignTop;
}
