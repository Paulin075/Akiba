import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backup/backup_progress.dart';
import '../../core/backup/backup_service.dart';
import '../../core/backup/google_drive_backup.dart';
import '../../core/config/google_oauth_config.dart';
import '../../core/format/akiba_date.dart';
import '../../core/state/akiba_data_revision.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/segmented_control.dart';
import '../../data/akiba_store.dart';

/// Centre de sauvegarde : Google Drive et Home Lab.
///
/// Le chiffrement est automatique (**AES-256-GCM** avec la clé de l'appareil) :
/// plus aucune phrase secrète à retenir. Chaque sauvegarde et chaque
/// restauration affiche les étapes réelles du chiffrement puis du transfert.
Future<void> openBackupCenter(
  BuildContext context, {
  required AkibaStore store,
  required AkibaSettings settings,
  required AkibaDataRevision revision,
  required bool masked,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => _BackupSheet(
      store: store,
      settings: settings,
      revision: revision,
      masked: masked,
    ),
  );
}

class _BackupSheet extends StatefulWidget {
  const _BackupSheet({
    required this.store,
    required this.settings,
    required this.revision,
    required this.masked,
  });

  final AkibaStore store;
  final AkibaSettings settings;
  final AkibaDataRevision revision;
  final bool masked;

  @override
  State<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<_BackupSheet> {
  late final TextEditingController _folder = TextEditingController(
    text: widget.settings.driveFolder,
  );
  late final TextEditingController _labUrl = TextEditingController(
    text: widget.settings.labUrl,
  );
  late final TextEditingController _labToken = TextEditingController(
    text: widget.settings.labToken,
  );

  int _target = 0;
  bool _busy = false;
  bool _restoring = false;
  String? _status;
  bool _isError = false;
  final ValueNotifier<BackupStage> _stage = ValueNotifier<BackupStage>(
    BackupStage.idle,
  );

  final GoogleDriveService _google = GoogleDriveService();
  String? _googleEmail;

  BackupService get _service => BackupService(widget.store);

  /// Vrai quand la sauvegarde Drive passe par l'API (compte lié).
  bool get _driveApi => _googleEmail != null;

  @override
  void initState() {
    super.initState();
    _loadGoogleLink();
  }

  Future<void> _loadGoogleLink() async {
    final String? email = await _google.linkedEmail();
    if (!mounted) return;
    setState(() => _googleEmail = email);
  }

  @override
  void dispose() {
    _folder.dispose();
    _labUrl.dispose();
    _labToken.dispose();
    _stage.dispose();
    super.dispose();
  }

  String get _targetKey => _target == 0 ? 'googleDrive' : 'homeLab';

  String get _targetLabel => _target == 0 ? 'Google Drive' : 'Home Lab Backup';

  void _show(String message, {bool error = false}) {
    setState(() {
      _status = message;
      _isError = error;
    });
  }

  Future<void> _connectGoogle() async {
    setState(() => _busy = true);
    try {
      final GoogleSession session = await _google.signIn();
      await widget.settings.setFlag('google_linked', true);
      if (!mounted) return;
      setState(() {
        _googleEmail = session.email.isEmpty ? 'compte Google' : session.email;
      });
      _show(
        'Compte Google connecté : sauvegarde chiffrée dans l’espace '
        'applicatif du Drive.',
      );
    } on GoogleAuthException catch (error) {
      _show(error.message, error: true);
    } catch (error) {
      _show('Connexion Google impossible (${error.runtimeType}).', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectGoogle() async {
    await _google.signOut();
    await widget.settings.setFlag('google_linked', false);
    if (!mounted) return;
    setState(() => _googleEmail = null);
    _show('Compte Google déconnecté. AKIBA reste utilisable hors ligne.');
  }

  Future<void> _persistTargetSettings() async {
    await widget.settings.set('backup_drive_folder', _folder.text.trim());
    await widget.settings.set('lab_url', _labUrl.text.trim());
    await widget.settings.set('lab_token', _labToken.text.trim());
  }

  Future<DateTime?> _localLastMutation() async {
    try {
      final List<dynamic> rows = await widget.store.transactions(limit: 1);
      if (rows.isEmpty) return null;
      return rows.first.createdAt as DateTime;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchRemote() async {
    if (_target == 0) {
      if (_driveApi) return _google.download();
      return _service.readFolder(
        _folder.text,
        onStage: (BackupStage stage) => _stage.value = stage,
      );
    }
    return _service.fetchRemote(
      url: _labUrl.text.trim(),
      token: _labToken.text,
      onStage: (BackupStage stage) => _stage.value = stage,
    );
  }

  Future<bool> _confirmOverwrite(BackupMetadata remote) async {
    final AkibaColors c = AkibaColors.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Conflit de sauvegarde'),
        content: Text(
          'La sauvegarde distante (${AkibaDate.short(remote.createdAt)} '
          '${AkibaDate.time(remote.createdAt)}) contient des mouvements plus '
          'récents que cet appareil. Écraser la version distante ?',
          style: AkibaTypography.body.copyWith(color: c.textMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Écraser'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _backup() async {
    setState(() {
      _busy = true;
      _restoring = false;
      _status = null;
    });
    _stage.value = BackupStage.preparing;
    try {
      await _persistTargetSettings();
      final Map<String, dynamic>? remote = await _fetchRemote();
      if (remote != null) {
        final BackupMetadata meta = BackupService.metadata(remote);
        final DateTime? local = await _localLastMutation();
        if (meta.isNewerThan(local) && !await _confirmOverwrite(meta)) {
          _show('Sauvegarde annulée : la version distante est conservée.');
          return;
        }
      }

      _stage.value = BackupStage.preparing;
      final Map<String, dynamic> envelope = await _service.createEnvelope(
        deviceId: 'akiba-${widget.settings.timezone}',
        onStage: (BackupStage stage) => _stage.value = stage,
      );

      String location;
      if (_target == 0) {
        if (_driveApi) {
          _stage.value = BackupStage.uploading;
          final DateTime stamp = await _google.upload(envelope);
          location =
              'Google Drive · ${AkibaDate.short(stamp.toLocal())} '
              '(espace applicatif) · 5 dernières conservées';
        } else {
          final dynamic file = await _service.saveToFolder(
            envelope,
            _folder.text,
            onStage: (BackupStage stage) => _stage.value = stage,
          );
          location = file.path as String;
        }
      } else {
        location = await _service.putRemote(
          url: _labUrl.text.trim(),
          token: _labToken.text,
          envelope: envelope,
          onStage: (BackupStage stage) => _stage.value = stage,
        );
      }

      final DateTime now = DateTime.now();
      await widget.settings.set(
        'last_backup_at',
        now.toUtc().toIso8601String(),
      );
      await widget.settings.set('last_backup_target', _targetKey);
      _stage.value = BackupStage.done;
      HapticFeedback.lightImpact();
      _show('Sauvegarde chiffrée créée : $location');
    } on BackupException catch (error) {
      _show(error.message, error: true);
    } on GoogleAuthException catch (error) {
      _show(error.message, error: true);
    } catch (error) {
      _show('Sauvegarde impossible (${error.runtimeType}).', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inspect() async {
    setState(() => _busy = true);
    try {
      final Map<String, dynamic>? remote = await _fetchRemote();
      if (remote == null) {
        _show('Aucune sauvegarde trouvée pour $_targetLabel.');
        return;
      }
      final BackupMetadata meta = BackupService.metadata(remote);
      final DateTime? local = await _localLastMutation();
      final String conflict = meta.isNewerThan(local)
          ? ' · plus récente que cet appareil'
          : '';
      _show(
        'Dernière sauvegarde : ${AkibaDate.short(meta.createdAt)} '
        '${AkibaDate.time(meta.createdAt)} · ${meta.transactions} mouvements'
        '$conflict.',
      );
    } on BackupException catch (error) {
      _show(error.message, error: true);
    } on GoogleAuthException catch (error) {
      _show(error.message, error: true);
    } catch (error) {
      _show('Lecture impossible (${error.runtimeType}).', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _restoring = true;
      _status = null;
    });
    try {
      final Map<String, dynamic>? remote = await _fetchRemote();
      if (remote == null) {
        _show('Aucune sauvegarde à restaurer.');
        return;
      }
      if (!mounted) return;
      final BackupMetadata meta = BackupService.metadata(remote);
      final AkibaColors c = AkibaColors.of(context);
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          backgroundColor: c.surface,
          title: const Text('Restaurer cette sauvegarde ?'),
          content: Text(
            '${AkibaDate.short(meta.createdAt)} · ${meta.accounts} comptes · '
            '${meta.transactions} mouvements. Les éléments déjà présents ne '
            'sont pas dupliqués ; rien n’est supprimé.',
            style: AkibaTypography.body.copyWith(color: c.textMuted),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Restaurer'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      _stage.value = BackupStage.decrypting;
      final Map<String, int> restored = await _service.restore(
        remote,
        onStage: (BackupStage stage) => _stage.value = stage,
      );
      widget.revision.bump();
      await widget.settings.load();
      _stage.value = BackupStage.done;
      _show(
        'Restauration terminée : ${restored['transactions']} mouvements et '
        '${restored['accounts']} comptes ajoutés.',
      );
    } on BackupException catch (error) {
      _show(error.message, error: true);
    } on GoogleAuthException catch (error) {
      _show(error.message, error: true);
    } catch (error) {
      _show('Restauration impossible (${error.runtimeType}).', error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _restoring = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final String last = widget.settings.lastBackupAt;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.94,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AkibaRadii.card),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AkibaSpacing.screen,
              AkibaSpacing.lg,
              AkibaSpacing.screen,
              AkibaSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'SAUVEGARDE CHIFFRÉE',
                                style: AkibaTypography.label.copyWith(
                                  color: c.textMuted,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              Text(
                                'AES-256-GCM · sans phrase secrète',
                                style: AkibaTypography.sectionTitle.copyWith(
                                  fontSize: 18,
                                  color: c.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fermer',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    if (last.isNotEmpty)
                      Text(
                        'Dernière sauvegarde : '
                        '${AkibaDate.short(DateTime.tryParse(last)?.toLocal() ?? DateTime.now())} '
                        '${widget.settings.lastBackupTarget}',
                        style: AkibaTypography.legend.copyWith(
                          color: c.textMuted,
                        ),
                      ),
                    const SizedBox(height: AkibaSpacing.md),
                    SegmentedControl(
                      segments: const <String>['Google Drive', 'Home Lab'],
                      selectedIndex: _target,
                      onChanged: (int index) => setState(() {
                        _target = index;
                        _status = null;
                      }),
                    ),
                    const SizedBox(height: AkibaSpacing.lg),
                    if (_target == 0) ...<Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            _driveApi
                                ? Icons.verified_user_rounded
                                : Icons.link_off_rounded,
                            size: 18,
                            color: _driveApi ? c.success : c.textMuted,
                          ),
                          const SizedBox(width: AkibaSpacing.sm),
                          Expanded(
                            child: Text(
                              _driveApi
                                  ? 'Compte Google lié : $_googleEmail'
                                  : GoogleOAuthConfig.isConfigured
                                  ? 'Identifiants OAuth prêts, compte non lié'
                                  : 'Se connecter avec Google (identifiants à '
                                        'ajouter)',
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
                      if (!GoogleOAuthConfig.isConfigured)
                        Text(
                          'Collez votre identifiant OAuth dans '
                          'secrets/google_oauth.json puis relancez AKIBA avec '
                          '--dart-define-from-file. En attendant, la sauvegarde '
                          'fonctionne dans le dossier Drive synchronisé de '
                          'l’appareil, sans connexion Google.',
                          style: AkibaTypography.legend.copyWith(
                            color: c.textMuted,
                            height: 1.45,
                          ),
                        ),
                      if (GoogleOAuthConfig.isConfigured && !_driveApi)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _connectGoogle,
                            icon: const Icon(Icons.login_rounded, size: 18),
                            label: const Text('Se connecter avec Google'),
                          ),
                        ),
                      if (_driveApi)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _busy ? null : _disconnectGoogle,
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Se déconnecter'),
                          ),
                        ),
                      const SizedBox(height: AkibaSpacing.sm),
                      TextField(
                        controller: _folder,
                        decoration: _field(
                          c,
                          'Dossier Google Drive synchronisé (ex. G:\\My Drive\\AKIBA)',
                        ),
                      ),
                      const SizedBox(height: AkibaSpacing.sm),
                      Text(
                        _driveApi
                            ? 'La sauvegarde part chiffrée AES-256-GCM dans '
                                  'l’espace applicatif du Drive (invisible dans '
                                  '« Mon Drive »). Google ne voit que du '
                                  'chiffré ; les cinq dernières sauvegardes '
                                  'sont conservées.'
                            : 'Sans connexion Google, AKIBA écrit un fichier '
                                  '.akiba chiffré dans le dossier Drive '
                                  'synchronisé de l’appareil.',
                        style: AkibaTypography.legend.copyWith(
                          color: c.textMuted,
                          height: 1.45,
                        ),
                      ),
                    ] else ...<Widget>[
                      TextField(
                        controller: _labUrl,
                        decoration: _field(
                          c,
                          'URL Home Lab (https://192.168.x.x:8080/akiba/backup)',
                        ),
                      ),
                      const SizedBox(height: AkibaSpacing.sm),
                      TextField(
                        controller: _labToken,
                        obscureText: true,
                        decoration: _field(c, 'Jeton d’accès (facultatif)'),
                      ),
                      const SizedBox(height: AkibaSpacing.sm),
                      Text(
                        'Home Lab seulement : même Wi-Fi, sans VPN. Le jeton '
                        'est envoyé en en-tête Bearer et jamais dans l’URL. '
                        'Android refuse le HTTP en clair : utilisez HTTPS ou un '
                        'certificat local. « Vérifier » lit la sauvegarde sans '
                        'rien écrire.',
                        style: AkibaTypography.legend.copyWith(
                          color: c.textMuted,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: AkibaSpacing.lg),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.lock_rounded, size: 16, color: c.terracotta),
                        const SizedBox(width: AkibaSpacing.sm),
                        Expanded(
                          child: Text(
                            'Chiffrement automatique AES-256-GCM avec la clé '
                            'de cet appareil (coffre du système). Aucune phrase '
                            'secrète à retenir, aucun montant en clair dans le '
                            'fichier envoyé.',
                            style: AkibaTypography.legend.copyWith(
                              color: c.textMuted,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AkibaSpacing.lg),
                    Wrap(
                      spacing: AkibaSpacing.sm,
                      runSpacing: AkibaSpacing.sm,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: _busy ? null : _backup,
                          icon: const Icon(
                            Icons.cloud_upload_rounded,
                            size: 18,
                          ),
                          label: const Text('Sauvegarder'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _inspect,
                          icon: const Icon(Icons.search_rounded, size: 18),
                          label: const Text('Vérifier'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _restore,
                          icon: const Icon(Icons.restore_rounded, size: 18),
                          label: const Text('Restaurer'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AkibaSpacing.md),
                    BackupProgress(
                      stage: _stage,
                      active: _busy,
                      restoring: _restoring,
                    ),
                    if (_status != null) ...<Widget>[
                      const SizedBox(height: AkibaSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            _isError
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 18,
                            color: _isError ? c.danger : c.success,
                          ),
                          const SizedBox(width: AkibaSpacing.sm),
                          Expanded(
                            child: Text(
                              _status!,
                              style: AkibaTypography.legend.copyWith(
                                color: _isError ? c.danger : c.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
