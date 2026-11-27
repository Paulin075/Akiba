import 'dart:convert';
import 'dart:io';

import 'package:akiba/core/backup/backup_service.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('le diagnostic teste le schéma, le port et le chemin saisis', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    String? requestedPath;
    server.listen((HttpRequest request) async {
      requestedPath = request.uri.path;
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final BackupService service = BackupService.withKey(
      const EmptyAkibaStore(),
      List<int>.generate(32, (int index) => index),
    );
    final HomeLabProbe probe = await service.probeRemote(
      url: '127.0.0.1:${server.port}/health',
      token: '',
    );
    expect(probe.ok, isTrue);
    expect(probe.statusCode, HttpStatus.noContent);
    expect(requestedPath, '/health');
  });

  test('un 401 affiche le motif du serveur, jamais le jeton', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.listen((HttpRequest request) async {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, String>{
            'detail': 'Jeton invalide : le jeton reçu est refusé.',
          }),
        );
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final BackupService service = BackupService.withKey(
      const EmptyAkibaStore(),
      List<int>.generate(32, (int index) => index),
    );
    final HomeLabProbe probe = await service.probeRemote(
      url: 'http://127.0.0.1:${server.port}/',
      token: 'jeton-secret-123',
    );
    expect(probe.reachable, isTrue);
    expect(probe.authenticated, isFalse);
    expect(probe.message, contains('Jeton invalide'));
    expect(probe.message, isNot(contains('jeton-secret-123')));
  });

  test('un motif qui recopie le jeton est masqué', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.listen((HttpRequest request) async {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, String>{
            'detail': 'Refusé pour le jeton jeton-secret-123.',
          }),
        );
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final BackupService service = BackupService.withKey(
      const EmptyAkibaStore(),
      List<int>.generate(32, (int index) => index),
    );
    final HomeLabProbe probe = await service.probeRemote(
      url: 'http://127.0.0.1:${server.port}/',
      token: 'jeton-secret-123',
    );
    expect(probe.message, contains('••••'));
    expect(probe.message, isNot(contains('jeton-secret-123')));
  });

  test(
    'URL incorrecte et port inaccessible ont un diagnostic précis',
    () async {
      final BackupService service = BackupService.withKey(
        const EmptyAkibaStore(),
        List<int>.generate(32, (int index) => index),
      );
      final HomeLabProbe invalid = await service.probeRemote(
        url: 'file:///tmp/backup',
        token: '',
      );
      expect(invalid.message, contains('Adresse invalide'));

      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int port = server.port;
      await server.close(force: true);
      final HomeLabProbe refused = await service.probeRemote(
        url: 'http://127.0.0.1:$port/health',
        token: '',
      );
      expect(refused.reachable, isFalse);
      expect(refused.message, contains('port'));
    },
  );
}
