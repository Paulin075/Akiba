import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/akiba_currency.dart';
import '../../core/profile/profile_photo.dart';
import '../../core/security/pin_attempts.dart';
import '../../core/security/pin_vault.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/cauri_drop.dart';
import '../../core/widgets/profile_avatar.dart';

/// Ouverture : **uniquement** l'animation signature, la tirelire (cochon sans
/// cauri) qui reçoit le cauri dans sa fente. Aucun titre, aucune barre de
/// chargement : 1 s au total, puis l'application prend la main.
///
/// C'est exactement le même widget ([CauriDropAnimation]) que celui utilisé à
/// chaque versement d'épargne : un seul geste, un seul code. Le versement garde
/// ses 3 s ; l'ouverture, elle, ne retarde plus l'accès au verrou PIN.
///
/// Si « Réduire les animations » est actif (réglage AKIBA ou accessibilité du
/// système), l'image finale s'affiche sans mouvement.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _warmed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_warmed) return;
    _warmed = true;
    _warmImages();
  }

  /// Préchauffe le cache d'images : le cauri tombe dès la première image.
  void _warmImages() {
    final List<String> assets = <String>[
      'assets/brand/cochon.png',
      'assets/brand/cauri.png',
      'assets/profile/avatar_default.jpg',
      'assets/logos/flooz.jpg',
      'assets/logos/mixx.png',
      'assets/logos/orabank.png',
      // Logos de devises embarqués : prêts hors ligne, dès l'ouverture.
      for (final AkibaCurrency currency in AkibaCurrency.values)
        currency.assetPath,
    ];
    for (final String asset in assets) {
      precacheImage(AssetImage(asset), context, onError: (_, _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sur un petit écran, le bloc se réduit au lieu de déborder.
    final double size = (MediaQuery.sizeOf(context).shortestSide * 0.52).clamp(
      120.0,
      200.0,
    );

    return Scaffold(
      // Le fond blanc est aussi celui du lancement natif : aucun saut de
      // couleur entre l'écran Android et la première image Flutter.
      backgroundColor: Colors.white,
      body: Center(
        child: Semantics(
          label: 'AKIBA',
          image: true,
          child: ExcludeSemantics(
            child: CauriDropAnimation(
              size: size,
              duration: AkibaDurations.splash,
            ),
          ),
        ),
      ),
    );
  }
}

/// Affiche [SplashScreen] puis [child].
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(AkibaDurations.splash, () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    // `SplashGate` garde la main sur la durée : l'ouverture ne reste jamais
    // bloquée si l'animation est coupée.
    return const SplashScreen();
  }
}

/// Verrouillage PIN / biométrie.
///
/// Le PIN est vérifié par empreinte salée (jamais stocké en clair). La
/// biométrie reste un confort : le PIN est toujours proposé en repli.
///
/// Le verrou suit l'état réel des réglages : dès qu'un PIN est enregistré
/// (`pinEnabled` passe à vrai), l'écran se verrouille, y compris si le réglage
/// vient d'être fait dans le Profil ou pendant l'onboarding.
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.child,
    required this.pinEnabled,
    required this.pinHash,
    required this.pinSalt,
    required this.biometrics,
    required this.biometricPrompt,
    this.lockOnPause = true,
  });

  final Widget child;
  final bool pinEnabled;
  final String pinHash;
  final String pinSalt;
  final bool biometrics;
  final bool lockOnPause;

  /// Retourne vrai si la biométrie a réussi.
  final Future<bool> Function() biometricPrompt;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _triedBiometrics = false;
  bool _checkedLockout = false;
  int _lockSeconds = 0;
  Timer? _ticker;
  final TextEditingController _pin = TextEditingController();
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkedLockout) return;
    _checkedLockout = true;
    _restoreLockout();
  }

  /// Un délai de limitation peut être encore actif après un redémarrage : il
  /// est relu depuis la base chiffrée.
  Future<void> _restoreLockout() async {
    final AkibaSettings? settings = AkibaSettingsScope.maybeOf(context);
    if (settings == null) return;
    final Duration remaining = await PinAttempts(settings.store).remaining();
    if (!mounted || remaining.inSeconds <= 0) return;
    _startCountdown(remaining.inSeconds);
  }

  void _startCountdown(int seconds) {
    _ticker?.cancel();
    if (!mounted) return;
    setState(() {
      _lockSeconds = seconds;
      _error = null;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lockSeconds <= 1) {
        timer.cancel();
        setState(() => _lockSeconds = 0);
      } else {
        setState(() => _lockSeconds -= 1);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = widget.pinEnabled;
    if (widget.pinEnabled && widget.biometrics) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _unlockWithBiometrics(),
      );
    }
  }

  @override
  void didUpdateWidget(covariant LockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Le PIN vient d'être activé (Profil ou onboarding) : on verrouille tout
    // de suite, sans attendre un redémarrage.
    if (widget.pinEnabled && !oldWidget.pinEnabled) {
      _locked = true;
      _error = null;
      _pin.clear();
      _triedBiometrics = false;
      if (widget.biometrics) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _unlockWithBiometrics(),
        );
      }
    } else if (!widget.pinEnabled && _locked) {
      // PIN retiré : l'accès redevient direct.
      _locked = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _pin.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool leaving =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (leaving && widget.pinEnabled && widget.lockOnPause) {
      setState(() {
        _locked = true;
        _triedBiometrics = false;
        _pin.clear();
      });
    }
    if (state == AppLifecycleState.resumed &&
        _locked &&
        widget.biometrics &&
        !_triedBiometrics) {
      _unlockWithBiometrics();
    }
  }

  Future<void> _unlockWithBiometrics() async {
    _triedBiometrics = true;
    bool ok = false;
    try {
      ok = await widget.biometricPrompt();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      setState(() {
        _locked = false;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_lockSeconds > 0) return;
    final String pin = _pin.text;
    if (pin.length < 4) {
      setState(() => _error = 'Saisissez votre code (4 à 6 chiffres).');
      return;
    }
    final AkibaSettings? settings = AkibaSettingsScope.maybeOf(context);
    if (PinVault.hashPin(pin, widget.pinSalt) == widget.pinHash) {
      if (settings != null) await PinAttempts(settings.store).reset();
      if (!mounted) return;
      setState(() {
        _locked = false;
        _error = null;
        _pin.clear();
      });
      return;
    }

    HapticFeedback.mediumImpact();
    _pin.clear();
    if (settings == null) {
      setState(() => _error = 'Code incorrect.');
      return;
    }
    // Délai progressif après trois échecs. Aucun nombre d'essais restants
    // n'est affiché, et aucune donnée n'est effacée.
    final Duration delay = await PinAttempts(settings.store).registerFailure();
    if (!mounted) return;
    if (delay > Duration.zero) {
      _startCountdown(delay.inSeconds);
    } else {
      setState(() => _error = 'Code incorrect.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    final AkibaColors c = AkibaColors.of(context);
    // Photo locale si elle existe, avatar par défaut sinon.
    final ProfilePhotoController? photo = ProfilePhotoScope.maybeOf(context);
    final String name =
        AkibaSettingsScope.maybeOf(context)?.firstName.trim() ?? '';

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AkibaSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: ProfileAvatar(
                      bytes: photo?.bytes,
                      name: name,
                      size: 84,
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 15,
                        color: c.terracotta,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        name.isEmpty ? 'Verrouillé' : 'Bonjour $name',
                        style: AkibaTypography.legend.copyWith(
                          color: c.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AkibaSpacing.xs),
                  Text(
                    'AKIBA est verrouillé',
                    textAlign: TextAlign.center,
                    style: AkibaTypography.screenTitle.copyWith(
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.xs),
                  Text(
                    'Vos montants restent masqués tant que vous n’êtes pas '
                    'déverrouillé.',
                    textAlign: TextAlign.center,
                    style: AkibaTypography.legend.copyWith(color: c.textMuted),
                  ),
                  const SizedBox(height: AkibaSpacing.xl),
                  TextField(
                    controller: _pin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    autofocus: true,
                    maxLength: 6,
                    enabled: _lockSeconds == 0,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Code PIN',
                      counterText: '',
                      filled: true,
                      fillColor: c.surfaceElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AkibaRadii.field),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_lockSeconds > 0 || _error != null) ...<Widget>[
                    const SizedBox(height: AkibaSpacing.sm),
                    Text(
                      _lockSeconds > 0
                          ? 'Trop de tentatives. Nouvel essai dans '
                                '$_lockSeconds s.'
                          : _error!,
                      style: AkibaTypography.legend.copyWith(
                        color: _lockSeconds > 0 ? c.warning : c.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: AkibaSpacing.lg),
                  FilledButton(
                    onPressed: _lockSeconds == 0 ? _submit : null,
                    child: const Text('Déverrouiller'),
                  ),
                  if (widget.biometrics) ...<Widget>[
                    const SizedBox(height: AkibaSpacing.sm),
                    TextButton.icon(
                      onPressed: _unlockWithBiometrics,
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: const Text('Utiliser la biométrie'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
