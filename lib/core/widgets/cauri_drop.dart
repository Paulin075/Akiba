import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;

import '../theme/akiba_colors.dart';

/// Animation signature AKIBA : le **cochon sans cauri** (la tirelire) reçoit le
/// cauri qui tombe dans sa fente.
///
/// Le même widget sert trois fois, pour que le geste soit identique partout :
/// 1. l'écran d'ouverture (`SplashScreen`) ;
/// 2. chaque versement vers l'épargne (`showSavingsCelebration`).
///
/// Durée par défaut : **3 secondes** (versement d'épargne) ; l'ouverture passe
/// une durée plus courte. Aucun réseau ni montant.
///
/// Un versement de 2 000 FCFA vaut **20 cauris** (1 cauri = 100 FCFA) : ils
/// tombent **individuellement** dans la tirelire, en cadence serrée, sans
/// badge multiplicateur « ×20 ». La durée totale reste de 3 secondes quel que
/// soit le montant ; au-delà de [maxVisibleCauris], la file est plafonnée pour
/// rester fluide (aucun compteur textuel n'est ajouté).
/// Si « Réduire les animations » est actif, l'image finale est affichée
/// directement et [onCompleted] est appelé sans mouvement.
class CauriDropAnimation extends StatefulWidget {
  const CauriDropAnimation({
    super.key,
    this.size = 180,
    this.duration = const Duration(seconds: 3),
    this.onCompleted,
    this.cauriCount = 1,
    this.playSound = false,
  });

  /// Largeur du bloc ; la tirelire occupe toute la largeur.
  final double size;

  /// Durée complète du geste (3 s par défaut).
  final Duration duration;

  /// Appelé une seule fois, à la fin de l'animation (ou tout de suite si les
  /// animations sont réduites).
  final VoidCallback? onCompleted;
  final int cauriCount;
  final bool playSound;

  /// Nombre maximal de cauris dessinés en même temps.
  ///
  /// Les montants courants (20 cauris pour 2 000 FCFA) sont rendus un par un.
  /// Au-delà de ce plafond, la chute reste fluide sur les appareils modestes ;
  /// aucun multiplicateur texte n'est affiché pour autant.
  static const int maxVisibleCauris = 60;

  @override
  State<CauriDropAnimation> createState() => _CauriDropAnimationState();
}

class _CauriDropAnimationState extends State<CauriDropAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _started = false;
  bool _notified = false;

  static const double _slotRatio = 0.46;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.playSound) {
      // Son natif léger, sans asset ni plugin supplémentaire. Sur un appareil
      // silencieux ou une plateforme qui ne le prend pas en charge, l'animation
      // continue normalement.
      unawaited(
        SystemSound.play(SystemSoundType.click).catchError((Object _) {}),
      );
    }
    final bool reduced =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) {
      _controller.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _notify());
    } else {
      _controller.forward().whenComplete(_notify);
    }
  }

  void _notify() {
    if (_notified) return;
    _notified = true;
    widget.onCompleted?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final double size = widget.size;
    final double pigHeight = size * 0.62;
    final double pigWidth = pigHeight * (389 / 260);
    final double pigTop = size - pigHeight;
    final double cauriHeight = size * 0.34;
    final double cauriWidth = cauriHeight * (249 / 360);
    final double landedTop = size * _slotRatio - cauriHeight / 2;
    final double startTop = -cauriHeight - size * 0.04;

    // File de cauris : chacun a sa propre chute, tous dans la même fenêtre de
    // 3 s. L'espacement se resserre quand le nombre grandit, pour que le
    // dernier cauri soit rentré avant le message d'encouragement.
    final int total = widget.cauriCount < 1 ? 1 : widget.cauriCount;
    final int visible = math.min(total, CauriDropAnimation.maxVisibleCauris);
    final double stagger = visible <= 1
        ? 0
        : math.min(0.030, 0.55 / (visible - 1));
    final double firstImpact = 0.05 + 0.20;

    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) {
          final double t = _controller.value;

          // Impact : halo ocre, léger écrasement de la tirelire, éclat.
          final double hit = ((t - firstImpact) / 0.20).clamp(0.0, 1.0);
          final double squash = hit > 0 && hit < 1
              ? 1 + 0.05 * math.sin(hit * math.pi)
              : 1.0;
          final double ring = ((t - firstImpact) / 0.24).clamp(0.0, 1.0);

          // Repos : la tirelire respire doucement jusqu'à la fin.
          final double breathe = t > 0.86
              ? math.sin((t - 0.86) / 0.14 * math.pi) * 2.0
              : 0.0;

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: <Widget>[
              if (ring > 0 && ring < 1)
                Positioned(
                  top: landedTop + cauriHeight * 0.34 - (size * 0.30) * ring,
                  child: Opacity(
                    opacity: 0.45 * (1 - ring),
                    child: Container(
                      width: size * 0.60 * ring + 8,
                      height: size * 0.60 * ring + 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: c.ochre, width: 2.5),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: pigTop + breathe,
                child: Transform.scale(
                  scaleX: squash,
                  scaleY: 2 - squash,
                  alignment: Alignment.bottomCenter,
                  child: Image.asset(
                    'assets/brand/cochon.png',
                    width: pigWidth,
                    height: pigHeight,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    isAntiAlias: true,
                    errorBuilder:
                        (
                          BuildContext context,
                          Object error,
                          StackTrace? stack,
                        ) => SizedBox(
                          width: pigWidth,
                          height: pigHeight,
                          child: Icon(
                            Icons.savings_rounded,
                            size: pigHeight * 0.7,
                            color: c.terracotta,
                          ),
                        ),
                  ),
                ),
              ),
              for (int i = 0; i < visible; i++)
                _fallingCauri(
                  index: i,
                  t: t,
                  size: size,
                  startTop: startTop,
                  landedTop: landedTop,
                  cauriHeight: cauriHeight,
                  cauriWidth: cauriWidth,
                  stagger: stagger,
                  color: c.ochre,
                ),
              if (hit > 0 && hit < 1)
                Positioned(
                  top: landedTop - 6,
                  left: size / 2 - size * 0.20,
                  child: SizedBox(
                    width: size * 0.40,
                    height: size * 0.14,
                    child: CustomPaint(
                      painter: _SparkPainter(progress: hit, color: c.ochre),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Un cauri de la file : départ échelonné, chute accélérée, disparition dans
  /// la fente. Aucun compteur n'est affiché : c'est la chute elle-même qui
  /// montre le nombre de cauris.
  Widget _fallingCauri({
    required int index,
    required double t,
    required double size,
    required double startTop,
    required double landedTop,
    required double cauriHeight,
    required double cauriWidth,
    required double stagger,
    required Color color,
  }) {
    final double begin = 0.05 + index * stagger;
    final double fall = ((t - begin) / 0.20).clamp(0.0, 1.0);
    final double eased = Curves.easeInCubic.transform(fall);
    final double top = lerpDouble(startTop, landedTop, eased)!;
    final double sink = ((fall - 0.82) / 0.18).clamp(0.0, 1.0);
    final double opacity = fall <= 0 ? 0 : (1 - sink).clamp(0.0, 1.0);
    final double scale = 1 - 0.62 * sink;
    final double rotation = -0.30 + 0.36 * eased;
    // Léger écart latéral en début de chute, resserré vers la fente.
    final double offsetX = math.sin(index * 2.4) * size * 0.06 * (1 - eased);

    return Positioned(
      top: top,
      left: size / 2 - cauriWidth / 2 + offsetX,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            scale: scale,
            child: Image.asset(
              'assets/brand/cauri.png',
              key: ValueKey<String>('cauri-$index'),
              width: cauriWidth,
              height: cauriHeight,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stack) =>
                      Icon(Icons.spa_rounded, size: cauriHeight, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// Petites étincelles ocre qui partent de la fente à l'impact.
class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final Paint paint = Paint()
      ..color = color.withValues(alpha: (1 - progress).clamp(0.0, 1.0) * 0.9);
    final Offset origin = Offset(size.width / 2, size.height * 0.7);
    final math.Random random = math.Random(11);
    for (int i = 0; i < 7; i++) {
      final double angle = -math.pi + random.nextDouble() * math.pi;
      final double distance =
          (0.4 + random.nextDouble()) * size.height * progress;
      final Offset point =
          origin +
          Offset(math.cos(angle) * distance, math.sin(angle) * distance);
      canvas.drawCircle(point, 2.2 * (1 - progress), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
