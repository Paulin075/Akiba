import 'dart:convert';
import 'dart:io';

import 'package:akiba/core/backup/backup_service.dart';
import 'package:akiba/data/simulation_store.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _envelope() => <String, dynamic>{
  'format': 'akiba-backup',
  'version': 2,
  'cipher': 'AES-256-GCM',
  'ciphertext': 'c2VhbGVk',
  'createdAt': '2026-11-20T10:00:00Z',
  'counts': <String, int>{'transactions': 3},
};

void main() {
  group('Lecture de la réponse d’un serveur de sauvegarde', () {
    test('un corps vide signifie « aucune sauvegarde »', () {
      expect(BackupService.decodeRemoteBackup(''), isNull);
      expect(BackupService.decodeRemoteBackup('  \n\t '), isNull);
    });

    test('une enveloppe brute est conservée telle quelle', () {
      final Map<String, dynamic>? parsed = BackupService.decodeRemoteBackup(
        jsonEncode(_envelope()),
      );
      expect(parsed, isNotNull);
      expect(parsed!['format'], 'akiba-backup');
      expect(parsed['ciphertext'], 'c2VhbGVk');
    });

    test('une enveloppe rangée sous backup/envelope est dépliée', () {
      for (final String key in <String>[
        'backup',
        'envelope',
        'latest',
        'data',
      ]) {
        final Map<String, dynamic>? parsed = BackupService.decodeRemoteBackup(
          jsonEncode(<String, Object>{key: _envelope()}),
        );
        expect(parsed?['format'], 'akiba-backup', reason: key);
      }
    });

    test('une chaîne JSON échappée est redécodée', () {
      final Map<String, dynamic>? parsed = BackupService.decodeRemoteBackup(
        jsonEncode(jsonEncode(_envelope())),
      );
      expect(parsed?['format'], 'akiba-backup');
    });

    test('une page web ne produit jamais « format non reconnu »', () {
      expect(
        () => BackupService.decodeRemoteBackup('<!DOCTYPE html><html></html>'),
        throwsA(
          isA<BackupException>()
              .having(
                (BackupException e) => e.message,
                'message',
                contains('page web'),
              )
              .having(
                (BackupException e) => e.message,
                'message',
                isNot(contains('Format de sauvegarde non reconnu')),
              ),
        ),
      );
    });

    test('un JSON sans enveloppe explique le jeton ou l’adresse', () {
      expect(
        () => BackupService.decodeRemoteBackup('{"status":"ok"}'),
        throwsA(
          isA<BackupException>().having(
            (BackupException e) => e.message,
            'message',
            contains('n’a pas renvoyé une sauvegarde AKIBA'),
          ),
        ),
      );
    });
  });

  group('fetchRemote : 404, 204 et sauvegarde valide', () {
    test('404 et 204 renvoient null, sans analyse de corps', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      int calls = 0;
      server.listen((HttpRequest request) async {
        calls++;
        request.response.statusCode = calls == 1
            ? HttpStatus.notFound
            : HttpStatus.noContent;
        if (calls == 2) request.response.write('');
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final BackupService service = BackupService.withKey(
        SimulationAkibaStore(),
        List<int>.filled(32, 7),
      );
      final String url = 'http://127.0.0.1:${server.port}/';
      expect(await service.fetchRemote(url: url, token: 'jeton'), isNull);
      expect(await service.fetchRemote(url: url, token: 'jeton'), isNull);
    });

    test('une enveloppe valide est rendue intacte', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      server.listen((HttpRequest request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(_envelope()));
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final BackupService service = BackupService.withKey(
        SimulationAkibaStore(),
        List<int>.filled(32, 7),
      );
      final Map<String, dynamic>? parsed = await service.fetchRemote(
        url: 'http://127.0.0.1:${server.port}/backup',
        token: 'jeton',
      );
      expect(parsed?['format'], 'akiba-backup');
      expect(parsed?['sha256'], isNull);
      expect(parsed?['ciphertext'], 'c2VhbGVk');
    });

    test('une sauvegarde plus grosse que 8 ko est lue en entier', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final Map<String, dynamic> envelope = _envelope()
        ..['note'] = 'x' * 40000
        ..['sha256'] = 'fin-de-sauvegarde';
      server.listen((HttpRequest request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(envelope));
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final BackupService service = BackupService.withKey(
        SimulationAkibaStore(),
        List<int>.filled(32, 7),
      );
      final Map<String, dynamic>? parsed = await service.fetchRemote(
        url: 'http://127.0.0.1:${server.port}/backup',
        token: 'jeton',
      );
      expect(parsed?['sha256'], 'fin-de-sauvegarde');
      expect((parsed?['note'] as String?)?.length, 40000);
    });

    test('un 200 avec corps vide vaut « aucune sauvegarde »', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      server.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final BackupService service = BackupService.withKey(
        SimulationAkibaStore(),
        List<int>.filled(32, 7),
      );
      expect(
        await service.fetchRemote(
          url: 'http://127.0.0.1:${server.port}/',
          token: 'jeton',
        ),
        isNull,
      );
    });

    test('un 401 est expliqué avec le motif du serveur', () async {
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
              'detail': 'Jeton invalide. Vérifiez SHARED_TOKEN.',
            }),
          );
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final BackupService service = BackupService.withKey(
        SimulationAkibaStore(),
        List<int>.filled(32, 7),
      );
      Object? failure;
      try {
        await service.fetchRemote(
          url: 'http://127.0.0.1:${server.port}/',
          token: 'mauvais-jeton',
        );
      } on BackupException catch (error) {
        failure = error;
      }

      expect(failure, isA<BackupException>());
      final String message = (failure! as BackupException).message;
      expect(message, contains('Jeton refusé'));
      expect(message, contains('401'));
      expect(message, contains('Jeton invalide'));
      expect(message, isNot(contains('mauvais-jeton')));
    });

    test('le motif du serveur est lu sans reprendre un corps brut', () {
      expect(
        BackupService.serverDetail('{"detail":"Jeton manquant."}'),
        'Jeton manquant.',
      );
      expect(BackupService.serverDetail('<html>502</html>'), isNull);
      expect(BackupService.serverDetail('{"autre":1}'), isNull);
      expect(BackupService.serverDetail(''), isNull);
    });
  });
}
