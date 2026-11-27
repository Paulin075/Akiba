import 'dart:convert';
import 'dart:io';

import 'package:akiba/core/backup/backup_code.dart';
import 'package:akiba/core/backup/backup_service.dart';
import 'package:akiba/core/backup/home_lab_setup.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parcours Home Lab en deux étapes : test d'IP/ping **sans jeton**, puis
/// jeton protégé dans le coffre et sauvegarde automatique réellement armée.
void main() {
  late HttpServer server;
  late AkibaSettings settings;
  late InMemoryLabTokenStore tokens;
  late InMemoryBackupCodeStore codes;
  late HomeLabSetup setup;
  late int puts;

  BackupService service() => BackupService.withKey(
    const EmptyAkibaStore(),
    List<int>.generate(32, (int index) => index + 1),
  );

  setUp(() async {
    puts = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) async {
      final String auth = request.headers.value('authorization') ?? '';
      final bool accepted = auth == 'Bearer secret-jeton';
      if (request.method == 'PUT') puts++;
      request.response.statusCode = accepted
          ? HttpStatus.noContent
          : HttpStatus.unauthorized;
      if (!accepted) {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, String>{'detail': 'Jeton invalide (test).'}),
          );
      }
      await request.response.close();
    });
    settings = AkibaSettings(const EmptyAkibaStore());
    tokens = InMemoryLabTokenStore();
    codes = InMemoryBackupCodeStore();
    setup = HomeLabSetup(
      service: service(),
      settings: settings,
      tokens: tokens,
      codes: codes,
    );
    await setup.load();
  });

  tearDown(() => server.close(force: true));

  test(
    'étape 1 : IP testée sans jeton, latence mesurée, étape 2 ouverte',
    () async {
      expect(setup.step, HomeLabStep.address);
      expect(setup.tokenStepUnlocked, isFalse);

      final HomeLabSetupResult result = await setup.testAddress(
        '127.0.0.1:${server.port}',
      );

      expect(result.ok, isTrue, reason: result.message);
      expect(setup.reachable, isTrue);
      expect(setup.tokenStepUnlocked, isTrue);
      expect(setup.step, HomeLabStep.token);
      expect(result.latency, isNotNull);
      expect(setup.latencyLabel, contains('ms'));
      // L'adresse testée est celle qui sera utilisée pour la sauvegarde.
      expect(settings.labUrl, 'http://127.0.0.1:${server.port}');
      // Aucune écriture réseau à l'étape 1.
      expect(puts, 0);
    },
  );

  test('test avec un jeton refusé : motif du serveur affiché', () async {
    final HomeLabSetupResult result = await setup.testAddress(
      '127.0.0.1:${server.port}',
      token: 'mauvais',
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('Jeton invalide (test)'));
    expect(result.message, isNot(contains('mauvais')));
    // L'étape 2 reste ouverte : le jeton peut être corrigé juste après.
    expect(setup.tokenStepUnlocked, isTrue);
    expect(setup.step, HomeLabStep.token);
  });

  test('adresse invalide : refusée avant tout appel réseau', () async {
    final HomeLabSetupResult result = await setup.testAddress(
      'file:///tmp/backup',
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('Adresse invalide'));
    expect(setup.reachable, isFalse);
    expect(setup.step, HomeLabStep.address);
    expect(setup.tokenStepUnlocked, isFalse);
  });

  test('étape 2 : un code à 4 chiffres est obligatoire', () async {
    await setup.testAddress('127.0.0.1:${server.port}');

    final HomeLabSetupResult result = await setup.activateToken('secret-jeton');

    expect(result.ok, isFalse);
    expect(result.message, contains('code de sauvegarde'));
    expect(await tokens.read(), isEmpty);
    expect(await codes.read(), isEmpty);
    expect(settings.labAutoBackup, isFalse);
    expect(puts, 0);
  });

  test('étape 2 : un jeton refusé n’active ni coffre ni sauvegarde', () async {
    await setup.testAddress('127.0.0.1:${server.port}');

    final HomeLabSetupResult result = await setup.activateToken('mauvais');

    expect(result.ok, isFalse);
    expect(result.message, contains('jeton'));
    expect(await tokens.read(), isEmpty);
    expect(settings.labAutoBackup, isFalse);
    expect(setup.step, HomeLabStep.token);
  });

  test(
    'étape 2 : jeton validé, coffre rempli, sauvegarde auto armée et envoyée',
    () async {
      await setup.testAddress('127.0.0.1:${server.port}');

      final HomeLabSetupResult result = await setup.activateToken(
        ' secret-jeton ',
        code: '1234',
      );

      expect(result.ok, isTrue, reason: result.message);
      // Jeton hors des réglages en clair, uniquement dans le coffre.
      expect(await tokens.read(), 'secret-jeton');
      expect(settings.labToken, isEmpty);
      expect(settings.labAutoBackup, isTrue);
      expect(settings.lastBackupTarget, 'homeLab');
      expect(settings.lastBackupAt, isNotEmpty);
      expect(setup.step, HomeLabStep.ready);
      // Le code à 4 chiffres protège le coffre et part dans l'enveloppe.
      expect(setup.codeSaved, isTrue);
      expect(await codes.read(), '1234');
      expect(settings.raw('backup_code'), isEmpty);
      // Première sauvegarde chiffrée envoyée immédiatement.
      expect(puts, 1);

      // Échéance respectée : aucun second envoi juste après.
      final HomeLabAutoBackup auto = HomeLabAutoBackup(
        service: service(),
        settings: settings,
        tokens: tokens,
        codes: codes,
      );
      expect(await auto.runIfDue(), isFalse);
      expect(puts, 1);
    },
  );

  test('sans activation, la sauvegarde automatique ne part pas', () async {
    settings = AkibaSettings(const EmptyAkibaStore());
    final HomeLabAutoBackup auto = HomeLabAutoBackup(
      service: service(),
      settings: settings,
      tokens: InMemoryLabTokenStore('secret-jeton'),
      codes: InMemoryBackupCodeStore('1234'),
    );

    expect(await auto.runIfDue(), isFalse);
    expect(puts, 0);
  });
}
