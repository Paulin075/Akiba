// Affiche l'empreinte SHA-1 de la clé qui signe l'APK debug.
//
//   dart run tool/debug_sha1.dart
//
// Cette empreinte et le package `com.akiba.app` forment le client OAuth
// « Android » de Google Cloud Console, sans lequel `google_sign_in` répond
// « clientConfigurationError ». Procédure complète :
// `akiba_spec/activer_connexion_google_android.md`.
//
// Aucune dépendance : `keytool` (livré avec tout JDK, donc avec Flutter/Android
// Studio) fait le travail. Sortie forcée en anglais pour que les libellés ne
// dépendent pas de la langue du poste. L'empreinte n'est pas un secret : c'est
// une donnée publique lue dans le certificat, jamais un mot de passe.
import 'dart:io';

/// Package déclaré dans `android/app/build.gradle.kts` (`applicationId`).
const String _packageId = 'com.akiba.app';

const String _defaultPassword = 'android';

void main(List<String> args) {
  final _Options options = _Options.parse(args);
  if (options.help) {
    _usage();
    return;
  }

  final File keystore = File(options.keystore ?? _defaultKeystorePath());
  if (!keystore.existsSync()) {
    _fail(
      'Aucune clé debug dans ${keystore.path}.\n'
      'Elle est créée par la première build debug : lancez '
      '`flutter build apk --debug` (ou `flutter run` sur le téléphone), puis '
      'relancez cette commande.',
    );
    return;
  }

  final _Keytool? keytool = _Keytool.find(options.keytool);
  if (keytool == null) {
    _fail(_keytoolMissing);
    return;
  }

  final ProcessResult result = keytool.run(<String>[
    '-list',
    '-v',
    '-keystore',
    keystore.path,
    '-storepass',
    options.password,
    if (options.alias != null) ...<String>['-alias', options.alias!],
  ]);
  if (result.exitCode != 0) {
    final String output = _text(result);
    if (output.toLowerCase().contains('password')) {
      _fail(
        'Le mot de passe de ${keystore.path} n’est pas « android ».\n'
        'Relancez avec --storepass <mot de passe> (et --alias <alias> si '
        'besoin).',
      );
      return;
    }
    _fail('keytool a échoué sur ${keystore.path} :\n$output');
    return;
  }

  final List<String> prints = _fingerprints('${result.stdout}');
  if (prints.isEmpty) {
    _fail('Aucune empreinte dans ${keystore.path} (alias absent ?).');
    return;
  }

  stdout.writeln('AKIBA · empreinte de signature de l’APK debug');
  stdout.writeln(
    'Source  : ${keystore.path}'
    '${options.alias == null ? '' : ' (alias ${options.alias})'}',
  );
  for (final String fingerprint in prints) {
    stdout.writeln('SHA-1   : $fingerprint');
  }
  stdout.writeln('Package : $_packageId');
  stdout.writeln();
  stdout.writeln(
    'Google Cloud Platform → Clients → « Créer un client » → Android : '
    'renseignez le package $_packageId et cette empreinte SHA-1.',
  );
  stdout.writeln(
    'Procédure complète : akiba_spec/activer_connexion_google_android.md',
  );
}

String _defaultKeystorePath() {
  final Map<String, String> environment = Platform.environment;
  final String home = Platform.isWindows
      ? (environment['USERPROFILE'] ?? environment['HOME'] ?? '')
      : (environment['HOME'] ?? '');
  final String separator = Platform.pathSeparator;
  return '$home$separator.android${separator}debug.keystore';
}

/// Empreintes trouvées dans une sortie keytool, sans doublon et dans l'ordre.
///
/// `keytool` écrit « SHA1: » en anglais (langue forcée par [_Keytool.run]) et
/// « SHA-1 : » dans une sortie traduite ; les deux formes sont acceptées.
List<String> _fingerprints(String output) {
  final RegExp pattern = RegExp(
    r'^\s*SHA-?1\s*[:：]\s*([0-9A-F]{2}(?::[0-9A-F]{2}){19})\s*$',
    caseSensitive: false,
    multiLine: true,
  );
  final List<String> prints = <String>[];
  for (final RegExpMatch match in pattern.allMatches(output)) {
    final String value = match.group(1)!.toUpperCase();
    if (!prints.contains(value)) prints.add(value);
  }
  return prints;
}

void _fail(String message) {
  stderr.writeln('AKIBA : $message');
  exitCode = 2;
}

const String _keytoolMissing =
    'keytool est introuvable.\n'
    'Installez un JDK, démarrez Android Studio une fois pour créer son JDK, '
    'ou indiquez le chemin : dart run tool/debug_sha1.dart --keytool '
    '<chemin>/keytool';

String _text(ProcessResult result) {
  final String text = '${result.stdout}${result.stderr}'.trim();
  return text.isEmpty ? '(aucun détail)' : text;
}

void _usage() {
  stdout.writeln(
    'Empreinte SHA-1 de la clé de signature de l’APK debug.\n\n'
    '  dart run tool/debug_sha1.dart\n\n'
    'Options :\n'
    '  --keystore <fichier>   autre magasin de clés\n'
    '  --alias <nom>          alias à lire (défaut : tous, filtrés sur SHA-1)\n'
    '  --storepass <secret>   mot de passe du magasin (défaut : android)\n'
    '  --keytool <chemin>     keytool à utiliser\n'
    '  -h, --help             cette aide\n\n'
    'Procédure Cloud Console : akiba_spec/activer_connexion_google_android.md',
  );
}

// --------------------------------------------------------------- keytool

/// `keytool` trouvé sur le poste, avec la langue forcée en anglais.
class _Keytool {
  _Keytool(this.executable);

  final String executable;

  /// Cherche le premier `keytool` utilisable : chemin demandé, JAVA_HOME, PATH,
  /// puis le JDK livré avec Android Studio (poste où seul Studio est installé).
  static _Keytool? find([String? requested]) {
    final List<String> candidates = <String>[
      if (requested != null && requested.isNotEmpty) requested,
      ..._candidates(),
    ];
    for (final String candidate in candidates) {
      final _Keytool keytool = _Keytool(candidate);
      if (keytool._works()) return keytool;
    }
    return null;
  }

  static List<String> _candidates() {
    final List<String> found = <String>[];
    final Map<String, String> environment = Platform.environment;
    final String? javaHome = environment['JAVA_HOME']?.trim();
    final String executable = Platform.isWindows ? 'keytool.exe' : 'keytool';

    if (javaHome != null && javaHome.isNotEmpty) {
      found.add('$javaHome/bin/$executable');
    }
    found.add('keytool');

    if (Platform.isWindows) {
      for (final String? root in <String?>[
        environment['ProgramFiles'],
        environment['LOCALAPPDATA'],
      ]) {
        if (root == null || root.isEmpty) continue;
        found.add('$root\\Android\\Android Studio\\jbr\\bin\\keytool.exe');
        found.add('$root\\Programs\\Android Studio\\jbr\\bin\\keytool.exe');
      }
    } else if (Platform.isMacOS) {
      found.add(
        '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/'
        'keytool',
      );
    }
    return found;
  }

  bool _works() {
    try {
      final ProcessResult result = Process.runSync(executable, <String>[
        '-help',
      ]);
      // `-help` écrit sur stdout (ou stderr selon la version).
      return '${result.stdout}${result.stderr}'.toLowerCase().contains(
        'keytool',
      );
    } on ProcessException {
      return false;
    }
  }

  /// Exécute keytool en anglais, pour un libellé « SHA1: » stable.
  ProcessResult run(List<String> arguments) {
    return Process.runSync(executable, <String>[
      '-J-Duser.language=en',
      '-J-Duser.country=US',
      ...arguments,
    ]);
  }
}

// --------------------------------------------------------------- options

class _Options {
  _Options({
    this.keystore,
    this.alias,
    this.keytool,
    this.password = _defaultPassword,
    this.help = false,
  });

  final String? keystore;
  final String? alias;
  final String? keytool;
  final String password;
  final bool help;

  static _Options parse(List<String> args) {
    String? keystore;
    String? alias;
    String? keytool;
    String? password;
    bool help = false;
    for (int index = 0; index < args.length; index++) {
      String? next() => index + 1 < args.length ? args[++index] : null;
      switch (args[index]) {
        case '-h':
        case '--help':
          help = true;
        case '--keystore':
          keystore = next();
        case '--alias':
          alias = next();
        case '--storepass':
          password = next();
        case '--keytool':
          keytool = next();
        default:
          stderr.writeln('AKIBA : option inconnue « ${args[index]} ».');
          help = true;
      }
    }
    return _Options(
      keystore: keystore,
      alias: alias,
      keytool: keytool,
      password: password ?? _defaultPassword,
      help: help,
    );
  }
}
