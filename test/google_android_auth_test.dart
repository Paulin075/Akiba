import 'dart:convert';
import 'dart:io';

import 'package:akiba/core/backup/google_android_auth.dart';
import 'package:akiba/core/backup/google_drive_backup.dart';
import 'package:akiba/core/backup/google_token_vault.dart';
import 'package:akiba/core/config/google_oauth_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Coffre en mémoire : aucun greffon natif, aucun jeton sur disque.
class _FakeVault implements GoogleTokenVault {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FakeAndroidAuth implements GoogleAndroidAuth {
  _FakeAndroidAuth({this.token, this.failure});

  final GoogleAndroidToken? token;
  final GoogleAuthException? failure;
  int connects = 0;
  int disconnects = 0;

  @override
  Future<GoogleAndroidToken> connect() async {
    connects += 1;
    final GoogleAuthException? error = failure;
    if (error != null) throw error;
    return token!;
  }

  @override
  Future<GoogleAndroidToken?> restore() async => null;

  @override
  Future<void> disconnect() async => disconnects += 1;
}

Future<void> _loadConfig({
  String clientId = '',
  String serverClientId = '',
}) async {
  final Directory dir = Directory.systemTemp.createTempSync('akiba_google');
  final File file = File(p.join(dir.path, 'google_oauth.json'));
  file.writeAsStringSync(
    jsonEncode(<String, String>{
      GoogleOAuthConfig.clientIdKey: clientId,
      GoogleOAuthConfig.clientSecretKey: '',
      GoogleOAuthConfig.androidServerKey: serverClientId,
    }),
  );
  await GoogleOAuthConfig.load(devPath: file.path);
  addTearDown(() => dir.deleteSync(recursive: true));
}

GoogleDriveService _service(
  _FakeVault vault,
  GoogleAndroidAuth auth, {
  bool android = true,
}) => GoogleDriveService(vault: vault, androidAuth: auth, android: android);

void main() {
  group('Connexion Google Android (google_sign_in)', () {
    test('le jeton Drive est obtenu sans jeton de rafraîchissement', () async {
      await _loadConfig(serverClientId: 'web-123.apps.googleusercontent.com');
      final _FakeVault vault = _FakeVault();
      final _FakeAndroidAuth auth = _FakeAndroidAuth(
        token: const GoogleAndroidToken(
          accessToken: 'ya29.drive-token',
          email: 'test@example.com',
        ),
      );

      final GoogleSession session = await _service(vault, auth).signIn();

      expect(session.accessToken, 'ya29.drive-token');
      expect(session.email, 'test@example.com');
      // Play services renouvelle le jeton : rien de durable à écrire.
      expect(vault.values.containsKey('akiba_google_refresh_token'), isFalse);
      expect(await _service(vault, auth).linkedEmail(), 'test@example.com');
    });

    test('sans client « Application Web », la connexion est refusée', () async {
      await _loadConfig(clientId: 'desktop-123.apps.googleusercontent.com');
      final _FakeVault vault = _FakeVault();
      final _FakeAndroidAuth auth = _FakeAndroidAuth(
        token: const GoogleAndroidToken(accessToken: 'x', email: 'a@b.c'),
      );

      expect(
        () => _service(vault, auth).signIn(),
        throwsA(
          isA<GoogleAuthException>().having(
            (GoogleAuthException e) => e.message,
            'message',
            allOf(contains('com.akiba.app'), contains('SHA-1')),
          ),
        ),
      );
      expect(auth.connects, 0);
    });

    test(
      'un refus du greffon devient un message lisible, sans session',
      () async {
        await _loadConfig(serverClientId: 'web-123.apps.googleusercontent.com');
        final _FakeVault vault = _FakeVault();
        final GoogleDriveService service = _service(
          vault,
          _FakeAndroidAuth(
            failure: const GoogleAuthException(
              'Google refuse la connexion Android. Vérifiez l’empreinte SHA-1.',
            ),
          ),
        );

        await expectLater(
          service.signIn(),
          throwsA(isA<GoogleAuthException>()),
        );
        expect(vault.values, isEmpty);
        expect(await service.linkedEmail(), isNull);
      },
    );

    test('la déconnexion révoque l’accès et vide le coffre', () async {
      await _loadConfig(serverClientId: 'web-123.apps.googleusercontent.com');
      final _FakeVault vault = _FakeVault();
      final _FakeAndroidAuth auth = _FakeAndroidAuth(
        token: const GoogleAndroidToken(
          accessToken: 'ya29.drive-token',
          email: 'test@example.com',
        ),
      );
      final GoogleDriveService service = _service(vault, auth);
      await service.signIn();

      await service.signOut();

      expect(auth.disconnects, 1);
      expect(vault.values, isEmpty);
      expect(await service.linkedEmail(), isNull);
    });

    test('hors Android, le flux boucle locale reste le seul chemin', () async {
      // Identifiant présent mais non Google : le flux de bureau s'arrête avant
      // d'ouvrir le navigateur, et `google_sign_in` n'est jamais appelé.
      await _loadConfig(clientId: 'pas-un-client');
      final _FakeVault vault = _FakeVault();
      final _FakeAndroidAuth auth = _FakeAndroidAuth(
        token: const GoogleAndroidToken(accessToken: 'x', email: 'a@b.c'),
      );

      await expectLater(
        _service(vault, auth, android: false).signIn(),
        throwsA(
          isA<GoogleAuthException>().having(
            (GoogleAuthException e) => e.message,
            'message',
            contains('Aucun identifiant OAuth exploitable'),
          ),
        ),
      );
      expect(auth.connects, 0);
    });
  });
}
