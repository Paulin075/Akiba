import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';
import '../theme/akiba_typography.dart';

/// Petite fête locale après un versement d'épargne.
///
/// Aucun son, aucun réseau, aucun montant : seulement l'encouragement et une
/// pluie de piécettes dessinées. L'animation se coupe si « Réduire les
/// animations » est actif.
Future<void> showSavingsCelebration(
  BuildContext context, {
  String? potName,
  int progressPercent = 0,
}) {
  final bool reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fermer',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: Duration(milliseconds: reduced ? 120 : 260),
    pageBuilder:
        (BuildContext context, Animation<double> a, Animation<double> b) =>
            _Celebration(
              potName: potName,
              progressPercent: progressPercent,
              reduced: reduced,
            ),
    transitionBuilder:
        (BuildContext context, Animation<double> animation, _, Widget child) =>
            FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                ),
                child: child,
              ),
            ),
  );
}

class _Celebration extends StatefulWidget {
  const _Celebration({
    required this.potName,
    required this.progressPercent,
    required this.reduced,
  });

  final String? potName;
  final int progressPercent;
  final bool reduced;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.reduced) {
      _controller.value = 0.4;
    } else {
      _controller.forward();
    }
    Future<void>.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final String pot = widget.potName ?? 'votre coffre';

    return Center(
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 320,
          height: 340,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              if (!widget.reduced)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (BuildContext context, Widget? _) => CustomPaint(
                      painter: _CoinsPainter(
                        progress: _controller.value,
                        color: c.ochre,
                      ),
                    ),
                  ),
                ),
              Container(
                margin: const EdgeInsets.all(AkibaSpacing.xl),
                padding: const EdgeInsets.all(AkibaSpacing.xl),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AkibaRadii.card),
                  boxShadow: c.heroShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.7, end: 1),
                      duration: widget.reduced
                          ? Duration.zero
                          : const Duration(milliseconds: 500),
                      curve: Curves.elasticOut,
                      builder:
                          (BuildContext context, double value, Widget? child) =>
                              Transform.scale(scale: value, child: child),
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: c.iconTile,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.savings_rounded,
                          size: 36,
                          color: c.terracottaDeep,
                        ),
                      ),
                    ),
                    const SizedBox(height: AkibaSpacing.md),
                    Text(
                      'Bravo !',
                      style: AkibaTypography.screenTitle.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AkibaSpacing.xs),
                    Text(
                      'Votre épargne pour $pot vient de grandir.',
                      textAlign: TextAlign.center,
                      style: AkibaTypography.body.copyWith(
                        color: c.textMuted,
                        height: 1.45,
                      ),
                    ),
                    if (widget.progressPercent > 0) ...<Widget>[
                      const SizedBox(height: AkibaSpacing.md),
                      Text(
                        'Objectif : ${widget.progressPercent} %',
                        style: AkibaTypography.label.copyWith(
                          color: c.terracotta,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Piécettes qui montent puis retombent, dessinées localement.
class _CoinsPainter extends CustomPainter {
  _CoinsPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final Paint paint = Paint()..color = color.withValues(alpha: 0.85);
    final math.Random random = math.Random(7);
    for (int i = 0; i < 18; i++) {
      final double startX = random.nextDouble() * size.width;
      final double drift = (random.nextDouble() - 0.5) * 40;
      final double delay = random.nextDouble() * 0.25;
      final double t = ((progress - delay) / 0.75).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final double y = size.height * (1 - t) - 20;
      final double x = startX + drift * t;
      canvas.drawCircle(Offset(x, y), 4 + 2 * (1 - t), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CoinsPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
