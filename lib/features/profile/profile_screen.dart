import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/format/akiba_currency.dart';
import '../../core/format/akiba_date.dart';
import '../../core/profile/avatar_editor.dart';
import '../../core/notifications/local_notifications.dart';
import '../../core/notifications/reminder_planner.dart';
import '../../core/profile/profile_photo.dart';
import '../../core/security/pin_vault.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/state/masked_amounts.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_theme.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/currency_logo.dart';
import '../../core/widgets/icon_circle_button.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../core/widgets/theme_swatch.dart';
import '../../data/akiba_store.dart';
import '../assistant/ai_settings_sheet.dart';
import '../assistant/assistant_sheet.dart';
import '../backup/backup_center.dart';
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
  });

  final AkibaStore store;
  final AkibaSettings settings;
  final AkibaDataRevision revision;
  final VoidCallback onReplayOnboarding;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _notifStatus = '';

  AkibaSettings get _s => widget.settings;

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
      await PinVault(widget.store).clear(widget.store);
      await _s.setFlag('biometrics', false);
      await _s.load();
      _toast('Code PIN retiré.');
      return;
    }

    final bool configured = _s.pinEnabled;
    final String? newPin = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _PinDialog(store: widget.store, requireCurrent: configured),
    );
    if (newPin == null) return;
    await _s.load();
    _toast('Code PIN activé.');
  }

  Future<bool> _askPin() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) =>
          _VerifyPinDialog(vault: PinVault(widget.store)),
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

  ReminderConfig _reminderConfig() => ReminderConfig(
    morningEnabled: _s.morningEnabled,
    noonEnabled: _s.noonEnabled,
    eveningEnabled: _s.eveningEnabled,
    morningTime: _s.morningTime,
    noonTime: _s.noonTime,
    eveningTime: _s.eveningTime,
    dndEnabled: _s.dndEnabled,
    dndStart: _s.dndStart,
    dndEnd: _s.dndEnd,
    festiveEnabled: _s.festiveEnabled,
    festiveLabel: _s.festiveLabel,
    masked: MaskedAmounts.of(context),
  );

  Future<void> _reschedule() async {
    final ReminderConfig config = _reminderConfig();
    if (!config.morningEnabled &&
        !config.noonEnabled &&
        !config.eveningEnabled) {
      await LocalNotifications.cancelAll();
      setState(() => _notifStatus = 'Tous les rappels sont désactivés.');
      return;
    }

    final List<ReminderPlan> plans = ReminderPlanner.plan(
      config,
      now: DateTime.now(),
      horizonDays: 7,
    );
    if (!LocalNotifications.supported) {
      setState(() {
        _notifStatus =
            '${plans.length} rappels prêts pour 7 jours. La livraison système '
            'Windows n’est pas encore prise en charge : les messages '
            's’affichent dans AKIBA.';
      });
      return;
    }

    final bool permission = await LocalNotifications.requestPermission();
    final int scheduled = permission
        ? await LocalNotifications.schedule(plans)
        : 0;
    if (!mounted) return;
    setState(() {
      _notifStatus = scheduled > 0
          ? '$scheduled rappels planifiés sur 7 jours, sans aucun montant.'
          : 'Autorisation de notification refusée ou planification indisponible.';
    });
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

  Future<void> _openSms() async {
    await openSmsReview(
      context,
      store: widget.store,
      revision: widget.revision,
      masked: MaskedAmounts.of(context),
    );
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

  // -------------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final bool masked = MaskedAmounts.of(context);
    final String name = _s.firstName.isEmpty ? 'Votre profil' : _s.firstName;
    final ProfilePhotoController? photo = ProfilePhotoScope.maybeOf(context);

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
                              'PROFIL',
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
                                        ? 'Changer la photo'
                                        : 'Ajouter une photo',
                                  ),
                                ),
                                if (photo?.hasPhoto ?? false)
                                  TextButton(
                                    onPressed: _removePhoto,
                                    child: const Text('Retirer'),
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
                            ? 'Afficher les montants'
                            : 'Masquer les montants',
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
                        title: 'Sécurité',
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
                        title: 'Confidentialité',
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
                        title: 'Apparence',
                        icon: Icons.palette_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              'Thème',
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
                              'L’aperçu est immédiat : palettes à contraste '
                              'élevé, logos officiels intacts, barre basse '
                              'ancrée et boutons latéraux identiques dans '
                              'les cinq thèmes.',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            _switchRow(
                              c,
                              'Réduire les animations',
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
                        title: 'Préférences',
                        icon: Icons.tune_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              'Devise',
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
                              'Seul l’affichage change : aucun taux de change '
                              'n’est appliqué aux montants.',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.sm),
                            DropdownButtonFormField<String>(
                              initialValue: _s.dateStyle,
                              isDense: true,
                              decoration: _field(c, 'Dates'),
                              items: const <DropdownMenuItem<String>>[
                                DropdownMenuItem<String>(
                                  value: 'jj/mm/aaaa',
                                  child: Text('Dates : 19/11/2026'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'aaaa-mm-jj',
                                  child: Text('Dates : 2026-11-19'),
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
                              decoration: _field(c, 'Fuseau'),
                              items: const <DropdownMenuItem<String>>[
                                DropdownMenuItem<String>(
                                  value: 'Africa/Lome',
                                  child: Text('Africa/Lome'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'Africa/Cotonou',
                                  child: Text('Africa/Cotonou'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'Africa/Abidjan',
                                  child: Text('Africa/Abidjan'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'Africa/Dakar',
                                  child: Text('Africa/Dakar'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'Europe/Paris',
                                  child: Text('Europe/Paris'),
                                ),
                              ],
                              onChanged: (String? value) {
                                if (value != null) _s.set('timezone', value);
                              },
                            ),
                            const SizedBox(height: AkibaSpacing.xs),
                            Text(
                              'Le fuseau sert aux rappels ; les dates restent '
                              'celles de l’appareil.',
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
                        title: 'Rappels quotidiens',
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
                        title: 'Assistant IA',
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
                        title: 'SMS financiers',
                        icon: Icons.sms_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              'Flooz, Mixx by Yas, Orabank : chaque SMS est relu '
                              'et peut être isolé comme argent de tiers.',
                              style: AkibaTypography.legend.copyWith(
                                color: c.textMuted,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: AkibaSpacing.md),
                            OutlinedButton.icon(
                              onPressed: _openSms,
                              icon: const Icon(
                                Icons.fact_check_outlined,
                                size: 18,
                              ),
                              label: const Text('Relire des SMS'),
                            ),
                          ],
                        ),
                      ),
                      _tile(
                        c,
                        tileWidth,
                        title: 'Sauvegarde & synchronisation',
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
                          ],
                        ),
                      ),
                      _tile(
                        c,
                        tileWidth * (columns > 1 ? 2 : 1) +
                            (columns > 1 ? AkibaSpacing.lg : 0),
                        title: 'Données & démonstration',
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
