import 'package:flutter/material.dart';

import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';

/// Résultat du test de connexion IA, affiché **dans la carte de la clé**,
/// juste sous le bouton « Tester ».
///
/// Trois états seulement : chargement, réponse du modèle, ou erreur déjà
/// traduite en catégorie sûre (`délai dépassé`, `clé refusée`, …). Aucune URL,
/// aucun corps de réponse brut et aucune clé ne transitent par ce widget.
class AiTestPanel extends StatelessWidget {
  const AiTestPanel({super.key, this.loading = false, this.reply, this.error});

  /// Un appel est en cours (liste des modèles ou réponse du modèle).
  final bool loading;

  /// Réponse réelle du modèle retenu, quand elle est arrivée.
  final String? reply;

  /// Message d'erreur catégorisé, sans détail technique.
  final String? error;

  bool get _hasContent => loading || reply != null || error != null;

  @override
  Widget build(BuildContext context) {
    if (!_hasContent) return const SizedBox.shrink();
    final AkibaColors c = AkibaColors.of(context);
    final Color accent = error != null ? c.danger : c.success;

    return Container(
      key: const Key('ai-test-panel'),
      margin: const EdgeInsets.only(top: AkibaSpacing.sm),
      padding: const EdgeInsets.all(AkibaSpacing.md),
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        borderRadius: BorderRadius.circular(AkibaRadii.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                loading
                    ? Icons.hourglass_top_rounded
                    : error != null
                    ? Icons.error_outline_rounded
                    : Icons.smart_toy_outlined,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                error != null ? 'Test de connexion' : 'Réponse du modèle',
                style: AkibaTypography.legend.copyWith(
                  color: c.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AkibaSpacing.xs),
          if (loading)
            Text(
              'Test en cours…',
              style: AkibaTypography.legend.copyWith(color: c.textMuted),
            )
          else if (error != null)
            Text(
              error!,
              style: AkibaTypography.legend.copyWith(color: c.danger),
            )
          else
            SelectableText(
              reply!,
              style: TextStyle(fontSize: 13, color: c.textPrimary, height: 1.4),
            ),
        ],
      ),
    );
  }
}
