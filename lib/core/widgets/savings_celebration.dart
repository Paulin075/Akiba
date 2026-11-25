import 'dart:async';

import 'package:flutter/material.dart';

import '../savings/savings_messages.dart';
import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';
import '../theme/akiba_typography.dart';
import 'cauri_drop.dart';

/// Petite fête locale après un versement d'épargne.
///
/// Aucun réseau ni montant : seulement l'encouragement et
/// **la même animation de 3 secondes que l'ouverture** — la tirelire reçoit le
/// cauri qui tombe dans sa fente. L'animation se coupe si « Réduire les
/// animations » est actif.
///
/// À la fin du geste, le message d'encouragement apparaît en fondu + glissement
/// doux, puis reste à l'écran jusqu'à ce que la personne le ferme : elle a le
/// temps de le lire. [aiMessage] peut remplacer le message local quand l'IA
/// configurée répond ; en cas d'échec, le message local reste affiché.
Future<void> showSavingsCelebration(
  BuildContext context, {
  String? potName,
  int progressPercent = 0,
  int cauriCount = 1,
  String? message,
  Future<String?>? aiMessage,
}) {
  final bool reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final String local =
      message ??
      SavingsMessages().next(
        SavingsMessageKind.encouragement,
        potName: potName,
      );
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
              cauriCount: cauriCount,
              reduced: reduced,
              message: local,
              aiMessage: aiMessage,
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
    required this.cauriCount,
    required this.reduced,
    required this.message,
    required this.aiMessage,
  });

  final String? potName;
  final int progressPercent;
  final int cauriCount;
  final bool reduced;
  final String message;
  final Future<String?>? aiMessage;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> {
  /// Le message n'apparaît qu'à la fin du cauri (ou tout de suite si les
  /// animations sont réduites), pour ne pas masquer le geste signature.
  bool _revealed = false;
  String? _aiText;

  @override
  void initState() {
    super.initState();
    if (widget.reduced) _revealed = true;
    final Future<String?>? ai = widget.aiMessage;
    if (ai != null) {
      unawaited(
        ai
            .then((String? value) {
              if (!mounted) return;
              final String? text = value?.trim();
              if (text == null || text.isEmpty) return;
              setState(() => _aiText = text);
            })
            .catchError((Object _) => null),
      );
    }
  }

  void _reveal() {
    if (_revealed || !mounted) return;
    setState(() => _revealed = true);
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final String pot = widget.potName ?? 'votre coffre';
    final String text = _aiText ?? widget.message;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Container(
            margin: const EdgeInsets.all(AkibaSpacing.xl),
            padding: const EdgeInsets.all(AkibaSpacing.lg),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AkibaRadii.card),
              boxShadow: c.heroShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CauriDropAnimation(
                  size: 168,
                  duration: AkibaDurations.cauriDrop,
                  cauriCount: widget.cauriCount,
                  playSound: true,
                  onCompleted: _reveal,
                ),
                const SizedBox(height: AkibaSpacing.sm),
                Text(
                  'Bravo !',
                  style: AkibaTypography.screenTitle.copyWith(
                    color: c.textPrimary,
                  ),
                ),
                // Transition douce vers le message : fondu + glissement vers
                // le haut, désactivés si « Réduire les animations » est actif.
                AnimatedSize(
                  duration: Duration(milliseconds: widget.reduced ? 0 : 280),
                  curve: Curves.easeOut,
                  child: AnimatedOpacity(
                    opacity: _revealed ? 1 : 0,
                    duration: Duration(milliseconds: widget.reduced ? 0 : 320),
                    curve: Curves.easeOut,
                    child: AnimatedSlide(
                      offset: _revealed ? Offset.zero : const Offset(0, 0.12),
                      duration: Duration(
                        milliseconds: widget.reduced ? 0 : 320,
                      ),
                      curve: Curves.easeOutCubic,
                      child: Column(
                        children: <Widget>[
                          const SizedBox(height: AkibaSpacing.xs),
                          Text(
                            text,
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
                          const SizedBox(height: AkibaSpacing.sm),
                          Text(
                            'Épargne pour $pot',
                            style: AkibaTypography.legend.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                          const SizedBox(height: AkibaSpacing.md),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              style: FilledButton.styleFrom(
                                backgroundColor: c.terracotta,
                                foregroundColor: c.onTerracotta,
                              ),
                              child: const Text('Continuer'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
