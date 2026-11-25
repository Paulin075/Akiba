import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/backup/google_drive_backup.dart';
import '../../core/format/akiba_currency.dart';
import '../../core/format/akiba_date.dart';
import '../../core/profile/avatar_editor.dart';
import '../../core/notifications/local_notifications.dart';
import '../../core/notifications/background_reminders.dart';
import '../../core/notifications/reminder_planner.dart';
import '../../core/notifications/reminder_scheduler.dart';
import '../../core/profile/profile_photo.dart';
import '../../core/report/monthly_report.dart';
import '../../core/report/report_pdf.dart';
import '../../core/report/report_scheduler.dart';
import '../../core/security/pin_vault.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/state/akiba_l10n.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/state/masked_amounts.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_theme.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/currency_logo.dart';
import '../../core/widgets/icon_circle_button.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../core/widgets/segmented_control.dart';
import '../../core/widgets/theme_swatch.dart';
import '../../data/akiba_store.dart';
import '../assistant/ai_settings_sheet.dart';
import '../assistant/assistant_sheet.dart';
import '../backup/backup_center.dart';
import '../report/report_preview.dart';
import '../sms/sms_review_sheet.dart';

/// Écran Profil : mosaïque Bento regroupant sécurité, apparence,
/// préférences, rappels et accès aux modules.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.store,
    required this.settings,
    required this.revision,
    required this.onReplayOnboarding,
    this.reprogramReminders,
    this.notificationPermissionCheck,
    this.notificationsSupported,
  });

  final AkibaStore store;
  final AkibaSettings settings;
  final AkibaDataRevision revision;
  final VoidCallback onReplayOnboarding;
  final Future<int> Function(AkibaSettings settings)? reprogramReminders;
  final Future<bool> Function()? notificationPermissionCheck;
  final bool? notificationsSupported;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  String _notifStatus = '';
  bool _reportBusy = false;
  late final TextEditingController _reportEmail = TextEditingController(
    text: _s.raw('report_email'),
  );
  late final TextEditingController _reportWhatsapp = TextEditingController(
    text: _s.raw('report_whatsapp'),
  );

  AkibaSettings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshNotificationPermission();
  }

  Future<void> _refreshNotificationPermission() async {
    if (!LocalNotifications.supported) return;
    final bool granted = await LocalNotifications.permissionGranted();
    await _s.setFlag('permission_notifications', granted);
    if (ReminderScheduler.anyEnabled(_s)) {
      await ReminderScheduler.reprogram(_s, store: _s.store);
    }
    if (!mounted) return;
    setState(
      () => _notifStatus = granted
          ? 'Autorisation de notification accordée par le système.'
          : 'Notifications non autorisées par le système.',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reportEmail.dispose();
    _reportWhatsapp.dispose();
    super.dispose();
  }

  // ------------------------------------------------------- Photo de profil

  /// Choisit une photo locale, puis la range chiffrée sur l'appareil.
  Future<void> _pickPhoto() async {
    final ProfilePhotoController? photo = ProfilePhotoScope.maybeOf(context);
    if (photo == null) {
      _toast('Photo indisponible dans cet écran.', error: true);
      return;
    }
    try {
      final XFile? chosen = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (chosen == null) return;
      final Uint8List bytes = await chosen.readAsBytes();
      if (!mounted) return;
      // Ajustement (déplacement + zoom) avant l'enregistrement chiffré.
      final Uint8List? adjusted = await showAvatarEditor(context, bytes);
      if (adjusted == null) return;
      await photo.update(adjusted);
      await _s.set(
        'profile_photo_updated_at',
        DateTime.now().toIso8601String(),
      );
      if (!mounted) return;
      _toast('Photo de profil mise à jour, chiffrée sur cet appareil.');
    } on ProfilePhotoException catch (error) {
      if (mounted) _toast(error.message, error: true);
    } catch (error) {
      if (mounted) {
        _toast(
          'Photo impossible à importer (${error.runtimeType}).',
          error: true,
        );
      }
    }
  }

  Future<void> _viewPhoto() async {
    final ProfilePhotoController? photo = ProfilePhotoScope.maybeOf(context);
    final Uint8List? bytes = photo?.bytes;
    if (bytes == null) {
      await _pickPhoto();
      return;
    }
    await showAvatarViewer(context, bytes);
  }

  Future<void> _removePhoto() async {
    final ProfilePhotoController? photo = ProfilePhotoScope.maybeOf(context);
    if (photo == null) return;
    await photo.remove();
    await _s.set('profile_photo_updated_at', '');
    if (mounted) _toast('Photo retirée : avatar par défaut.');
  }

  void _toast(String message, {bool error = false}) {
    final AkibaColors c = AkibaColors.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? c.danger : c.textPrimary,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // ------------------------------------------------------------- Sécurité

  Future<void> _togglePin(bool enable) async {
    if (!enable) {
      final bool ok = await _askPin();
      if (!ok) return;
      // Toujours le magasin des réglages (base réelle), même en simulation :
      // c'est lui que lit le verrouillage au démarrage.
      await PinVault(_s.store).clear(_s.store);
      await _s.setFlag('biometrics', false);
      await _s.load();
      _toast('Code PIN retiré.');
      return;
    }

    final bool configured = _s.pinEnabled;
    final String? newPin = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _PinDialog(store: _s.store, requireCurrent: configured),
    );
    if (newPin == null) return;
    await _s.load();
    _toast('Code PIN activé.');
  }

  Future<bool> _askPin() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) =>
          _VerifyPinDialog(vault: PinVault(_s.store)),
    );
    return result ?? false;
  }

  Future<void> _changePin() async {
    await _togglePin(true);
  }

  Future<void> _toggleBiometrics(bool value) async {
    if (!value) {
      await _s.setFlag('biometrics', false);
      return;
    }
    if (!_s.pinEnabled) {
      _toast('Activez d’abord un code PIN : il reste le repli obligatoire.');
      return;
    }
    try {
      final LocalAuthentication auth = LocalAuthentication();
      final bool supported =
          await auth.isDeviceSupported() && await auth.canCheckBiometrics;
      if (!supported) {
        _toast(
          'La biométrie n’est pas disponible sur cet appareil ou ce poste.',
          error: true,
        );
        return;
      }
      final bool ok = await auth.authenticate(
        localizedReason: 'Activer le déverrouillage biométrique d’AKIBA',
      );
      if (!ok) return;
      await _s.setFlag('biometrics', true);
      _toast('Déverrouillage biométrique activé.');
    } catch (error) {
      _toast('Biométrie indisponible (${error.runtimeType}).', error: true);
    }
  }

  // ---------------------------------------------------------- Notifications

  Future<void> _reschedule() async {
    if (!ReminderScheduler.anyEnabled(_s)) {
      await LocalNotifications.cancelAll();
      await BackgroundReminders.cancel();
      if (!mounted) return;
      setState(() => _notifStatus = 'Tous les rappels sont désactivés.');
      return;
    }

    final bool supported =
        widget.notificationsSupported ?? LocalNotifications.supported;
    // Un seul chemin de planification : greffon initialisé, autorisation
    // mémorisée, échéances de dettes incluses, Workmanager inscrit une fois.
    final int scheduled =
        await (widget.reprogramReminders?.call(_s) ??
            ReminderScheduler.reprogram(
              _s,
              store: _s.store,
              requestPermission: true,
            ));
    if (!mounted) return;
    // Un échec de planification peut venir d'une permission révoquée : on
    // relit l'état réel pour ne pas annoncer « refusé » à tort.
    final bool granted = supported
        ? await (widget.notificationPermissionCheck?.call() ??
              LocalNotifications.permissionGranted())
        : false;
    if (!mounted) return;
    setState(() {
      if (!supported) {
        _notifStatus =
            'Les rappels sont prêts pour 7 jours. La livraison système '
            'Windows n’est pas encore prise en charge : les messages '
            's’affichent dans AKIBA.';
      } else if (scheduled > 0) {
        _notifStatus =
            '$scheduled rappels planifiés sur 7 jours, échéances de créances '
            'et de dettes comprises. Aucun montant, aucun nom de contact.';
      } else if (!granted) {
        _notifStatus =
            'Notifications non autorisées par le système : la demande a été '
            'tentée. Ouvrez les réglages Android d’AKIBA pour autoriser les '
            'notifications, puis appuyez de nouveau sur Reprogrammer.';
      } else {
        _notifStatus =
            'Autorisation générale accordée, mais aucun rappel planifié. '
            'Vérifiez que le canal « Rappels AKIBA » est activé dans les '
            'réglages de notifications Android.';
      }
    });
    if (scheduled > 0 &&
        widget.notificationPermissionCheck == null &&
        Platform.isAndroid) {
      final bool? channelEnabled =
          await LocalNotifications.androidChannelEnabled('akiba_rappels');
      if (!mounted || channelEnabled != false) return;
      setState(
        () => _notifStatus =
            'Autorisation générale accordée, mais le canal « Rappels AKIBA » '
            'est désactivé dans Android. Activez-le dans les réglages de '
            'notifications de l’application.',
      );
    }
  }

  Future<void> _pickTime({
    required String key,
    required String current,
    required String label,
  }) async {
    final ({int hour, int minute}) parsed = ReminderPlanner.parseTime(current);
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: parsed.hour, minute: parsed.minute),
      helpText: label,
    );
    if (picked == null) return;
    final String value =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    await _s.set(key, value);
    await _reschedule();
  }

  Future<void> _toggleFestive(bool value) async {
    await _s.setFlag('festive_enabled', value);
    await _reschedule();
  }

  Future<void> _editFestiveLabel() async {
    final TextEditingController controller = TextEditingController(
      text: _s.festiveLabel,
    );
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        final AkibaColors c = AkibaColors.of(context);
        return AlertDialog(
          backgroundColor: c.surface,
          title: const Text('Nom de la période de fête'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Ex. Fêtes de fin d’année',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (value == null) return;
    await _s.set('festive_label', value);
  }

  // -------------------------------------------------------------- Modules

  Future<void> _openAssistant() async {
    await openAssistant(
      context,
      store: widget.store,
      revision: widget.revision,
      masked: MaskedAmounts.of(context),
      settings: widget.settings,
    );
  }

  Future<void> _openAiSettings() async {
    await openAiSettings(context, settings: widget.settings);
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------ Rapport mensuel

  Future<void> _saveReportContacts() async {
    await _s.set('report_email', _reportEmail.text.trim());
    await _s.set('report_whatsapp', _reportWhatsapp.text.trim());
  }

  /// Génère le PDF à la demande, l'ouvre en prévisualisation, puis le copie
  /// éventuellement vers le Home Lab. Les montants sont en clair dans le
  /// rapport ; rien n'est envoyé sans ce geste.
  Future<void> _openReport() async {
    if (_reportBusy) return;
    final Uint8List? profilePhotoBytes = ProfilePhotoScope.maybeOf(
      context,
    )?.bytes;
    setState(() => _reportBusy = true);
    await _saveReportContacts();
    try {
      final ReportPeriod period = ReportPeriod.fromStorage(
        _s.raw('report_period'),
      );
      MonthlyReport report = await MonthlyReport.build(
        store: widget.store,
        settings: _s,
        period: period,
        profilePhotoBytes: profilePhotoBytes,
      );
      report = await const ReportAdvisor().enrich(report, _s);
      final Uint8List bytes = await const ReportPdfBuilder().build(report);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              ReportPreviewScreen(report: report, bytes: bytes, settings: _s),
        ),
      );
      await _s.set(
        'report_last_generated_at',
        DateTime.now().toIso8601String(),
      );
      if (_s.flag('report_home_lab')) {
        final bool sent = await ReportScheduler.sendToHomeLab(
          settings: _s,
          pdf: bytes,
        );
        _toast(
          sent
              ? 'Rapport copié vers le Home Lab.'
              : 'Home Lab injoignable : le PDF reste disponible.',
          error: !sent,
        );
      }
      if (mounted) setState(() {});
    } catch (_) {
      _toast('Génération du rapport impossible.', error: true);
    } finally {
      if (mounted) setState(() => _reportBusy = false);
    }
  }

  Future<void> _openSms() async {
    await openSmsReview(
      context,
      store: widget.store,
      revision: widget.revision,
      masked: MaskedAmounts.of(context),
    );
  }

  /// Active la détection SMS en arrière-plan (Flooz, Mixx by Yas, banques).
  ///
  /// L'autorisation système est la seule clé : sans elle, le récepteur Android
  /// ne reçoit rien. Le drapeau n'est qu'un reflet pour l'interface.
  Future<void> _enableSmsDetection() async {
    PermissionStatus status = await Permission.sms.status;
    if (!status.isGranted) status = await Permission.sms.request();
    await _s.setFlag('permission_sms', status.isGranted);
    if (!mounted) return;
    if (status.isGranted) {
      _toast(
        'Détection SMS activée : un dépôt ou retrait détecté ouvre la fiche '
        'à confirmer, jamais une écriture automatique.',
      );
    } else if (status.isPermanentlyDenied) {
      _toast(
        'Autorisation SMS refusée définitivement : ouvrez les réglages du '
        'système pour l’accorder à AKIBA.',
        error: true,
      );
      await openAppSettings();
    } else {
      _toast(
        'Autorisation SMS refusée : la détection reste désactivée.',
        error: true,
      );
    }
  }

  Future<void> _openBackup() async {
    await openBackupCenter(
      context,
      store: widget.store,
      settings: widget.settings,
      revision: widget.revision,
      masked: MaskedAmounts.of(context),
    );
    if (!mounted) return;
    setState(() {});
  }

  /// Déconnexion explicite du compte Google lié.
  ///
  /// La session et le jeton durable sont retirés (coffre du système), mais les
  /// données locales chiffrées ne sont **jamais** supprimées : aucune
  /// opération destructive n'est lancée sans une confirmation distincte.
  Future<void> _signOut() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Le compte Google lié et la session de sauvegarde seront retirés. '
          'Vos données locales chiffrées restent intactes : rien n’est '
          'supprimé et AKIBA reste utilisable hors ligne.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await GoogleDriveService().signOut();
    } catch (_) {
      // Coffre indisponible : le drapeau local suffit à repasser hors ligne.
    }
    await _s.setFlag('google_linked', false);
    await _s.set('last_backup_target', '');
    if (!mounted) return;
    _toast('Déconnecté. Vos données locales chiffrées sont conservées.');
  }

  // -------------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final bool masked = MaskedAmounts.of(context);
    final String name = _s.firstName.isEmpty
        ? AkibaL10n.tr('my_profile')
        : _s.firstName;
    final ProfilePhotoController? photo = ProfilePhotoScope.maybeOf(context);

    // Une valeur enregistrée inconnue (restauration, ancienne version) doit
    // rester sélectionnable : sinon `DropdownButton` lève l'assertion
    // « exactly one item with value ». Les dates retombent sur le format
    // français par défaut.
    const List<String> knownTimezones = <String>[
      'Africa/Lome',
      'Africa/Cotonou',
      'Africa/Abidjan',
      'Africa/Dakar',
      'Europe/Paris',
    ];
    final List<String> timezones = <String>[
      ...knownTimezones,
      if (!knownTimezones.contains(_s.timezone)) _s.timezone,
    ];
    final String dateStyle =
        const <String>['jj/mm/aaaa', 'aaaa-mm-jj'].contains(_s.dateStyle)
        ? _s.dateStyle
        : 'jj/mm/aaaa';

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double maxContent = 1120;
        final double contentWidth = (width - AkibaSpacing.screen * 2).clamp(
          0,
          maxContent,
        );
        final int columns = contentWidth >= 980
            ? 3
            : contentWidth >= 640
            ? 2
            : 1;
        final double tileWidth =
            (contentWidth - AkibaSpacing.lg * (columns - 1)) / columns;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AkibaSpacing.screen,
            AkibaSpacing.lg,
            AkibaSpacing.screen,
            160,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContent),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      ProfileAvatar(
                        bytes: photo?.bytes,
                        name: _s.firstName,
                        size: 62,
                        onTap: (photo?.hasPhoto ?? false)
                            ? _viewPhoto
                            : _pickPhoto,
                      ),
                      const SizedBox(width: AkibaSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              AkibaL10n.tr('profile_label'),
                              style: AkibaTypography.label.copyWith(
                                color: c.textMuted,
                                letterSpacing: 1.6,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AkibaTypography.screenTitle.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: AkibaSpacing.sm,
                              children: <Widget>[
                                TextButton(
                                  onPressed: _pickPhoto,
                                  child: Text(
                                    photo?.hasPhoto ?? false
                                        ? AkibaL10n.tr('change_photo')
                                        : AkibaL10n.tr('add_photo'),
                                  ),
                                ),
                                if (photo?.hasPhoto ?? false)
                                  TextButton(
                                    onPressed: _removePhoto,
                                    child: Text(AkibaL10n.tr('remove')),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconCircleButton(
                        icon: masked
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        tooltip: masked
                            ? AkibaL10n.tr('show_amounts')
                            : AkibaL10n.tr('hide_amounts'),
                        onTap: () => MaskedAmounts.toggle(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: AkibaSpacing.xxl),
                  Wrap(
                    spacing: AkibaSpacing.lg,
                    runSpacing: AkibaSpacing.lg,
                    children: <Widget>[
                      _tile(
                        c,
                        tileWidth,
                        title: AkibaL10n.tr('security'),
                        icon: Icons.lock_outline_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _switchRow(
                              c,
                              'Code PIN',
                              _s.pinEnabled
                                  ? 'Actif · 4 à 6 chiffres, empreinte salée'
                                  : 'Aucun code : l’accès est direct',
                              _s.pinEnabled,
                              _togglePin,
                            ),
                            if (_s.pinEnabled)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: _changePin,
                                  child: const Text('Changer le code PIN'),
                                ),
                              ),
                            _switchRow(
                              c,
                              'Biométrie / Hello',
                              'Repli PIN systématique',
                              _s.biometrics,
                              _toggleBiometrics,
                            ),
                            _switchRow(
                              c,
                              'Verrouiller au retour',
                              'À chaque sortie d’arrière-plan',
                              _s.lockOnResume,
                              (bool v) => _s.setFlag('lock_on_resume', v),
                            ),
                          ],
                        ),
                      ),
                      _tile(
                        c,
                        tileWidth,
                        title: AkibaL10n.tr('privacy'),
                        icon: Icons.visibility_off_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _switchRow(
                              c,
                              'Masquer les montants',
                              'Partout : accueil, portefeuille, analyses, '
                                  'rappels',
                              masked,
                              (_) => MaskedAmounts.toggle(context),
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            Text(
                              'Aucune notification ne contient de montant, '
                              'même quand le masquage est désactivé.',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _tile(
                        c,
                        tileWidth,
                        title: AkibaL10n.tr('appearance'),
                        icon: Icons.palette_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              AkibaL10n.tr('theme'),
                              style: AkibaTypography.label.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            Wrap(
                              spacing: AkibaSpacing.sm,
                              runSpacing: AkibaSpacing.sm,
                              children: <Widget>[
                                for (final AkibaThemeId id
                                    in AkibaThemeId.values)
                                  ThemeSwatch(
                                    id: id,
                                    selected: _s.themeId == id,
                                    onTap: () => _s.setThemeId(id),
                                  ),
                              ],
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            Text(
                              AkibaL10n.tr('appearance_note'),
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            _switchRow(
                              c,
                              AkibaL10n.tr('reduce_animations'),
                              'Fondu rapide de 150 ms, jauges sans rebond',
                              _s.reduceAnimations,
                              _s.setReduceAnimations,
                            ),
                          ],
                        ),
                      ),
                      _tile(
                        c,
                        tileWidth,
                        title: AkibaL10n.tr('preferences'),
                        icon: Icons.tune_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              AkibaL10n.tr('currency'),
                              style: AkibaTypography.label.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            Wrap(
                              spacing: AkibaSpacing.sm,
                              runSpacing: AkibaSpacing.sm,
                              children: <Widget>[
                                for (final AkibaCurrency currency
                                    in AkibaCurrency.values)
                                  CurrencyBadge(
                                    currency: currency,
                                    selected: _s.currencyCode == currency,
                                    onTap: () => _s.setCurrency(currency),
                                  ),
                              ],
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            Text(
                              AkibaL10n.tr('currency_note'),
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            Text(
                              AkibaL10n.tr('language'),
                              style: AkibaTypography.label.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            SegmentedControl(
                              segments: const <String>['Français', 'English'],
                              selectedIndex: _s.language == 'en' ? 1 : 0,
                              onChanged: (int index) =>
                                  _s.setLanguage(index == 1 ? 'en' : 'fr'),
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            Text(
                              AkibaL10n.tr('language_note'),
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            DropdownButtonFormField<String>(
                              initialValue: dateStyle,
                              isDense: true,
                              isExpanded: true,
                              decoration: _field(c, AkibaL10n.tr('dates')),
                              items: const <DropdownMenuItem<String>>[
                                DropdownMenuItem<String>(
                                  value: 'jj/mm/aaaa',
                                  child: Text('19/11/2026'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'aaaa-mm-jj',
                                  child: Text('2026-11-19'),
                                ),
                              ],
                              onChanged: (String? value) {
                                if (value != null) _s.set('date_style', value);
                              },
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            DropdownButtonFormField<String>(
                              initialValue: _s.timezone,
                              isDense: true,
                              isExpanded: true,
                              decoration: _field(c, AkibaL10n.tr('timezone')),
                              items: <DropdownMenuItem<String>>[
                                for (final String zone in timezones)
                                  DropdownMenuItem<String>(
                                    value: zone,
                                    child: Text(zone),
                                  ),
                              ],
                              onChanged: (String? value) {
                                if (value != null) _s.set('timezone', value);
                              },
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            Text(
                              AkibaL10n.tr('timezone_note'),
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _tile(
                        c,
                        tileWidth * (columns > 1 ? 2 : 1) +
                            (columns > 1 ? AkibaSpacing.lg : 0),
                        title: AkibaL10n.tr('daily_reminders'),
                        icon: Icons.notifications_none_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _slotRow(
                              c,
                              key: 'notif_morning',
                              timeKey: 'notif_morning_time',
                              enabled: _s.morningEnabled,
                              time: _s.morningTime,
                              title: 'Matin',
                              detail:
                                  'Démarrage & transport · 07:30 par défaut',
                            ),
                            _slotRow(
                              c,
                              key: 'notif_noon',
                              timeKey: 'notif_noon_time',
                              enabled: _s.noonEnabled,
                              time: _s.noonTime,
                              title: 'Midi',
                              detail: 'Pause déjeuner & achats',
                            ),
                            _slotRow(
                              c,
                              key: 'notif_evening',
                              timeKey: 'notif_evening_time',
                              enabled: _s.eveningEnabled,
                              time: _s.eveningTime,
                              title: 'Soir',
                              detail: 'Clôture & bilan de journée',
                            ),
                            _switchRow(
                              c,
                              'Rappel de dépenses',
                              'Entre 17 h et 20 h · sans montant',
                              _s.expenseReminderEnabled,
                              (bool enabled) async {
                                await _s.setFlag('notif_expense', enabled);
                                await _reschedule();
                              },
                            ),
                            const Divider(height: AkibaSpacing.xl),
                            _switchRow(
                              c,
                              'Ne pas déranger',
                              '${_s.dndStart} → ${_s.dndEnd}',
                              _s.dndEnabled,
                              (bool v) async {
                                await _s.setFlag('dnd_enabled', v);
                                await _reschedule();
                              },
                            ),
                            Wrap(
                              spacing: AkibaSpacing.sm,
                              children: <Widget>[
                                TextButton(
                                  onPressed: () => _pickTime(
                                    key: 'dnd_start',
                                    current: _s.dndStart,
                                    label: 'Début du silence',
                                  ),
                                  child: Text('Début ${_s.dndStart}'),
                                ),
                                TextButton(
                                  onPressed: () => _pickTime(
                                    key: 'dnd_end',
                                    current: _s.dndEnd,
                                    label: 'Fin du silence',
                                  ),
                                  child: Text('Fin ${_s.dndEnd}'),
                                ),
                              ],
                            ),
                            const Divider(height: AkibaSpacing.xl),
                            _switchRow(
                              c,
                              'Périodes de fête',
                              'Noël, Nouvel An, fêtes locales, rentrée',
                              _s.festiveEnabled,
                              _toggleFestive,
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _editFestiveLabel,
                                icon: const Icon(
                                  Icons.celebration_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  _s.festiveLabel.isEmpty
                                      ? 'Nommer ma période (facultatif)'
                                      : _s.festiveLabel,
                                ),
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    _notifStatus.isEmpty
                                        ? 'Messages variés, jamais de montant. '
                                              'Planification locale, sans réseau.'
                                        : _notifStatus,
                                    style: AkibaTypography.legend.copyWith(
                                      color: c.textMuted,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AkibaSpacing.sm),
                                OutlinedButton(
                                  onPressed: _reschedule,
                                  child: const Text('Reprogrammer'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _tile(
                        c,
                        tileWidth,
                        title: AkibaL10n.tr('ai_assistant'),
                        icon: Icons.auto_awesome_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              'Texte ou micro : AKIBA propose une opération, '
                              'vous corrigez puis confirmez. Aucune exécution '
                              'automatique.',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            _moduleRow(
                              c,
                              icon: _s.aiKeyConfigured
                                  ? Icons.key_rounded
                                  : Icons.key_off_rounded,
                              title: _s.aiKeyConfigured
                                  ? 'Clé API · ••••••••'
                                  : 'Aucune clé API',
                              detail: _s.aiRemoteEnabled
                                  ? 'Modèles distants autorisés, cascade '
                                        'automatique'
                                  : 'Analyse locale uniquement',
                            ),
                            const SizedBox(height: AkibaSpacing.md),
                            FilledButton.icon(
                              onPressed: _openAssistant,
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18,
                              ),
                              label: const Text('Ouvrir l’assistant'),
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            OutlinedButton.icon(
                              onPressed: _openAiSettings,
                              icon: const Icon(Icons.tune_rounded, size: 18),
                              label: const Text('Clé et modèles'),
                            ),
                          ],
                        ),
                      ),
                      _tile(
                        c,
                        tileWidth,
                        title: AkibaL10n.tr('sms_title'),
                        icon: Icons.sms_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              'Flooz, Mixx by Yas et banques : un SMS de dépôt '
                              'ou de retrait ouvre une fiche à confirmer, jamais '
                              'une écriture automatique.',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            _moduleRow(
                              c,
                              icon: _s.flag('permission_sms')
                                  ? Icons.mark_email_read_outlined
                                  : Icons.mark_email_unread_outlined,
                              title: _s.flag('permission_sms')
                                  ? 'Détection automatique active'
                                  : 'Détection automatique inactive',
                              detail: _s.flag('permission_sms')
                                  ? 'Application fermée comprise · notification '
                                        'sans montant'
                                  : 'Autorisation SMS requise',
                            ),
                            const SizedBox(height: AkibaSpacing.md),
                            Wrap(
                              spacing: AkibaSpacing.sm,
                              runSpacing: AkibaSpacing.sm,
                              children: <Widget>[
                                OutlinedButton.icon(
                                  onPressed: _openSms,
                                  icon: const Icon(
                                    Icons.fact_check_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Relire des SMS'),
                                ),
                                if (!_s.flag('permission_sms'))
                                  FilledButton.icon(
                                    onPressed: _enableSmsDetection,
                                    icon: const Icon(
                                      Icons.sms_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Activer la détection'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _tile(
                        c,
                        tileWidth,
                        title: AkibaL10n.tr('backup_sync'),
                        icon: Icons.cloud_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _moduleRow(
                              c,
                              icon: Icons.add_to_drive_outlined,
                              title: 'Google Drive',
                              detail: _s.driveFolder.isEmpty
                                  ? 'Dossier synchronisé, non configuré'
                                  : _s.driveFolder,
                            ),
                            _moduleRow(
                              c,
                              icon: Icons.home_work_outlined,
                              title: 'Home Lab Backup',
                              detail: _s.labUrl.isEmpty
                                  ? 'Wi-Fi domestique, non configuré'
                                  : _s.labUrl,
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            FilledButton.icon(
                              onPressed: _openBackup,
                              icon: const Icon(Icons.lock_rounded, size: 18),
                              label: const Text('Centre de sauvegarde'),
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            OutlinedButton.icon(
                              onPressed: _signOut,
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              label: const Text('Se déconnecter'),
                            ),
                          ],
                        ),
                      ),
                      _tile(
                        c,
                        tileWidth * (columns > 1 ? 2 : 1) +
                            (columns > 1 ? AkibaSpacing.lg : 0),
                        title: 'Rapport mensuel',
                        icon: Icons.picture_as_pdf_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              'PDF généré et prévisualisé sur l’appareil, '
                              'dans la langue et le thème actifs. Les montants y '
                              'restent en clair, même si le masquage est actif '
                              'ailleurs ; l’argent de tiers et les dettes '
                              'restent isolés.',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.md),
                            DropdownButtonFormField<ReportPeriod>(
                              initialValue: ReportPeriod.fromStorage(
                                _s.raw('report_period'),
                              ),
                              isDense: true,
                              decoration: InputDecoration(
                                labelText: 'Période',
                                isDense: true,
                                filled: true,
                                fillColor: c.surfaceElevated,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AkibaRadii.field,
                                  ),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              items: <DropdownMenuItem<ReportPeriod>>[
                                for (final ReportPeriod period
                                    in ReportPeriod.values)
                                  DropdownMenuItem<ReportPeriod>(
                                    value: period,
                                    child: Text(
                                      period.label(_s.language),
                                      style: TextStyle(color: c.textPrimary),
                                    ),
                                  ),
                              ],
                              onChanged: (ReportPeriod? value) async {
                                if (value == null) return;
                                await _s.set('report_period', value.name);
                                if (mounted) setState(() {});
                              },
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            _switchRow(
                              c,
                              'Données de simulation',
                              'Le rapport utilise alors les données d’essai '
                                  'locales',
                              _s.simulationMode,
                              (bool v) async {
                                await _s.setFlag('simulation_mode', v);
                                widget.revision.bump();
                                if (mounted) setState(() {});
                              },
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            TextField(
                              controller: _reportEmail,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: 'Destinataire Email',
                                hintText: 'nom@exemple.com',
                                isDense: true,
                                filled: true,
                                fillColor: c.surfaceElevated,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AkibaRadii.field,
                                  ),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) => _saveReportContacts(),
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            TextField(
                              controller: _reportWhatsapp,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Numéro WhatsApp',
                                hintText: '+228 90 00 00 00',
                                isDense: true,
                                filled: true,
                                fillColor: c.surfaceElevated,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AkibaRadii.field,
                                  ),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) => _saveReportContacts(),
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            _switchRow(
                              c,
                              'Fin de mois',
                              'Généré au premier lancement du mois suivant, '
                                  'sans réseau',
                              _s.flag('report_end_of_month'),
                              (bool v) async {
                                await _s.setFlag('report_end_of_month', v);
                                if (mounted) setState(() {});
                              },
                            ),
                            _switchRow(
                              c,
                              'Copier vers le Home Lab',
                              _s.labUrl.isEmpty
                                  ? 'Home Lab non configuré'
                                  : _s.labUrl,
                              _s.flag('report_home_lab'),
                              (bool v) {
                                if (_s.labUrl.isEmpty) {
                                  _toast(
                                    'Configurez le Home Lab dans Sauvegarde avant '
                                    'd’activer la copie.',
                                    error: true,
                                  );
                                  return;
                                }
                                _s.setFlag('report_home_lab', v);
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            _moduleRow(
                              c,
                              icon: _s.aiRemoteEnabled
                                  ? Icons.auto_awesome_rounded
                                  : Icons.offline_bolt_outlined,
                              title: _s.aiRemoteEnabled
                                  ? 'Avis IA activé'
                                  : 'Analyse locale déterministe',
                              detail: _s.aiRemoteEnabled
                                  ? 'Repli local instantané si hors ligne'
                                  : 'Aucune clé IA requise',
                            ),
                            const SizedBox(height: AkibaSpacing.md),
                            FilledButton.icon(
                              onPressed: _reportBusy ? null : _openReport,
                              style: FilledButton.styleFrom(
                                backgroundColor: c.terracotta,
                                foregroundColor: c.onTerracotta,
                              ),
                              icon: _reportBusy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.preview_outlined,
                                      size: 18,
                                    ),
                              label: const Text('Générer et prévisualiser'),
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            Text(
                              _s.raw('report_last_generated_at').isEmpty
                                  ? 'Aucun rapport généré pour l’instant.'
                                  : 'Dernier rapport : '
                                        '${AkibaDate.short(DateTime.tryParse(_s.raw('report_last_generated_at'))?.toLocal() ?? DateTime.now())}',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _tile(
                        c,
                        tileWidth * (columns > 1 ? 2 : 1) +
                            (columns > 1 ? AkibaSpacing.lg : 0),
                        title: AkibaL10n.tr('data_demo'),
                        icon: Icons.storage_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _switchRow(
                              c,
                              'Mode simulation',
                              'Bandeau permanent, données locales chiffrées',
                              _s.simulationMode,
                              (bool v) async {
                                await _s.setFlag('simulation_mode', v);
                                widget.revision.bump();
                              },
                            ),
                            const Divider(height: AkibaSpacing.xl),
                            Text(
                              'Identité : ${_s.firstName.isEmpty ? 'non renseignée' : _s.firstName} '
                              '${_s.lastName}',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            Text(
                              'Devise : ${_s.currencyLabel} · dates '
                              '${_s.dateStyle} · ${_s.timezone}',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            Text(
                              'Dernière sauvegarde : '
                              '${_s.lastBackupAt.isEmpty ? 'aucune' : AkibaDate.short(DateTime.tryParse(_s.lastBackupAt)?.toLocal() ?? DateTime.now())}',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.md),
                            OutlinedButton.icon(
                              onPressed: widget.onReplayOnboarding,
                              icon: const Icon(Icons.replay_rounded, size: 18),
                              label: const Text('Rejouer l’accueil'),
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            Text(
                              'AKIBA · version 1.0.0 · base chiffrée SQLCipher '
                              'AES-256 · aucune télémétrie',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tile(
    AkibaColors c,
    double width, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(AkibaSpacing.lg),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AkibaRadii.tile),
          boxShadow: c.cardShadow,
        ),
        // Material transparent : les interrupteurs de la tuile peignent leur
        // encre sur ce Material, et non sur celui du Scaffold masqué par le
        // fond de la tuile.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c.iconTile,
                      borderRadius: BorderRadius.circular(AkibaRadii.iconTile),
                    ),
                    child: Icon(icon, size: 18, color: c.terracottaDeep),
                  ),
                  const SizedBox(width: AkibaSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AkibaSpacing.md),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchRow(
    AkibaColors c,
    String title,
    String detail,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: onChanged,
      title: Text(title, style: TextStyle(fontSize: 14, color: c.textPrimary)),
      subtitle: Text(
        detail,
        style: AkibaTypography.legend.copyWith(
          color: c.textMuted,
          fontSize: 11,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _slotRow(
    AkibaColors c, {
    required String key,
    required String timeKey,
    required bool enabled,
    required String time,
    required String title,
    required String detail,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: enabled,
      onChanged: (bool value) async {
        await _s.setFlag(key, value);
        await _reschedule();
      },
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 14, color: c.textPrimary),
            ),
          ),
          TextButton(
            onPressed: () =>
                _pickTime(key: timeKey, current: time, label: title),
            child: Text(time),
          ),
        ],
      ),
      subtitle: Text(
        detail,
        style: AkibaTypography.legend.copyWith(
          color: c.textMuted,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _moduleRow(
    AkibaColors c, {
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AkibaSpacing.sm),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: c.textMuted),
          const SizedBox(width: AkibaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AkibaTypography.legend.copyWith(
                    color: c.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _field(AkibaColors c, String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: c.surfaceElevated,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AkibaSpacing.md,
      vertical: AkibaSpacing.sm,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AkibaRadii.field),
      borderSide: BorderSide.none,
    ),
  );
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.store, required this.requireCurrent});

  final AkibaStore store;
  final bool requireCurrent;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final PinVault vault = PinVault(widget.store);
      if (widget.requireCurrent) {
        final bool ok = await vault.verify(_current.text);
        if (!ok) {
          setState(() => _error = 'Code actuel incorrect.');
          return;
        }
      }
      if (_next.text.length < 4 || _next.text.length > 6) {
        setState(() => _error = 'Le nouveau code doit faire 4 à 6 chiffres.');
        return;
      }
      if (PinVault.isTrivial(_next.text)) {
        setState(() => _error = 'Ce code est trop facile à deviner.');
        return;
      }
      if (_next.text != _confirm.text) {
        setState(() => _error = 'Les deux codes ne correspondent pas.');
        return;
      }
      await vault.setPin(_next.text);
      if (!mounted) return;
      Navigator.of(context).pop(_next.text);
    } catch (error) {
      setState(() => _error = 'Impossible : ${error.runtimeType}.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(
        widget.requireCurrent ? 'Changer le code PIN' : 'Activer un code PIN',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.requireCurrent) _pinField(_current, 'Code actuel'),
            _pinField(_next, 'Nouveau code (4 à 6 chiffres)'),
            _pinField(_confirm, 'Confirmer le nouveau code'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AkibaSpacing.sm),
                child: Text(
                  _error!,
                  style: AkibaTypography.legend.copyWith(color: c.danger),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Valider'),
        ),
      ],
    );
  }

  Widget _pinField(TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AkibaSpacing.sm),
      child: TextField(
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(hintText: hint, counterText: ''),
      ),
    );
  }
}

class _VerifyPinDialog extends StatefulWidget {
  const _VerifyPinDialog({required this.vault});

  final PinVault vault;

  @override
  State<_VerifyPinDialog> createState() => _VerifyPinDialogState();
}

class _VerifyPinDialogState extends State<_VerifyPinDialog> {
  final TextEditingController _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final bool ok = await widget.vault.verify(_pin.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = 'Code incorrect.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return AlertDialog(
      backgroundColor: c.surface,
      title: const Text('Confirmer votre code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _pin,
            obscureText: true,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              hintText: 'Code PIN',
              counterText: '',
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: AkibaTypography.legend.copyWith(color: c.danger),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _check, child: const Text('Confirmer')),
      ],
    );
  }
}
