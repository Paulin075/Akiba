// Copie les identifiants OAuth Google locaux vers la copie embarquée au build.
//
//   dart run tool/sync_oauth_secrets.dart [fichier source]
//
// Cette commande n'a **pas** à être retapée : la même copie est régénérée au
// démarrage sur ordinateur (`GoogleOAuthConfig.load`) et avant chaque build
// Android (tâche Gradle `syncOAuthSecrets`). Elle reste utile pour forcer une
// copie ou diagnostiquer un identifiant refusé.
//
// Source : `secrets/google_oauth.json` (jamais versionné), ou le chemin donné.
// Cible  : `assets/config/google_oauth.json` (jamais versionné, embarqué au
//          build et lu à l'exécution par `GoogleOAuthConfig`).
//
// Le script est idempotent : si la cible est déjà à jour, rien n'est réécrit.
// Il ne révèle jamais la valeur d'un identifiant en entier.
import 'dart:convert';
import 'dart:io';

const String _defaultSource = 'secrets/google_oauth.json';
const String _target = 'assets/config/google_oauth.json';
const String _idKey = 'AKIBA_GOOGLE_CLIENT_ID';
const String _secretKey = 'AKIBA_GOOGLE_CLIENT_SECRET';
const String _serverKey = 'AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID';
const String _clientSuffix = '.apps.googleusercontent.com';

void main(List<String> args) {
  final String source = args.isEmpty ? _defaultSource : args.first;
  final File sourceFile = File(source);

  if (!sourceFile.existsSync()) {
    _removeIfPresent();
    stderr.writeln(
      'AKIBA : $source introuvable — aucune copie embarquée.\n'
      'L’application reste utilisable hors ligne (dossier Drive synchronisé).\n'
      'Créez $source avec {"$_idKey": "…$_clientSuffix", "$_secretKey": "", '
      '"$_serverKey": "…$_clientSuffix"}.',
    );
    exitCode = 2;
    return;
  }

  Map<String, dynamic> values;
  try {
    final Object? decoded = jsonDecode(sourceFile.readAsStringSync());
    if (decoded is! Map) {
      throw const FormatException('objet JSON attendu');
    }
    values = Map<String, dynamic>.from(decoded);
  } catch (error) {
    stderr.writeln('AKIBA : $source illisible (${error.runtimeType}).');
    exitCode = 2;
    return;
  }

  final String clientId = '${values[_idKey] ?? ''}'.trim();
  final String clientSecret = '${values[_secretKey] ?? ''}'.trim();
  final String serverClientId = '${values[_serverKey] ?? ''}'.trim();

  if (clientId.isEmpty && serverClientId.isEmpty) {
    _removeIfPresent();
    stderr.writeln('AKIBA : $_idKey et $_serverKey sont vides dans $source.');
    exitCode = 2;
    return;
  }
  for (final String id in <String>[clientId, serverClientId]) {
    if (id.isNotEmpty && !id.endsWith(_clientSuffix)) {
      _removeIfPresent();
      stderr.writeln(
        'AKIBA : « ${_mask(id)} » n’est pas un identifiant OAuth Google.\n'
        'Un client OAuth se termine par $_clientSuffix. Copie refusée pour '
        'éviter un « 400 invalid_request ».',
      );
      exitCode = 2;
      return;
    }
  }

  final String output = const JsonEncoder.withIndent('  ')
      .convert(<String, String>{
        _idKey: clientId,
        _secretKey: clientSecret,
        if (serverClientId.isNotEmpty) _serverKey: serverClientId,
      });

  final File targetFile = File(_target);
  if (targetFile.existsSync() &&
      targetFile.readAsStringSync().replaceAll('\r\n', '\n') == '$output\n') {
    stdout.writeln('AKIBA : $_target déjà à jour (${_mask(clientId)}).');
    return;
  }

  targetFile.parent.createSync(recursive: true);
  targetFile.writeAsStringSync('$output\n', flush: true);

  stdout.writeln(
    'AKIBA : identifiants Google OAuth copiés vers $_target '
    '(${_mask(clientId)}). Fichier ignoré par Git.',
  );
  if (clientSecret.isNotEmpty) {
    stdout.writeln(
      'Attention : un client de bureau n’a pas besoin de secret. '
      'Cette valeur serait embarquée dans l’APK ; préférez la laisser vide.',
    );
  }
}

/// Supprime la copie embarquée pour ne jamais livrer un identifiant périmé.
void _removeIfPresent() {
  final File targetFile = File(_target);
  if (targetFile.existsSync()) {
    targetFile.deleteSync();
    stdout.writeln('AKIBA : $_target supprimé (aucun identifiant valide).');
  }
}

/// Aperçu non réversible d'un identifiant : jamais la valeur complète.
String _mask(String value) {
  if (value.length <= 18) return '…';
  return '${value.substring(0, 10)}…${value.substring(value.length - 12)}';
}
