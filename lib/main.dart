import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqlite3/sqlite3.dart';

import 'core/database/akiba_database.dart';
import 'core/format/akiba_date.dart';
import 'core/notifications/background_reminders.dart';
import 'core/format/akiba_money.dart';
import 'core/profile/profile_photo.dart';
import 'core/state/akiba_data_revision.dart';
import 'core/state/akiba_settings.dart';
import 'core/theme/akiba_theme.dart';
import 'core/widgets/brand_logo.dart';
import 'data/akiba_store.dart';
import 'data/simulation_store.dart';
import 'data/sqlite_akiba_store.dart';
import 'features/onboarding/onboarding_flow.dart';
import 'features/shell/akiba_shell.dart';
import 'features/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AkibaStore store = const EmptyAkibaStore();
  try {
    final Database database = await AkibaDatabase.open();
    final SqliteAkibaStore opened = SqliteAkibaStore(database);
    await opened.ensureDefaultAccounts();
    store = opened;
  } catch (error) {
    // Aucun montant, aucune donnée : uniquement le type de l'erreur.
    debugPrint('AKIBA : base locale indisponible (${error.runtimeType}).');
  }

  final AkibaSettings settings = AkibaSettings(store);
  await settings.load();

  // Contrôle d'intégrité non bloquant : l'interface démarre tout de suite.
  Future<void>(() => AkibaDatabase.integrityCheck());

  // Rappels de repas en arrière-plan (Workmanager, Android uniquement).
  await BackgroundReminders.ensureScheduled(settings);

  // Logos et avatar décodés une fois : aucun scintillement à l'ouverture.
  BrandImages.warmUp();

  // Photo locale chargée avant la première image : pas de clignotement.
  final ProfilePhotoController photo = ProfilePhotoController(
    ProfilePhotoStore(),
  );
  await photo.load();

  runApp(AkibaApp(store: store, settings: settings, photo: photo));
}

/// Racine AKIBA : thème clair par défaut, onboarding E1→E11 au premier
/// démarrage, verrouillage PIN/biométrie et réglages partagés.
class AkibaApp extends StatefulWidget {
  const AkibaApp({
    super.key,
    this.store = const EmptyAkibaStore(),
    this.settings,
    this.photo,
  });

  final AkibaStore store;
  final AkibaSettings? settings;
  final ProfilePhotoController? photo;

  @override
  State<AkibaApp> createState() => _AkibaAppState();
}

class _AkibaAppState extends State<AkibaApp> with WidgetsBindingObserver {
  late final AkibaSettings _settings =
      widget.settings ?? AkibaSettings(widget.store);
  late final ProfilePhotoController _photo =
      widget.photo ?? ProfilePhotoController(ProfilePhotoStore());
  final AkibaDataRevision _revision = AkibaDataRevision();

  /// Magasin fictif isolé : le mode simulation ne touche jamais la base réelle.
  final SimulationAkibaStore _simulation = SimulationAkibaStore();

  AkibaStore get _store =>
      _settings.simulationMode ? _simulation : widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Fermeture propre : checkpoint WAL puis close, sans bloquer l'UI.
    if (state == AppLifecycleState.detached) AkibaDatabase.close();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revision.dispose();
    super.dispose();
  }

  void _applyFormats() {
    AkibaMoney.currency = _settings.currencyLabel;
    AkibaDate.isoStyle = _settings.dateStyle == 'aaaa-mm-jj';
  }

  /// Vrai si la biométrie a réussi. Toute erreur (poste sans capteur,
  /// greffon indisponible) renvoie faux et laisse le PIN faire foi.
  Future<bool> _biometricPrompt() async {
    try {
      final LocalAuthentication auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return false;
      return await auth.authenticate(localizedReason: 'Déverrouiller AKIBA');
    } catch (_) {
      return false;
    }
  }

  void _replayOnboarding() {
    _settings.setOnboardingDone(false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (BuildContext context, Widget? _) {
        _applyFormats();
        return MaterialApp(
          title: 'AKIBA',
          debugShowCheckedModeBanner: false,
          // Le thème choisi porte sa propre palette : plus besoin de
          // `darkTheme` ni de `themeMode`, aucun thème système ne s'y
          // superpose.
          theme: AkibaTheme.forId(_settings.themeId),
          builder: (BuildContext context, Widget? child) {
            final MediaQueryData media = MediaQuery.of(context);
            final bool reduced =
                _settings.reduceAnimations || media.disableAnimations;
            return AkibaSettingsScope(
              settings: _settings,
              child: ProfilePhotoScope(
                photo: _photo,
                child: MediaQuery(
                  data: media.copyWith(
                    disableAnimations: reduced,
                    textScaler: media.textScaler.clamp(maxScaleFactor: 2),
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
          home: SplashGate(
            // Transition fluide entre l'onboarding et l'accueil : le logo
            // termine son animation, puis la coquille apparaît en fondu.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _settings.onboardingDone
                  ? LockGate(
                      key: const ValueKey<String>('akiba-shell'),
                      pinEnabled: _settings.pinEnabled,
                      pinHash: _settings.pinHash,
                      pinSalt: _settings.pinSalt,
                      biometrics: _settings.biometrics,
                      lockOnPause: _settings.lockOnResume,
                      biometricPrompt: _biometricPrompt,
                      child: AkibaShell(
                        store: _store,
                        settings: _settings,
                        onReplayOnboarding: _replayOnboarding,
                      ),
                    )
                  : OnboardingFlow(
                      key: const ValueKey<String>('akiba-onboarding'),
                      store: _store,
                      settings: _settings,
                      revision: _revision,
                      onFinished: () {
                        if (_settings.onboardingDone) _revision.bump();
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}
