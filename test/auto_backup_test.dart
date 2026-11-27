import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akiba/core/backup/auto_backup.dart';
import 'package:akiba/core/backup/backup_service.dart';
import 'package:akiba/core/backup/home_lab_setup.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/data/simulation_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('une écriture métier déclenche la sauvegarde, un réglage non', () async {
    final SimulationAkibaStore inner = SimulationAkibaStore();
    int changes = 0;
    final AutoBackupStore store = AutoBackupStore(
      inner,
      onChanged: () => changes++,
    );

    await store.ensureDefaultAccounts();
    expect(changes, 1);

    // Les réglages passent par le magasin brut : pas de boucle de sauvegarde.
    await store.setSetting('first_name', 'Ama');
    expect(changes, 1);

    await store.setSetting('auto_backup_pending_at', '');
    expect(changes, 1);
  });

  test('un échec hors ligne reste en attente puis réussit au retour', () async {
    final SimulationAkibaStore store = SimulationAkibaStore();
    final AkibaSettings settings = AkibaSettings(store);
    await settings.load();

    // Port libre mais fermé : le premier envoi échoue comme hors ligne.
    final HttpServer probe = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final int port = probe.port;
    await probe.close(force: true);

    await settings.set('lab_url', 'http://127.0.0.1:$port');
    await settings.setFlag('lab_auto_backup', true);

    final AutoBackupCoordinator coordinator = AutoBackupCoordinator(
      store: store,
      settings: settings,
      service: BackupService.withKey(
        store,
        List<int>.generate(32, (int i) => i),
      ),
      tokens: InMemoryLabTokenStore('jeton-test'),
      debounce: Duration.zero,
      retryInterval: null,
    );
    addTearDown(coordinator.dispose);

    final AutoBackupResult offline = await coordinator.flush();
    expect(offline.attempted, isTrue);
    expect(offline.failed, <AutoBackupChannel>[AutoBackupChannel.localServer]);
    expect(offline.ok, isFalse);
    expect(coordinator.pending, isTrue);
    expect(settings.raw('auto_backup_pending_at'), isNotEmpty);
    expect(settings.raw('last_backup_at'), isEmpty);

    // Le réseau revient : même adresse, serveur disponible cette fois.
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    final Completer<Map<String, dynamic>> received =
        Completer<Map<String, dynamic>>();
    final StreamSubscription<HttpRequest> subscription = server.listen((
      HttpRequest request,
    ) async {
      final String body = await utf8.decoder.bind(request).join();
      received.complete(jsonDecode(body) as Map<String, dynamic>);
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final AutoBackupResult retried = await coordinator.retryIfPending();
    expect(retried.ok, isTrue);
    expect(retried.succeeded, <AutoBackupChannel>[
      AutoBackupChannel.localServer,
    ]);
    expect(coordinator.pending, isFalse);
    expect(settings.raw('auto_backup_pending_at'), isEmpty);
    expect(settings.raw('last_backup_at'), isNotEmpty);
    expect(settings.raw('last_backup_target'), 'homeLab');

    final Map<String, dynamic> sent = await received.future;
    expect(sent['format'], 'akiba-backup');
    expect(
      (sent['counts'] as Map<String, dynamic>)['accounts'],
      greaterThan(0),
    );
  });
}
