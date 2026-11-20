import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/backup/backup_progress.dart';
import '../../core/backup/backup_service.dart';
import '../../core/backup/google_drive_backup.dart';
import '../../core/config/google_oauth_config.dart';
import '../../core/format/akiba_currency.dart';
import '../../core/format/akiba_date.dart';
import '../../core/format/akiba_money.dart';
import '../../core/notifications/local_notifications.dart';
import '../../core/security/pin_vault.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_theme.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/akiba_surface_card.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/currency_logo.dart';
import '../../core/widgets/segmented_control.dart';
import '../../core/widgets/theme_swatch.dart';
import '../../data/akiba_store.dart';
import '../../data/models/account.dart';
import '../../data/models/transaction_record.dart';

/// Parcours d'onboarding E1 → E11.
///
/// Chaque étape est reprise depuis le réglage `onboarding_step`, le retour est
/// possible partout sauf à E1, et le dashboard n'est atteint qu'après E3.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.store,
    required this.settings,
    required this.revision,
    required this.onFinished,
  });

  final AkibaStore store;
  final AkibaSettings settings;
  final AkibaDataRevision revision;
  final VoidCallback onFinished;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const int steps = 11;

  late int _step;
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _pinConfirm = TextEditingController();
  final TextEditingController _reserve = TextEditingController();

  final Map<AccountBrand, TextEditingController> _openings =
      <AccountBrand, TextEditingController>{
        for (final AccountBrand brand in AccountBrand.values)
          brand: TextEditingController(),
      };

  AkibaCurrency _currency = AkibaCurrency.fcfa;
  String _timezone = 'Africa/Lome';
  String _dateStyle = 'jj/mm/aaaa';
  AkibaThemeId _theme = AkibaThemeId.blanc;
  String _language = 'fr';
  bool _biometrics = false;
  bool _googleLinked = false;
  final GoogleDriveService _google = GoogleDriveService();
  String? _googleEmail;
  Map<String, dynamic>? _driveBackup;
  BackupMetadata? _driveMeta;
  bool _googleChecked = false;
  bool _restoring = false;
  final ValueNotifier<BackupStage> _backupStage = ValueNotifier<BackupStage>(
    BackupStage.idle,
  );
  bool _entering = false;
  bool _permissionNotifications = false;
  bool _permissionSms = false;
  bool _permissionMicro = false;
  bool _permissionWifi = false;
  String? _permissionNote;
  bool _simulation = false;
  int _savingsGoal = 10;
  int _openingTotal = 0;
  bool _saving = false;
  String? _error;

  bool _openingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _step = widget.settings.onboardingStep.clamp(0, steps - 1);
    _firstName = TextEditingController(text: widget.settings.firstName);
    _lastName = TextEditingController(text: widget.settings.lastName);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_openingsLoaded) return;
    _openingsLoaded = true;
    _currency = widget.settings.currencyCode;
    _timezone = widget.settings.timezone;
    _dateStyle = widget.settings.dateStyle;
    _theme = widget.settings.themeId;
    _language = widget.settings.raw('language');
    _biometrics = widget.settings.biometrics;
    _simulation = widget.settings.simulationMode;
    _permissionNotifications = widget.settings.flag('permission_notifications');
    _permissionSms = widget.settings.flag('permission_sms');
    _permissionMicro = widget.settings.flag('permission_micro');
    _permissionWifi = widget.settings.flag('permission_wifi');
    for (final TextEditingController controller in _openings.values) {
      controller.addListener(_recomputeOpeningTotal);
    }
    _loadReserve();
    _loadGoogleLink();
  }

  Future<void> _loadGoogleLink() async {
    final String? email = await _google.linkedEmail();
    if (!mounted) return;
    setState(() {
      _googleEmail = email;
      if (email != null) _googleLinked = true;
    });
  }

  /// Connexion Google facultative : un échec laisse l'étape intacte.
  Future<void> _connectGoogle() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final GoogleSession session = await _google.signIn();
      if (!mounted) return;
      setState(() {
        _googleEmail = session.email.isEmpty ? 'compte Google' : session.email;
        _googleLinked = true;
      });
      await _checkDriveBackup();
    } on GoogleAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Connexion Google impossible (${error.runtimeType}).',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Vérifie automatiquement s'il existe une sauvegarde AKIBA sur le Drive.
  Future<void> _checkDriveBackup() async {
    try {
      final Map<String, dynamic>? envelope = await _google.download();
      if (!mounted) return;
      setState(() {
        _driveBackup = envelope;
        _driveMeta = envelope == null ? null : BackupService.metadata(envelope);
        _googleChecked = true;
      });
    } on GoogleAuthException catch (error) {
      if (mounted) {
        setState(() {
          _googleChecked = true;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _googleChecked = true);
    }
  }

  /// Restaure la sauvegarde Drive détectée (chiffrement AES-256-GCM local).
  Future<void> _restoreDriveBackup() async {
    final Map<String, dynamic>? envelope = _driveBackup;
    if (envelope == null) return;
    setState(() {
      _restoring = true;
      _error = null;
    });
    _backupStage.value = BackupStage.downloading;
    try {
      final Map<String, int> restored = await BackupService(widget.store)
          .restore(
            envelope,
            onStage: (BackupStage stage) => _backupStage.value = stage,
          );
      widget.revision.bump();
      if (!mounted) return;
      setState(() {
        _error =
            'Restauration terminée : ${restored['transactions']} mouvements et '
            '${restored['accounts']} comptes ajoutés.';
      });
    } on BackupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Restauration impossible (${error.runtimeType}).',
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// Importe la sauvegarde locale la plus récente (dossier de l'application).
  Future<void> _importLocalBackup() async {
    setState(() {
      _restoring = true;
      _error = null;
    });
    _backupStage.value = BackupStage.downloading;
    try {
      final BackupService service = BackupService(widget.store);
      final Map<String, dynamic>? envelope = await service.readFolder(
        '',
        onStage: (BackupStage stage) => _backupStage.value = stage,
      );
      if (envelope == null) {
        setState(() => _error = 'Aucune sauvegarde locale trouvée.');
        return;
      }
      final Map<String, int> restored = await service.restore(
        envelope,
        onStage: (BackupStage stage) => _backupStage.value = stage,
      );
      widget.revision.bump();
      if (!mounted) return;
      setState(() {
        _error =
            'Sauvegarde locale restaurée : ${restored['transactions']} '
            'mouvements.';
      });
    } on BackupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Import impossible (${error.runtimeType}).');
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// Demande la **vraie** autorisation système, et reflète l'état accordé.
  Future<void> _requestPermission(String kind, bool enable) async {
    if (!enable) {
      setState(() {
        switch (kind) {
          case 'notifications':
            _permissionNotifications = false;
          case 'sms':
            _permissionSms = false;
          case 'micro':
            _permissionMicro = false;
          case 'wifi':
            _permissionWifi = false;
        }
        _permissionNote = null;
      });
      return;
    }

    bool granted = false;
    try {
      switch (kind) {
        case 'notifications':
          await LocalNotifications.ensureReady(
            timezone: widget.settings.timezone,
          );
          granted = await LocalNotifications.requestPermission();
        case 'sms':
          granted = (await Permission.sms.request()).isGranted;
        case 'micro':
          granted = (await Permission.microphone.request()).isGranted;
        case 'wifi':
          granted =
              (await Permission.nearbyWifiDevices.request()).isGranted ||
              (await Permission.locationWhenInUse.request()).isGranted;
      }
    } catch (_) {
      granted = false;
    }

    if (!mounted) return;
    setState(() {
      switch (kind) {
        case 'notifications':
          _permissionNotifications = granted;
        case 'sms':
          _permissionSms = granted;
        case 'micro':
          _permissionMicro = granted;
        case 'wifi':
          _permissionWifi = granted;
      }
      _permissionNote = granted
          ? null
          : 'Autorisation refusée par le système : l’interrupteur reste '
                'désactivé. Vous pouvez la donner plus tard dans les réglages '
                'Android.';
    });
  }

  Future<void> _loadReserve() async {
    try {
      final int value = await widget.store.settingInt('reserve_securite');
      if (value > 0) _reserve.text = '$value';
    } catch (_) {
      // Pas de base : champ vide.
    }
  }

  void _recomputeOpeningTotal() {
    int total = 0;
    for (final TextEditingController controller in _openings.values) {
      total += int.tryParse(controller.text) ?? 0;
    }
    if (total != _openingTotal) setState(() => _openingTotal = total);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _pin.dispose();
    _pinConfirm.dispose();
    _reserve.dispose();
    _backupStage.dispose();
    for (final TextEditingController controller in _openings.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _go(int delta) async {
    final int next = (_step + delta).clamp(0, steps - 1);
    if (next == _step) return;
    setState(() {
      _step = next;
      _error = null;
    });
    await widget.settings.setOnboardingStep(next);
  }

  bool _validateStep() {
    switch (_step) {
      case 2: // E3 identité
        final String first = _firstName.text.trim();
        final String last = _lastName.text.trim();
        if (first.length < 2 || first.length > 40) {
          setState(() => _error = 'Le prénom doit faire 2 à 40 caractères.');
          return false;
        }
        if (last.isEmpty) {
          setState(() => _error = 'Indiquez votre nom.');
          return false;
        }
        return true;
      case 6: // PIN
        if (_pin.text.isEmpty) return true; // « Plus tard »
        if (_pin.text.length < 4 || _pin.text.length > 6) {
          setState(() => _error = 'Le PIN doit faire 4 à 6 chiffres.');
          return false;
        }
        if (PinVault.isTrivial(_pin.text)) {
          setState(() => _error = 'Ce PIN est trop facile à deviner.');
          return false;
        }
        if (_pin.text != _pinConfirm.text) {
          setState(() => _error = 'Les deux codes ne correspondent pas.');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  Future<void> _next() async {
    if (!_validateStep()) return;
    setState(() => _saving = true);
    try {
      await _persistStep();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Enregistrement impossible : ${error.runtimeType}.';
        });
      }
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;

    if (_step == steps - 1) {
      // Animation de sortie du logo avant la bascule vers l'accueil.
      final bool reduced =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      setState(() => _entering = true);
      if (!reduced) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      await widget.settings.setFlag('onboarding_done', true);
      widget.revision.bump();
      widget.onFinished();
      return;
    }
    await _go(1);
  }

  Future<void> _persistStep() async {
    switch (_step) {
      case 0:
        await widget.settings.set('language', _language);
        await widget.settings.setThemeId(_theme);
      case 2:
        await widget.settings.set('first_name', _firstName.text.trim());
        await widget.settings.set('last_name', _lastName.text.trim());
      case 3:
        await widget.settings.setCurrency(_currency);
        await widget.settings.set('timezone', _timezone);
        await widget.settings.set('date_style', _dateStyle);
      case 4:
        await widget.settings.setFlag('google_linked', _googleLinked);
      case 5:
        await widget.store.ensureDefaultAccounts();
        final List<Account> accounts = await widget.store.accounts();
        final DateTime now = DateTime.now();
        for (final Account account in accounts) {
          final int amount =
              int.tryParse(_openings[account.brand]?.text ?? '') ?? 0;
          if (amount <= 0) continue;
          await widget.store.saveTransaction(
            TransactionRecord(
              id: 'open-${account.id}-${now.microsecondsSinceEpoch}',
              accountId: account.id,
              amount: amount,
              kind: TransactionKind.opening,
              note: 'Solde de départ',
              occurredAt: now,
              createdAt: now,
            ),
          );
        }
      case 6:
        if (_pin.text.isNotEmpty) {
          await PinVault(widget.store).setPin(_pin.text);
        }
        await widget.settings.setFlag('biometrics', _biometrics);
      case 7:
        await widget.settings.setFlag(
          'permission_notifications',
          _permissionNotifications,
        );
        await widget.settings.setFlag('permission_sms', _permissionSms);
        await widget.settings.setFlag('permission_micro', _permissionMicro);
        await widget.settings.setFlag('permission_wifi', _permissionWifi);
      case 8:
        await widget.settings.set('savings_goal_percent', '$_savingsGoal');
        final int reserve = int.tryParse(_reserve.text.trim()) ?? 0;
        if (reserve > 0) {
          await widget.store.setSetting('reserve_securite', '$reserve');
        }
      case 9:
        await widget.settings.setFlag('simulation_mode', _simulation);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 900;
            return Row(
              children: <Widget>[
                if (wide)
                  Expanded(
                    child: _BrandPanel(step: _step, total: steps),
                  ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AkibaSpacing.screen,
                        AkibaSpacing.xl,
                        AkibaSpacing.screen,
                        AkibaSpacing.xxl,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _Dots(step: _step, total: steps),
                            const SizedBox(height: AkibaSpacing.xl),
                            AnimatedSwitcher(
                              duration: AkibaDurations.page,
                              child: KeyedSubtree(
                                key: ValueKey<int>(_step),
                                child: _stepBody(c),
                              ),
                            ),
                            if (_error != null) ...<Widget>[
                              const SizedBox(height: AkibaSpacing.md),
                              Text(
                                _error!,
                                style: AkibaTypography.legend.copyWith(
                                  color: c.danger,
                                ),
                              ),
                            ],
                            const SizedBox(height: AkibaSpacing.xxl),
                            Row(
                              children: <Widget>[
                                if (_step > 0)
                                  TextButton.icon(
                                    onPressed: _saving ? null : () => _go(-1),
                                    icon: const Icon(
                                      Icons.arrow_back_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Retour'),
                                  ),
                                const Spacer(),
                                FilledButton.icon(
                                  onPressed: _saving ? null : _next,
                                  icon: Icon(
                                    _step == steps - 1
                                        ? Icons.check_rounded
                                        : Icons.arrow_forward_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _step == steps - 1
                                        ? 'Entrer dans AKIBA'
                                        : 'Continuer',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            Text(
                              'Étape ${_step + 1} sur $steps',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stepBody(AkibaColors c) {
    return switch (_step) {
      0 => _welcome(c),
      1 => _value(c),
      2 => _identity(c),
      3 => _currencyStep(c),
      4 => _googleStep(c),
      5 => _accountsStep(c),
      6 => _pinStep(c),
      7 => _permissionsStep(c),
      8 => _habitsStep(c),
      9 => _dataStep(c),
      _ => _ready(c),
    };
  }

  Widget _title(AkibaColors c, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: AkibaTypography.screenTitle.copyWith(
            fontSize: 26,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: AkibaSpacing.sm),
        Text(
          subtitle,
          style: AkibaTypography.body.copyWith(color: c.textMuted, height: 1.5),
        ),
      ],
    );
  }

  Widget _welcome(AkibaColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, double value, Widget? child) {
              return Transform.translate(
                offset: Offset(0, 16 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: Container(
              width: 128,
              height: 128,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                boxShadow: c.heroShadow,
              ),
              child: Image.asset(
                c.isDark
                    ? 'assets/brand/akiba_mark_dark.png'
                    : 'assets/brand/akiba_mark_light.png',
                fit: BoxFit.contain,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? stack) =>
                        Icon(
                          Icons.savings_rounded,
                          size: 64,
                          color: c.terracotta,
                        ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AkibaSpacing.xl),
        Text(
          'Bienvenue dans AKIBA',
          textAlign: TextAlign.center,
          style: AkibaTypography.screenTitle.copyWith(
            fontSize: 26,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: AkibaSpacing.sm),
        Text(
          'Votre tirelire numérique pour suivre chaque franc, sans mélanger '
          'votre argent avec celui des autres.',
          textAlign: TextAlign.center,
          style: AkibaTypography.body.copyWith(color: c.textMuted, height: 1.5),
        ),
        const SizedBox(height: AkibaSpacing.xxl),
        Text(
          'Votre thème',
          style: AkibaTypography.sectionTitle.copyWith(color: c.textPrimary),
        ),
        const SizedBox(height: AkibaSpacing.xs),
        Text(
          'Il s’applique immédiatement à ce parcours et reste enregistré.',
          style: AkibaTypography.legend.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: AkibaSpacing.md),
        Wrap(
          spacing: AkibaSpacing.xs,
          runSpacing: AkibaSpacing.sm,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final AkibaThemeId id in AkibaThemeId.values)
              ThemeSwatch(
                id: id,
                selected: _theme == id,
                onTap: () {
                  setState(() => _theme = id);
                  widget.settings.setThemeId(id);
                },
              ),
          ],
        ),
        const SizedBox(height: AkibaSpacing.xl),
        Text(
          'Votre langue',
          style: AkibaTypography.sectionTitle.copyWith(color: c.textPrimary),
        ),
        const SizedBox(height: AkibaSpacing.xs),
        Text(
          'La langue choisie s’applique à la navigation et aux actions de '
          'l’accueil. Les écrans détaillés restent en français.',
          style: AkibaTypography.legend.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: AkibaSpacing.sm),
        Wrap(
          spacing: AkibaSpacing.sm,
          runSpacing: AkibaSpacing.sm,
          children: <Widget>[
            for (final (String key, String label) in <(String, String)>[
              ('fr', 'Français'),
              ('en', 'English'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _language == key,
                onSelected: (_) => setState(() => _language = key),
              ),
          ],
        ),
      ],
    );
  }

  Widget _value(AkibaColors c) {
    final List<({IconData icon, String title, String text})> cards =
        <({IconData icon, String title, String text})>[
          (
            icon: Icons.bolt_rounded,
            title: 'Moins de 10 secondes',
            text:
                'Une dépense, une entrée, un transfert : trois touches et '
                'c’est noté.',
          ),
          (
            icon: Icons.shield_outlined,
            title: 'Vos chiffres restent privés',
            text: 'Base chiffrée, masquage immédiat, argent de tiers isolé.',
          ),
          (
            icon: Icons.insights_rounded,
            title: 'Des décisions claires',
            text: 'Budgets, besoins priorisés et bilans en FCFA, sans jargon.',
          ),
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          c,
          'Pourquoi AKIBA ?',
          'Trois promesses simples, tenues hors ligne.',
        ),
        const SizedBox(height: AkibaSpacing.xl),
        for (final ({IconData icon, String title, String text}) card in cards)
          Padding(
            padding: const EdgeInsets.only(bottom: AkibaSpacing.md),
            child: AkibaSurfaceCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: c.iconTile,
                      borderRadius: BorderRadius.circular(AkibaRadii.iconTile),
                    ),
                    child: Icon(card.icon, size: 20, color: c.terracottaDeep),
                  ),
                  const SizedBox(width: AkibaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          card.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          card.text,
                          style: AkibaTypography.legend.copyWith(
                            color: c.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _identity(AkibaColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          c,
          'Comment vous appelez-vous ?',
          'Votre prénom apparaîtra sur l’accueil.',
        ),
        const SizedBox(height: AkibaSpacing.xl),
        TextField(
          controller: _firstName,
          textCapitalization: TextCapitalization.words,
          decoration: _field(c, 'Prénom'),
        ),
        const SizedBox(height: AkibaSpacing.md),
        TextField(
          controller: _lastName,
          textCapitalization: TextCapitalization.words,
          decoration: _field(c, 'Nom'),
        ),
      ],
    );
  }

  Widget _currencyStep(AkibaColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          c,
          'Votre devise et votre fuseau',
          'AKIBA est pensé pour le FCFA (XOF). Le choix de la devise ne change '
              'que l’affichage, jamais la valeur des montants.',
        ),
        const SizedBox(height: AkibaSpacing.xl),
        Wrap(
          spacing: AkibaSpacing.sm,
          runSpacing: AkibaSpacing.sm,
          children: <Widget>[
            for (final AkibaCurrency currency in AkibaCurrency.values)
              CurrencyBadge(
                currency: currency,
                selected: _currency == currency,
                onTap: () => setState(() => _currency = currency),
              ),
          ],
        ),
        const SizedBox(height: AkibaSpacing.lg),
        DropdownButtonFormField<String>(
          initialValue: _timezone,
          decoration: _field(c, 'Fuseau horaire'),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: 'Africa/Lome',
              child: Text('Africa/Lome (GMT)'),
            ),
            DropdownMenuItem<String>(
              value: 'Africa/Cotonou',
              child: Text('Africa/Cotonou (GMT+1)'),
            ),
            DropdownMenuItem<String>(
              value: 'Africa/Abidjan',
              child: Text('Africa/Abidjan (GMT)'),
            ),
            DropdownMenuItem<String>(
              value: 'Africa/Dakar',
              child: Text('Africa/Dakar (GMT)'),
            ),
            DropdownMenuItem<String>(
              value: 'Europe/Paris',
              child: Text('Europe/Paris'),
            ),
          ],
          onChanged: (String? value) {
            if (value != null) setState(() => _timezone = value);
          },
        ),
        const SizedBox(height: AkibaSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _dateStyle,
          decoration: _field(c, 'Format des dates'),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: 'jj/mm/aaaa',
              child: Text('jj/mm/aaaa (19/11/2026)'),
            ),
            DropdownMenuItem<String>(
              value: 'aaaa-mm-jj',
              child: Text('aaaa-mm-jj (2026-11-19)'),
            ),
          ],
          onChanged: (String? value) {
            if (value != null) setState(() => _dateStyle = value);
          },
        ),
      ],
    );
  }

  Widget _accountsStep(AkibaColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          c,
          'Vos comptes de départ',
          'Indiquez ce que vous avez aujourd’hui. Laissez vide si le compte '
              'est à zéro : rien n’est inventé.',
        ),
        const SizedBox(height: AkibaSpacing.lg),
        for (final AccountBrand brand in AccountBrand.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AkibaSpacing.md),
            child: Row(
              children: <Widget>[
                BrandLogo(brand: brand, size: BrandLogoSize.compact),
                const SizedBox(width: AkibaSpacing.md),
                Expanded(
                  child: Text(
                    brand.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _openings[brand],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    decoration: _field(c, '0').copyWith(
                      suffixText: _currency.symbol,
                      suffixStyle: AkibaTypography.legend.copyWith(
                        color: c.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AkibaSpacing.sm),
        AkibaSurfaceCard(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Total de départ',
                  style: AkibaTypography.body.copyWith(color: c.textMuted),
                ),
              ),
              Text(
                AkibaMoney.format(_openingTotal),
                style: AkibaTypography.money(20, color: c.textPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pinStep(AkibaColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          c,
          'Protégez l’accès',
          'Un code de 4 à 6 chiffres, ou la biométrie. Vous pouvez aussi '
              'choisir « Plus tard ».',
        ),
        const SizedBox(height: AkibaSpacing.xl),
        TextField(
          controller: _pin,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: _field(
            c,
            'Code PIN (facultatif)',
          ).copyWith(counterText: ''),
        ),
        const SizedBox(height: AkibaSpacing.md),
        TextField(
          controller: _pinConfirm,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: _field(c, 'Confirmer le PIN').copyWith(counterText: ''),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _biometrics,
          onChanged: (bool value) => setState(() => _biometrics = value),
          title: Text(
            'Déverrouillage biométrique',
            style: TextStyle(fontSize: 14, color: c.textPrimary),
          ),
          subtitle: Text(
            'Empreinte ou Windows Hello, avec repli PIN systématique.',
            style: AkibaTypography.legend.copyWith(color: c.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _googleStep(AkibaColors c) {
    final BackupMetadata? meta = _driveMeta;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          c,
          'Sauvegarde et restauration',
          'Connectez Google pour retrouver une sauvegarde AKIBA existante. '
              'Rien ne part sans votre action, et tout reste chiffré '
              'AES-256-GCM.',
        ),
        const SizedBox(height: AkibaSpacing.xl),
        AkibaSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    _googleEmail != null
                        ? Icons.verified_user_rounded
                        : Icons.cloud_outlined,
                    size: 18,
                    color: _googleEmail != null ? c.success : c.textMuted,
                  ),
                  const SizedBox(width: AkibaSpacing.sm),
                  Expanded(
                    child: Text(
                      _googleEmail != null
                          ? 'Compte lié : $_googleEmail'
                          : 'Aucun compte Google lié',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AkibaSpacing.xs),
              Text(
                _googleEmail != null
                    ? 'AKIBA a vérifié votre espace applicatif Drive.'
                    : GoogleOAuthConfig.isConfigured
                    ? 'La connexion ouvre le navigateur, puis AKIBA vérifie '
                          'automatiquement s’il existe une sauvegarde.'
                    : 'Les identifiants OAuth ne sont pas renseignés : vous '
                          'pouvez continuer hors ligne et connecter Google '
                          'plus tard depuis le Profil.',
                style: AkibaTypography.legend.copyWith(
                  color: c.textMuted,
                  height: 1.45,
                ),
              ),
              if (GoogleOAuthConfig.isConfigured &&
                  _googleEmail == null) ...<Widget>[
                const SizedBox(height: AkibaSpacing.md),
                FilledButton.icon(
                  onPressed: _saving ? null : _connectGoogle,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Se connecter avec Google'),
                ),
              ],
              if (_saving && _googleEmail == null) ...<Widget>[
                const SizedBox(height: AkibaSpacing.sm),
                const LinearProgressIndicator(minHeight: 3),
              ],
            ],
          ),
        ),
        if (_googleEmail != null && _googleChecked) ...<Widget>[
          const SizedBox(height: AkibaSpacing.lg),
          if (meta != null) ...<Widget>[
            AkibaSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Sauvegarde trouvée sur votre Drive',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.xs),
                  Text(
                    '${AkibaDate.short(meta.createdAt)} · '
                    '${meta.accounts} comptes · ${meta.transactions} '
                    'mouvements. La restauration ajoute les mouvements sans '
                    'jamais supprimer ni dupliquer vos données actuelles.',
                    style: AkibaTypography.legend.copyWith(
                      color: c.textMuted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.md),
                  FilledButton.icon(
                    onPressed: _restoring ? null : _restoreDriveBackup,
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('Restaurer cette sauvegarde'),
                  ),
                ],
              ),
            ),
          ] else ...<Widget>[
            Text(
              'Aucune sauvegarde AKIBA sur ce compte Google.',
              style: AkibaTypography.body.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: AkibaSpacing.md),
            Wrap(
              spacing: AkibaSpacing.sm,
              runSpacing: AkibaSpacing.sm,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _restoring ? null : _importLocalBackup,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Importer une sauvegarde locale'),
                ),
                TextButton.icon(
                  onPressed: _restoring ? null : _next,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Partir sur de bonnes bases'),
                ),
              ],
            ),
          ],
          const SizedBox(height: AkibaSpacing.md),
          BackupProgress(
            stage: _backupStage,
            active: _restoring,
            restoring: true,
          ),
        ],
      ],
    );
  }

  Widget _permissionsStep(AkibaColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          c,
          'Des permissions expliquées',
          'Rien n’est demandé sans raison, et tout se coupe depuis le Profil.',
        ),
        const SizedBox(height: AkibaSpacing.md),
        _permissionSwitch(
          c,
          title: 'Rappels matin, midi et soir',
          detail:
              'Notifications locales, sans montant si le masquage est actif.',
          value: _permissionNotifications,
          onChanged: (bool v) => _requestPermission('notifications', v),
        ),
        _permissionSwitch(
          c,
          title: 'Lecture des SMS financiers',
          detail:
              'Android uniquement : chaque SMS reste relu par vous avant '
              'enregistrement.',
          value: _permissionSms,
          onChanged: (bool v) => _requestPermission('sms', v),
        ),
        _permissionSwitch(
          c,
          title: 'Micro pour l’assistant',
          detail: 'La dictée n’est utilisée que lorsque vous appuyez.',
          value: _permissionMicro,
          onChanged: (bool v) => _requestPermission('micro', v),
        ),
        _permissionSwitch(
          c,
          title: 'Wi-Fi local (Home Lab)',
          detail: 'Pour sauvegarder sur votre serveur domestique, sans VPN.',
          value: _permissionWifi,
          onChanged: (bool v) => _requestPermission('wifi', v),
        ),
        const SizedBox(height: AkibaSpacing.sm),
        Text(
          'Chaque interrupteur démarre décoché et déclenche la vraie demande '
          'Android. S’il reste fermé, c’est que le système a refusé.',
          style: AkibaTypography.legend.copyWith(color: c.textMuted),
        ),
        if (_permissionNote != null) ...<Widget>[
          const SizedBox(height: AkibaSpacing.sm),
          Text(
            _permissionNote!,
            style: AkibaTypography.legend.copyWith(color: c.danger),
          ),
        ],
      ],
    );
  }

  Widget _permissionSwitch(
    AkibaColors c, {
    required String title,
    required String detail,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(title, style: TextStyle(fontSize: 14, color: c.textPrimary)),
      subtitle: Text(
        detail,
        style: AkibaTypography.legend.copyWith(color: c.textMuted),
      ),
    );
  }

  Widget _habitsStep(AkibaColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          c,
          'Vos habitudes',
          'AKIBA s’en sert pour proposer, jamais pour imposer.',
        ),
        const SizedBox(height: AkibaSpacing.xl),
        Text(
          'Part d’épargne visée : $_savingsGoal %',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        Slider(
          value: _savingsGoal.toDouble(),
          min: 0,
          max: 30,
          divisions: 6,
          label: '$_savingsGoal %',
          onChanged: (double value) =>
              setState(() => _savingsGoal = value.round()),
        ),
        Text(
          'Un versement est toujours neutre pour le solde disponible : il '
          'déplace votre argent, il ne le dépense pas.',
          style: AkibaTypography.legend.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: AkibaSpacing.xl),
        TextField(
          controller: _reserve,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          decoration: _field(c, 'Réserve de sécurité en FCFA (facultatif)'),
        ),
      ],
    );
  }

  Widget _dataStep(AkibaColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          c,
          'Vos données',
          'Choisissez la base réelle ou un mode simulation pour essayer sans '
              'risque.',
        ),
        const SizedBox(height: AkibaSpacing.xl),
        SegmentedControl(
          segments: const <String>['Données réelles', 'Simulation'],
          selectedIndex: _simulation ? 1 : 0,
          onChanged: (int index) => setState(() => _simulation = index == 1),
        ),
        const SizedBox(height: AkibaSpacing.md),
        Text(
          _simulation
              ? 'Le mode simulation est signalé par un bandeau permanent. Les '
                    'écritures restent locales et chiffrées.'
              : 'Vos écritures sont enregistrées dans la base locale chiffrée '
                    '(SQLCipher AES-256).',
          style: AkibaTypography.legend.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: AkibaSpacing.xl),
        AkibaSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Sauvegarde',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: AkibaSpacing.xs),
              Text(
                'Vous pourrez créer une sauvegarde AES-256-GCM (Google Drive '
                'ou Home Lab) depuis Profil → Sauvegarde.',
                style: AkibaTypography.legend.copyWith(
                  color: c.textMuted,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ready(AkibaColors c) {
    final bool reduced =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: reduced ? 1 : 0.4, end: 1),
            duration: Duration(milliseconds: reduced ? 0 : 700),
            curve: Curves.easeOutBack,
            builder: (BuildContext context, double value, Widget? child) =>
                Transform.scale(scale: value, child: child),
            child: AnimatedScale(
              // Au clic sur « Entrer dans AKIBA », le logo grandit et laisse
              // place à l'accueil (transition fluide).
              scale: _entering ? 1.35 : 1,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _entering ? 0.2 : 1,
                duration: const Duration(milliseconds: 600),
                child: Container(
                  width: 116,
                  height: 116,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: c.heroShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/brand/app_icon.png',
                      fit: BoxFit.contain,
                      errorBuilder:
                          (
                            BuildContext context,
                            Object error,
                            StackTrace? stack,
                          ) => Icon(
                            Icons.savings_rounded,
                            size: 64,
                            color: c.terracotta,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AkibaSpacing.lg),
        Text(
          'Prêt et bienvenue',
          textAlign: TextAlign.center,
          style: AkibaTypography.screenTitle.copyWith(
            fontSize: 26,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: AkibaSpacing.sm),
        Text(
          '${_firstName.text.trim().isEmpty ? 'Votre espace' : _firstName.text.trim()} est prêt : '
          '${_openingsTotalLabel()} de départ, devise $_currency, fuseau $_timezone.',
          textAlign: TextAlign.center,
          style: AkibaTypography.body.copyWith(color: c.textMuted, height: 1.5),
        ),
        const SizedBox(height: AkibaSpacing.xl),
        AkibaSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _RecapRow(
                label: 'Code d’accès',
                value: _pin.text.isEmpty
                    ? 'À configurer dans Profil'
                    : 'PIN activé',
              ),
              _RecapRow(
                label: 'Rappels',
                value: _permissionNotifications
                    ? 'Matin, midi, soir'
                    : 'Désactivés',
              ),
              _RecapRow(
                label: 'Données',
                value: _simulation ? 'Simulation' : 'Réelles, chiffrées',
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _openingsTotalLabel() {
    int total = 0;
    for (final TextEditingController controller in _openings.values) {
      total += int.tryParse(controller.text) ?? 0;
    }
    return AkibaMoney.format(total);
  }

  InputDecoration _field(AkibaColors c, String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: c.surfaceElevated,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AkibaSpacing.lg,
      vertical: AkibaSpacing.md,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AkibaRadii.field),
      borderSide: BorderSide.none,
    ),
  );
}

class _Dots extends StatelessWidget {
  const _Dots({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Wrap(
      spacing: 6,
      children: <Widget>[
        for (int index = 0; index < total; index++)
          AnimatedContainer(
            duration: AkibaDurations.fast,
            width: index == step ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: index <= step ? c.terracotta : c.surfaceElevated,
              borderRadius: BorderRadius.circular(AkibaRadii.pill),
            ),
          ),
      ],
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Container(
      decoration: BoxDecoration(gradient: c.balanceGradient),
      padding: const EdgeInsets.all(AkibaSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Image.asset(
            'assets/brand/akiba_mark_light.png',
            width: 64,
            height: 64,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stack) =>
                    Icon(Icons.savings_rounded, size: 48, color: c.sand),
          ),
          const SizedBox(height: AkibaSpacing.xl),
          Text(
            'AKIBA',
            style: AkibaTypography.screenTitle.copyWith(
              fontSize: 28,
              letterSpacing: 6,
              color: c.onTerracotta,
            ),
          ),
          const SizedBox(height: AkibaSpacing.sm),
          Text(
            'Chaque franc noté.\nChaque besoin priorisé.\nVos données, chez vous.',
            style: AkibaTypography.body.copyWith(
              color: c.onTerracotta.withValues(alpha: 0.85),
              height: 1.6,
            ),
          ),
          const Spacer(),
          Text(
            '${step + 1} / $total',
            style: AkibaTypography.money(16, color: c.sand),
          ),
        ],
      ),
    );
  }
}

class _RecapRow extends StatelessWidget {
  const _RecapRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AkibaSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: AkibaTypography.body.copyWith(color: c.textMuted),
            ),
          ),
          const SizedBox(width: AkibaSpacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
