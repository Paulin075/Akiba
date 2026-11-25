import 'package:akiba/core/backup/backup_service.dart';
import 'package:akiba/core/backup/google_account.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faux rejet « Connectez le même compte Google pour restaurer cette
/// sauvegarde » : l'identité du compte est normalisée et plusieurs variantes
/// sont essayées, donc une reconnexion avec le même compte aboutit toujours.
void main() {
  BackupService service() => BackupService(const EmptyAkibaStore());

  group('Identité Google normalisée', () {
    test('e-mail en minuscules sans espace, identifiant stable conservé', () {
      final GoogleAccount account = GoogleAccount.normalized(
        id: '  1049ABC  ',
        email: ' Paul.X@Gmail.COM ',
      );

      expect(account.id, '1049ABC');
      expect(account.email, 'paul.x@gmail.com');
      expect(account.rawEmail, 'Paul.X@Gmail.COM');
      expect(account.label, 'paul.x@gmail.com');
      // Identifiant stable d'abord, puis e-mail normalisé, puis variante brute.
      expect(account.keyCandidates, <String>[
        '1049ABC',
        'paul.x@gmail.com',
        'Paul.X@Gmail.COM',
      ]);
    });

    test('les espaces internes sont supprimés et les doublons écartés', () {
      final GoogleAccount account = GoogleAccount.normalized(
        id: ' sub 123 ',
        email: 'sub123@gmail.com',
      );

      expect(account.id, 'sub123');
      // La variante brute est conservée pour rouvrir les anciennes enveloppes.
      expect(account.keyCandidates, <String>[
        'sub123',
        'sub 123',
        'sub123@gmail.com',
      ]);
      expect(GoogleAccount.none.keyCandidates, isEmpty);
      expect(GoogleAccount.none.isEmpty, isTrue);
      expect(GoogleAccount.none.label, 'aucun compte Google');
    });
  });

  group('Restauration Drive — même compte, aucune fausse alerte', () {
    test(
      'e-mail saisi avec espaces et majuscules : la clé est retrouvée',
      () async {
        final Map<String, dynamic> envelope = await service().createEnvelope(
          deviceId: 'poste-1',
          account: GoogleAccount.normalized(email: ' Paul.X@Gmail.COM '),
        );

        expect(envelope['kdf'], 'PBKDF2-HMAC-SHA256');
        expect(
          Map<String, dynamic>.from(envelope['account'] as Map)['email'],
          'paul.x@gmail.com',
        );

        // Reconnexion plus tard, même compte, saisie différente.
        final Map<String, dynamic> payload = await service().decryptEnvelope(
          envelope,
          account: GoogleAccount.normalized(email: 'paul.x@gmail.com'),
        );
        expect(payload['counts'], isA<Map>());
      },
    );

    test(
      'identifiant stable avec espaces : la sauvegarde se déchiffre',
      () async {
        final Map<String, dynamic> envelope = await service().createEnvelope(
          deviceId: 'poste-1',
          account: GoogleAccount.normalized(
            id: ' 1094-sub ',
            email: 'ama@gmail.com',
          ),
        );

        final Map<String, dynamic> payload = await service().decryptEnvelope(
          envelope,
          account: GoogleAccount.fromId('1094-sub'),
        );
        expect(payload['counts'], isA<Map>());
      },
    );

    test(
      'sauvegarde héritée (identifiant brut) restaurable avec le même compte',
      () async {
        // Ancienne génération : la clé dérivait de la chaîne brute fournie.
        final Map<String, dynamic> envelope = await service().createEnvelope(
          deviceId: 'poste-1',
          account: const GoogleAccount(id: 'Paul.X@Gmail.com'),
        );

        // La session actuelle fournit e-mail normalisé + variante brute.
        final Map<String, dynamic> payload = await service().decryptEnvelope(
          envelope,
          account: GoogleAccount.normalized(email: 'Paul.X@Gmail.com'),
        );
        expect(payload['counts'], isA<Map>());
      },
    );
  });

  group('Restauration Drive — vraie différence de compte', () {
    test('l’e-mail attendu est affiché, sans accuser une autre clé', () async {
      final Map<String, dynamic> envelope = await service().createEnvelope(
        deviceId: 'poste-1',
        account: GoogleAccount.normalized(email: 'paul@gmail.com'),
      );

      await expectLater(
        service().decryptEnvelope(
          envelope,
          account: GoogleAccount.normalized(email: 'autre@gmail.com'),
        ),
        throwsA(
          isA<BackupException>().having(
            (BackupException error) => error.message,
            'message',
            allOf(contains('paul@gmail.com'), contains('compte Google')),
          ),
        ),
      );
    });

    test('sans compte connecté, le message nomme le compte attendu', () async {
      final Map<String, dynamic> envelope = await service().createEnvelope(
        deviceId: 'poste-1',
        account: GoogleAccount.normalized(email: 'paul@gmail.com'),
      );

      await expectLater(
        service().decryptEnvelope(envelope),
        throwsA(
          isA<BackupException>().having(
            (BackupException error) => error.message,
            'message',
            contains('paul@gmail.com'),
          ),
        ),
      );
    });

    test('compte identique mais clé différente : message dédié', () async {
      final Map<String, dynamic> envelope = await service().createEnvelope(
        deviceId: 'poste-1',
        account: GoogleAccount.normalized(id: 'sub-1', email: 'paul@gmail.com'),
      );

      await expectLater(
        service().decryptEnvelope(
          envelope,
          account: const GoogleAccount(id: 'sub-2', email: 'paul@gmail.com'),
        ),
        throwsA(
          isA<BackupException>().having(
            (BackupException error) => error.message,
            'message',
            contains('déconnectez puis reconnectez'),
          ),
        ),
      );
    });
  });
}
