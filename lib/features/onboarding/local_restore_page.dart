import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backup/backup_code.dart';
import '../../core/backup/backup_service.dart';
import '../../core/backup/google_account.dart';
import '../../core/backup/google_drive_backup.dart';
import '../../core/backup/home_lab_setup.dart';
import '../../core/format/akiba_date.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/akiba_surface_card.dart';
import '../../data/akiba_store.dart';

/// Télécharge l'enveloppe de sauvegarde du serveur local.
typedef LocalBackupFetcher =
    Future<Map<String, dynamic>?> Function(String url, String token);

/// Restaure une enveloppe déjà téléchargée.
typedef LocalBackupRestorer =
    Future<Map<String, int>> Function(Map<String, dynamic> envelope);

/// Page dédiée de l'onboarding : connexion au serveur de sauvegarde local
/// (Home Lab) avec l'adresse et le jeton, puis restauration automatique.
///
/// Aucune saisie de phrase secrète : les sauvegardes AKIBA sont chiffrées
/// AES-256-GCM. L'adresse est normalisée (`192.168.1.20:8080` devient
/// `http://192.168.1.20:8080`) avant tout appel réseau.
class LocalRestorePage extends StatefulWidget {
  const LocalRestorePage({
    super.key,
    required this.store,
    required this.settings,
    required this.onRestored,
    this.tokens,
    this.backup,
    this.fetcher,
    this.restorer,
  });

  final AkibaStore store;
  final AkibaSettings settings;
  final VoidCallback onRestored;
  final LabTokenStore? tokens;
  final BackupService? backup;
  final LocalBackupFetcher? fetcher;
  final LocalBackupRestorer? restorer;

  @override
  State<LocalRestorePage> createState() => _LocalRestorePageState();
}

class _LocalRestorePageState extends State<LocalRestorePage> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _token = TextEditingController();

  /// Code à 4 chiffres choisi lors de la configuration de la sauvegarde :
  /// c'est la seule preuve demandée pour rouvrir les données du serveur.
  final TextEditingController _code = TextEditingController();

  bool _busy = false;
  bool _restored = false;
  bool _error = false;
  String? _status;

  LabTokenStore get _vault => widget.tokens ?? const SecureLabTokenStore();

  BackupService get _service => widget.backup ?? BackupService(widget.store);

  @override
  void initState() {
    super.initState();
    _url.text = widget.settings.labUrl;
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _fetch(String url, String token) {
    final LocalBackupFetcher? injected = widget.fetcher;
    if (injected != null) return injected(url, token);
    return _service.fetchRemote(url: url, token: token);
  }

  Future<Map<String, int>> _restore(Map<String, dynamic> envelope) async {
    final LocalBackupRestorer? injected = widget.restorer;
    if (injected != null) return injected(envelope);
    // Une sauvegarde déposée sur le serveur local peut avoir été créée avec
    // un compte Google (clé dérivée) : on transmet l'identité connue hors
    // ligne, sans exiger de connexion.
    final GoogleAccount account = await GoogleDriveService().currentAccount();
    return _service.restore(
      envelope,
      account: account,
      code: normalizeBackupCode(_code.text),
    );
  }

  /// Cherche la sauvegarde la plus récente, puis la restaure **sans seconde
  /// confirmation** dès qu'une enveloppe valide est trouvée.
  Future<void> _searchAndRestore() async {
    if (_busy) return;
    final String? normalized = BackupService.normalizeUrl(_url.text);
    if (normalized == null) {
      setState(() {
        _error = true;
        _status =
            'Adresse invalide : utilisez une IP ou un nom, par exemple '
            '192.168.1.20:8080.';
      });
      return;
    }
    final String token = _token.text.trim();
    if (token.isEmpty) {
      setState(() {
        _error = true;
        _status = 'Saisissez le jeton d’accès fourni par le serveur.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = false;
      _status = 'Recherche de la sauvegarde sur le serveur…';
    });

    try {
      final Map<String, dynamic>? envelope = await _fetch(normalized, token);
      if (!mounted) return;
      if (envelope == null) {
        setState(() {
          _busy = false;
          _status =
              'Aucune sauvegarde AKIBA trouvée sur ce serveur pour '
              'ce jeton. Vous pouvez continuer : la première '
              'sauvegarde sera créée plus tard.';
        });
        return;
      }

      // Enveloppe du serveur (version 4) : sans le code à 4 chiffres, elle ne
      // peut pas être rouverte. On le dit avant de lancer le déchiffrement.
      final bool needsCode = '${envelope['kdf']}' == 'PBKDF2-CODE';
      if (needsCode && !isValidBackupCode(_code.text)) {
        setState(() {
          _busy = false;
          _error = true;
          _status =
              'Cette sauvegarde est protégée par un code à 4 chiffres. '
              'Saisissez-le dans « Code de sauvegarde » pour la restaurer.';
        });
        return;
      }

      final BackupMetadata meta = BackupService.metadata(envelope);
      if (mounted) {
        setState(() {
          _status =
              'Sauvegarde du ${AkibaDate.short(meta.createdAt)} trouvée '
              '(${meta.transactions} mouvements). Restauration en cours…';
        });
      }

      final Map<String, int> restored = await _restore(envelope);
      if (!mounted) return;
      // Configuration conservée pour les sauvegardes suivantes : adresse,
      // jeton et code dans le coffre système, sauvegarde automatique armée.
      await _remember(normalized, token);
      await widget.settings.setFlag('restore_done', true);
      widget.onRestored();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _restored = true;
        _error = false;
        _status =
            'Restauration terminée : ${restored['transactions'] ?? 0} '
            'mouvements et ${restored['accounts'] ?? 0} comptes ajoutés. '
            'Aucune donnée locale n’a été supprimée.';
      });
    } on BackupException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = true;
          _status = error.message;
        });
      }
    } on GoogleAuthException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = true;
          _status = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = true;
          _status =
              'Serveur injoignable ou sauvegarde illisible. Vérifiez '
              'l’adresse, le Wi-Fi et le jeton, puis réessayez.';
        });
      }
    }
  }

  Future<void> _remember(String url, String token) async {
    try {
      await _vault.write(token);
      final String code = normalizeBackupCode(_code.text);
      if (isValidBackupCode(code)) {
        await const SecureBackupCodeStore().write(code);
      }
      await widget.settings.set('lab_url', url);
      await widget.settings.setFlag('lab_auto_backup', true);
    } catch (_) {
      // La restauration a réussi : un coffre indisponible ne l'annule pas.
    }
  }

  void _leaveWithoutRestore() => Navigator.of(context).pop(false);

  void _continue() => Navigator.of(context).pop(_restored);

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Serveur de sauvegarde'),
        leading: IconButton(
          tooltip: 'Retour',
          onPressed: _busy ? null : _leaveWithoutRestore,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AkibaSpacing.screen,
              AkibaSpacing.lg,
              AkibaSpacing.screen,
              AkibaSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Restaurer depuis mon serveur',
                    style: AkibaTypography.screenTitle.copyWith(
                      fontSize: 26,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.sm),
                  Text(
                    'Sans compte Google, connectez le serveur de sauvegarde '
                    'de votre Wi-Fi. Saisissez son adresse ou son IP, son jeton '
                    'd’accès, puis le code à 4 chiffres choisi lors de la '
                    'configuration de la sauvegarde. Si le jeton est partagé, '
                    'ajoutez votre nom après « : » (exemple 9f2c8a…:mamadou) : '
                    'vos sauvegardes restent dans votre propre dossier. AKIBA '
                    'cherche la sauvegarde la plus récente et la restaure '
                    'automatiquement. Rien n’est supprimé sur cet appareil.',
                    style: AkibaTypography.body.copyWith(
                      color: c.textMuted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.xl),
                  AkibaSurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        TextField(
                          controller: _url,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: _decoration(
                            c,
                            'Adresse ou IP du serveur',
                            hint: '192.168.1.20:8080',
                          ),
                        ),
                        const SizedBox(height: AkibaSpacing.md),
                        TextField(
                          controller: _token,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _searchAndRestore(),
                          decoration: _decoration(
                            c,
                            'Jeton d’accès',
                            hint: 'Jeton, ou jeton:mon_nom',
                          ),
                        ),
                        const SizedBox(height: AkibaSpacing.md),
                        TextField(
                          controller: _code,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _searchAndRestore(),
                          decoration: _decoration(
                            c,
                            'Code de sauvegarde',
                            hint: '4 chiffres choisis à la configuration',
                          ),
                        ),
                        const SizedBox(height: AkibaSpacing.lg),
                        FilledButton.icon(
                          onPressed: _busy ? null : _searchAndRestore,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_download_rounded),
                          label: Text(
                            _restored
                                ? 'Rechercher à nouveau'
                                : 'Rechercher et restaurer',
                          ),
                        ),
                        if (_busy) ...<Widget>[
                          const SizedBox(height: AkibaSpacing.sm),
                          const LinearProgressIndicator(minHeight: 2),
                        ],
                      ],
                    ),
                  ),
                  if (_status != null) ...<Widget>[
                    const SizedBox(height: AkibaSpacing.md),
                    Text(
                      _status!,
                      style: AkibaTypography.legend.copyWith(
                        color: _error ? c.danger : c.textMuted,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: AkibaSpacing.lg),
                  Wrap(
                    spacing: AkibaSpacing.sm,
                    runSpacing: AkibaSpacing.sm,
                    children: <Widget>[
                      if (_restored)
                        FilledButton.icon(
                          onPressed: _continue,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Continuer'),
                        )
                      else
                        TextButton(
                          onPressed: _busy ? null : _leaveWithoutRestore,
                          child: const Text('Continuer sans restaurer'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(AkibaColors c, String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: c.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AkibaRadii.field),
        borderSide: BorderSide.none,
      ),
    );
  }
}
