import 'dart:io';

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
      await request.response.close();
    });
    settings = AkibaSettings(const EmptyAkibaStore());
    tokens = InMemoryLabTokenStore();
    setup = HomeLabSetup(
      service: service(),
      settings: settings,
      tokens: tokens,
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
      );

      expect(result.ok, isTrue, reason: result.message);
      // Jeton hors des réglages en clair, uniquement dans le coffre.
      expect(await tokens.read(), 'secret-jeton');
      expect(settings.labToken, isEmpty);
      expect(settings.labAutoBackup, isTrue);
      expect(settings.lastBackupTarget, 'homeLab');
      expect(settings.lastBackupAt, isNotEmpty);
      expect(setup.step, HomeLabStep.ready);
      // Première sauvegarde chiffrée envoyée immédiatement.
      expect(puts, 1);

      // Échéance respectée : aucun second envoi juste après.
      final HomeLabAutoBackup auto = HomeLabAutoBackup(
        service: service(),
        settings: settings,
        tokens: tokens,
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
    );

    expect(await auto.runIfDue(), isFalse);
    expect(puts, 0);
  });
}
