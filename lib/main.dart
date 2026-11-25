import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqlite3/sqlite3.dart';

import 'core/backup/home_lab_setup.dart';
import 'core/config/google_oauth_config.dart';
import 'core/database/akiba_database.dart';
import 'core/format/akiba_date.dart';
import 'core/notifications/reminder_scheduler.dart';
import 'core/format/akiba_money.dart';
import 'core/profile/profile_photo.dart';
import 'core/state/akiba_data_revision.dart';
import 'core/state/akiba_l10n.dart';
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

  // Identifiants Google OAuth chargés avant l'interface. Sur ordinateur,
  // `secrets/google_oauth.json` est lu directement ; sur Android/iOS, la copie
  // embarquée a été rafraîchie par la tâche Gradle avant le build. Ne lève
  // jamais : sans identifiants, le repli hors ligne reste en place.
  await GoogleOAuthConfig.load();

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

  // Formats et langue appliqués avant la première image : aucun montant ni
  // libellé ne s'affiche avec la valeur par défaut (FCFA / français).
  AkibaMoney.currency = settings.currencyLabel;
  AkibaDate.isoStyle = settings.dateStyle == 'aaaa-mm-jj';
  AkibaL10n.setLanguage(settings.language);
  AkibaDate.english = AkibaL10n.isEnglish;

  final ProfilePhotoController photo = ProfilePhotoController(
    ProfilePhotoStore(),
  );

  // Première image tout de suite : l'ouverture courte couvre la suite.
  runApp(AkibaApp(store: store, settings: settings, photo: photo));

  // Hors du chemin critique — aucun de ces travaux ne bloque l'affichage :
  // contrôle d'intégrité de la base, photo chiffrée (coffre du système),
  // rappels de repas en arrière-plan et préchauffage des logos.
  unawaited(AkibaDatabase.integrityCheck());
  unawaited(photo.load());
  // Les rappels planifiés sont recalculés à chaque démarrage : une mise à jour
  // du système ou un redémarrage ne les laisse pas périmés. C'est le seul
  // point d'entrée, pour ne pas inscrire deux fois la tâche Workmanager.
  unawaited(ReminderScheduler.reprogram(settings, store: store));
  // Sauvegarde automatique Home Lab : silencieuse, jamais bloquante.
  unawaited(runLabAutoBackupOnStartup(store, settings));
  BrandImages.warmUp();
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
    AkibaL10n.setLanguage(_settings.language);
    AkibaDate.english = AkibaL10n.isEnglish;
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
          // Les widgets Material (sélecteurs d'heure et de date, boutons
          // système) suivent la langue choisie, comme les textes AKIBA.
          locale: Locale(_settings.language),
          supportedLocales: const <Locale>[Locale('fr'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
          // Bascule directe : pas de fondu entre deux sous-arbres qui
          // garderaient chacun leur champ de saisie et leur focus. C'est ce
          // croisement qui faisait tomber l'assertion de Flutter au premier
          // code PIN. Le zoom du logo en fin d'onboarding assure la transition.
          home: SplashGate(
            child: _settings.onboardingDone
                ? LockGate(
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
                    store: _store,
                    settings: _settings,
                    revision: _revision,
                    onFinished: () {
                      if (_settings.onboardingDone) _revision.bump();
                    },
                  ),
          ),
        );
      },
    );
  }
}
