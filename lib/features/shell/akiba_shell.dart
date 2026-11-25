import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/report/report_scheduler.dart';
import '../../core/sms/sms_bridge.dart';
import '../../core/sms/sms_entry_intent.dart';
import '../../core/sms/sms_parser.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/state/akiba_l10n.dart';
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

  /// Segment demandé au portefeuille : 2 = Épargne (coffres).
  final ValueNotifier<int> _portfolioSegment = ValueNotifier<int>(0);
  final AkibaDataRevision _revision = AkibaDataRevision();

  StreamSubscription<String>? _smsSubscription;
  bool _openingSms = false;

  @override
  void initState() {
    super.initState();
    // SMS détecté quand l'application était fermée : le texte attend dans
    // l'Intent de la notification, on le relit après la première image.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingSms();
      // Rapport de fin de mois : premier lancement du mois suivant, en local.
      ReportScheduler.maybeGenerate(
        store: widget.store,
        settings: widget.settings,
      );
    });
    // SMS reçu pendant que l'application tourne (récepteur natif → canal).
    _smsSubscription = SmsBridge.messages.listen(_onSms);
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    _masked.dispose();
    _portfolioSegment.dispose();
    _revision.dispose();
    super.dispose();
  }

  Future<void> _consumePendingSms() async {
    final String? body = await SmsBridge.consumePending();
    if (body == null || !mounted) return;
    await _onSms(body);
  }

  /// Ouvre la saisie préremplie depuis un SMS. Aucune écriture ici : la
  /// personne doit encore confirmer dans la fiche.
  Future<void> _onSms(String body) async {
    if (!mounted || _openingSms) return;
    if (!SmsDetector.isFinancialSms(body)) return;
    final SmsDraft? draft = SmsParser.parseOne(body);
    if (draft == null) return;
    final SmsEntryIntent? intent = SmsEntryIntent.fromDraft(draft);
    if (intent == null) return;
    _openingSms = true;
    try {
      await openQuickEntry(
        context,
        store: widget.store,
        revision: _revision,
        mode: intent.isNeutral
            ? QuickEntryMode.thirdParty
            : (intent.income ? QuickEntryMode.income : QuickEntryMode.expense),
        prefill: intent,
      );
    } finally {
      _openingSms = false;
    }
  }

  Future<void> _openEntry({QuickEntryMode mode = QuickEntryMode.expense}) {
    return openQuickEntry(
      context,
      store: widget.store,
      revision: _revision,
      mode: mode,
    );
  }

  void _openSavings() {
    _portfolioSegment.value = 2;
    setState(() => _index = 2);
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
                            onOpenSavings: _openSavings,
                            onOpenAssistant: _openAssistant,
                          ),
                          AnalysisScreen(
                            store: widget.store,
                            revision: _revision,
                          ),
                          PortfolioScreen(
                            store: widget.store,
                            revision: _revision,
                            segmentRequest: _portfolioSegment,
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
              AkibaL10n.tr('sim_banner'),
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
