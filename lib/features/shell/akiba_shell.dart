import 'package:flutter/material.dart';

import '../../core/state/akiba_data_revision.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/state/masked_amounts.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/akiba_bottom_bar.dart';
import '../../core/widgets/akiba_side_actions.dart';
import '../../data/akiba_store.dart';
import '../analysis/analysis_screen.dart';
import '../assistant/assistant_sheet.dart';
import '../dashboard/dashboard_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../profile/profile_screen.dart';
import '../quick_entry/quick_entry.dart';

/// Coquille de navigation AKIBA.
///
/// Assemble les trois éléments de structure imposés :
/// - une barre de navigation basse pleine largeur, non flottante ;
/// - le bouton cochon sur le côté droit, au-dessus de la barre ;
/// - la petite icône Assistant IA juste au-dessus du cochon.
///
/// Elle porte le masquage des montants et le signal de rafraîchissement.
class AkibaShell extends StatefulWidget {
  const AkibaShell({
    super.key,
    required this.store,
    required this.settings,
    required this.onReplayOnboarding,
  });

  final AkibaStore store;
  final AkibaSettings settings;
  final VoidCallback onReplayOnboarding;

  @override
  State<AkibaShell> createState() => _AkibaShellState();
}

class _AkibaShellState extends State<AkibaShell> {
  int _index = 0;
  final ValueNotifier<bool> _masked = ValueNotifier<bool>(false);
  final AkibaDataRevision _revision = AkibaDataRevision();

  @override
  void dispose() {
    _masked.dispose();
    _revision.dispose();
    super.dispose();
  }

  Future<void> _openEntry({QuickEntryMode mode = QuickEntryMode.expense}) {
    return openQuickEntry(
      context,
      store: widget.store,
      revision: _revision,
      mode: mode,
    );
  }

  Future<void> _openAssistant() {
    return openAssistant(
      context,
      store: widget.store,
      revision: _revision,
      masked: _masked.value,
      settings: widget.settings,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaskedAmounts(
      notifier: _masked,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Column(
                  children: <Widget>[
                    if (widget.settings.simulationMode)
                      const _SimulationBanner(),
                    Expanded(
                      child: IndexedStack(
                        index: _index,
                        children: <Widget>[
                          DashboardScreen(
                            store: widget.store,
                            revision: _revision,
                            themeId: widget.settings.themeId,
                            onThemeChanged: widget.settings.setThemeId,
                            onSeeAllMovements: () => setState(() => _index = 2),
                          ),
                          AnalysisScreen(
                            store: widget.store,
                            revision: _revision,
                          ),
                          PortfolioScreen(
                            store: widget.store,
                            revision: _revision,
                          ),
                          ProfileScreen(
                            store: widget.store,
                            settings: widget.settings,
                            revision: _revision,
                            onReplayOnboarding: widget.onReplayOnboarding,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: AkibaSpacing.lg,
                bottom: AkibaSpacing.lg,
                child: AkibaSideActions(
                  onAdd: () => _openEntry(),
                  onLongPressAdd: _openAssistant,
                  onAssistant: _openAssistant,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: AkibaBottomBar(
          currentIndex: _index,
          onSelected: (int index) => setState(() => _index = index),
        ),
      ),
    );
  }
}

class _SimulationBanner extends StatelessWidget {
  const _SimulationBanner();

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Container(
      width: double.infinity,
      color: c.ochre.withValues(alpha: 0.16),
      padding: const EdgeInsets.symmetric(
        horizontal: AkibaSpacing.screen,
        vertical: AkibaSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.science_outlined, size: 16, color: c.ochre),
          const SizedBox(width: AkibaSpacing.sm),
          Expanded(
            child: Text(
              'Mode simulation · données d’essai locales',
              style: AkibaTypography.label.copyWith(
                color: c.textPrimary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
