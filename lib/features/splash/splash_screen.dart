import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/profile/profile_photo.dart';
import '../../core/security/pin_vault.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/profile_avatar.dart';

/// Animation d'ouverture : l'icône AKIBA (cochon agrandi sur fond blanc) puis
/// le **vrai cauri** fourni dans `akiba_spec/` qui glisse vers la fente, sur un
/// fond terre cuite de la palette (jamais blanc).
///
/// Si « Réduire les animations » est actif (réglage AKIBA ou accessibilité du
/// système), l'écran s'affiche sans mouvement.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onFinished});

  final VoidCallback? onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AkibaDurations.splash,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final bool reduced =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) {
      _controller.value = 1;
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (mounted) widget.onFinished?.call();
      });
    } else {
      _controller.forward().whenComplete(() {
        if (mounted) widget.onFinished?.call();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final Color onSplash = c.onTerracotta;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[c.terracotta, c.terracottaDeep],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              final double t = Curves.easeOutCubic.transform(_controller.value);
              final double cauriY = (1 - t) * -58;
              final double cauriOpacity = t < 0.15 ? t / 0.15 : 1.0;
              final double glow = t > 0.65 ? ((t - 0.65) / 0.35) : 0;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: 168,
                    width: 168,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        if (glow > 0)
                          Container(
                            width: 132 + 44 * glow,
                            height: 132 + 44 * glow,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: onSplash.withValues(alpha: 0.12 * glow),
                            ),
                          ),
                        Container(
                          width: 124,
                          height: 124,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 24,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              'assets/brand/app_icon.png',
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (
                                    BuildContext context,
                                    Object error,
                                    StackTrace? s,
                                  ) => Icon(
                                    Icons.savings_rounded,
                                    size: 64,
                                    color: c.terracotta,
                                  ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          child: Opacity(
                            opacity: cauriOpacity.clamp(0, 1),
                            child: Transform.translate(
                              offset: Offset(0, cauriY),
                              child: Image.asset(
                                'assets/brand/cauri.png',
                                width: 38,
                                height: 40,
                                color: onSplash,
                                colorBlendMode: BlendMode.srcIn,
                                errorBuilder:
                                    (
                                      BuildContext context,
                                      Object error,
                                      StackTrace? s,
                                    ) => Icon(
                                      Icons.spa_rounded,
                                      size: 26,
                                      color: onSplash,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.xxl),
                  Text(
                    'AKIBA',
                    style: AkibaTypography.screenTitle.copyWith(
                      fontSize: 26,
                      letterSpacing: 6,
                      color: onSplash,
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.xs),
                  Text(
                    'Votre argent, en clair.',
                    style: AkibaTypography.legend.copyWith(
                      color: onSplash.withValues(alpha: 0.82),
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.xl),
                  SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AkibaRadii.pill),
                      child: LinearProgressIndicator(
                        value: t,
                        minHeight: 3,
                        backgroundColor: onSplash.withValues(alpha: 0.24),
                        valueColor: AlwaysStoppedAnimation<Color>(onSplash),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Affiche [SplashScreen] puis [child].
class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1250),
  });

  final Widget child;
  final Duration duration;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.duration, () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return const SplashScreen();
  }
}

/// Verrouillage PIN / biométrie.
///
/// Le PIN est vérifié par empreinte salée (jamais stocké en clair). La
/// biométrie reste un confort : le PIN est toujours proposé en repli.
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
  final TextEditingController _pin = TextEditingController();
  String? _error;

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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pin.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        widget.pinEnabled &&
        widget.lockOnPause) {
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

  void _submit() {
    final String pin = _pin.text;
    if (pin.length < 4) {
      setState(() => _error = 'Saisissez votre code (4 à 6 chiffres).');
      return;
    }
    if (PinVault.hashPin(pin, widget.pinSalt) == widget.pinHash) {
      setState(() {
        _locked = false;
        _error = null;
        _pin.clear();
      });
    } else {
      HapticFeedback.mediumImpact();
      setState(() => _error = 'Code incorrect.');
      _pin.clear();
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
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: AkibaSpacing.sm),
                    Text(
                      _error!,
                      style: AkibaTypography.legend.copyWith(color: c.danger),
                    ),
                  ],
                  const SizedBox(height: AkibaSpacing.lg),
                  FilledButton(
                    onPressed: _submit,
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
