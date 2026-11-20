import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';
import '../theme/akiba_typography.dart';
import 'backup_service.dart';

/// Suivi animé d'une sauvegarde ou d'une restauration.
///
/// Affiche chaque étape réelle (préparation, chiffrement AES-256-GCM, envoi ou
/// téléchargement, vérification) et coche celles qui sont terminées. Aucun
/// montant n'apparaît.
class BackupProgress extends StatelessWidget {
  const BackupProgress({
    super.key,
    required this.stage,
    required this.active,
    required this.restoring,
  });

  final ValueListenable<BackupStage> stage;
  final bool active;
  final bool restoring;

  static List<BackupStage> stepsFor(bool restoring) => restoring
      ? <BackupStage>[
          BackupStage.downloading,
          BackupStage.decrypting,
          BackupStage.verifying,
          BackupStage.done,
        ]
      : <BackupStage>[
          BackupStage.preparing,
          BackupStage.encrypting,
          BackupStage.uploading,
          BackupStage.verifying,
          BackupStage.done,
        ];

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final List<BackupStage> steps = stepsFor(restoring);

    return ValueListenableBuilder<BackupStage>(
      valueListenable: stage,
      builder: (BuildContext context, BackupStage current, Widget? _) {
        if (!active && current == BackupStage.idle) {
          return const SizedBox.shrink();
        }
        final int index = steps.indexOf(current);
        return AnimatedSize(
          duration: AkibaDurations.page,
          curve: Curves.easeOutCubic,
          child: Container(
            padding: const EdgeInsets.all(AkibaSpacing.md),
            decoration: BoxDecoration(
              color: c.surfaceElevated,
              borderRadius: BorderRadius.circular(AkibaRadii.field),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: current == BackupStage.done
                          ? Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: c.success,
                            )
                          : CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.terracotta,
                            ),
                    ),
                    const SizedBox(width: AkibaSpacing.sm),
                    Expanded(
                      child: Text(
                        restoring
                            ? 'Restauration chiffrée en cours'
                            : 'Sauvegarde chiffrée en cours',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AkibaSpacing.sm),
                for (int i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          i < index
                              ? Icons.check_rounded
                              : i == index
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 14,
                          color: i <= index ? c.terracotta : c.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          backupStageLabel(steps[i]),
                          style: AkibaTypography.legend.copyWith(
                            color: i <= index ? c.textPrimary : c.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AkibaSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AkibaRadii.pill),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0,
                      end: current == BackupStage.done
                          ? 1
                          : (index + 1) / steps.length,
                    ),
                    duration: AkibaDurations.page,
                    curve: Curves.easeOutCubic,
                    builder:
                        (BuildContext context, double value, Widget? child) =>
                            LinearProgressIndicator(
                              value: value,
                              minHeight: 4,
                              backgroundColor: c.surface,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                c.terracotta,
                              ),
                            ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
