import 'package:akiba/core/backup/backup_code.dart';
import 'package:akiba/core/backup/backup_service.dart';
import 'package:akiba/core/backup/google_account.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sauvegarde du serveur protégée par un code à 4 chiffres : plus besoin du
/// compte Google, le même code rouvre l'enveloppe sur un autre appareil.
void main() {
  BackupService service() => BackupService(const EmptyAkibaStore());

  group('Code à 4 chiffres', () {
    test('validation : exactement quatre chiffres', () {
      expect(isValidBackupCode('1234'), isTrue);
      expect(isValidBackupCode(' 12 34 '), isTrue);
      expect(isValidBackupCode('123'), isFalse);
      expect(isValidBackupCode('12345'), isFalse);
      expect(isValidBackupCode('12a4'), isFalse);
      expect(isValidBackupCode(''), isFalse);
      expect(normalizeBackupCode(' 12 34 '), '1234');
    });

    test('enveloppe version 4 : kdf dédié, aucun compte Google', () async {
      final Map<String, dynamic> envelope = await service().createEnvelope(
        deviceId: 'poste-1',
        account: GoogleAccount.normalized(email: 'paul@gmail.com'),
        code: '1234',
      );

      expect(envelope['version'], 4);
      expect(envelope['kdf'], 'PBKDF2-CODE');
      expect(envelope['salt'], isA<String>());
      expect(envelope.containsKey('account'), isFalse);
      // Le code lui-même n'est jamais écrit dans l'enveloppe.
      expect(envelope.toString().contains('1234'), isFalse);
    });

    test('le même code rouvre la sauvegarde sur un autre appareil', () async {
      final Map<String, dynamic> envelope = await service().createEnvelope(
        deviceId: 'poste-1',
        code: '1234',
      );

      final Map<String, dynamic> payload = await service().decryptEnvelope(
        envelope,
        code: ' 12 34 ',
      );
      expect(payload['counts'], isA<Map>());
    });

    test('code absent : demandé explicitement, rien n’est déchiffré', () async {
      final Map<String, dynamic> envelope = await service().createEnvelope(
        deviceId: 'poste-1',
        code: '1234',
      );

      await expectLater(
        service().decryptEnvelope(envelope),
        throwsA(
          isA<BackupException>()
              .having(
                (BackupException e) => e.codeRequired,
                'codeRequired',
                true,
              )
              .having(
                (BackupException e) => e.message,
                'message',
                contains('code à 4 chiffres'),
              ),
        ),
      );
    });

    test('code faux : message d’oubli, aucune fuite du code saisi', () async {
      final Map<String, dynamic> envelope = await service().createEnvelope(
        deviceId: 'poste-1',
        code: '1234',
      );

      await expectLater(
        service().decryptEnvelope(envelope, code: '9999'),
        throwsA(
          isA<BackupException>()
              .having((BackupException e) => e.codeWrong, 'codeWrong', true)
              .having(
                (BackupException e) => e.message,
                'message',
                allOf(
                  contains('Code à 4 chiffres incorrect'),
                  contains('oublié'),
                ),
              )
              .having(
                (BackupException e) => e.message,
                'message',
                isNot(contains('9999')),
              ),
        ),
      );
    });

    test('un code de longueur invalide est refusé à la création', () async {
      await expectLater(
        service().createEnvelope(deviceId: 'poste-1', code: '12'),
        throwsA(isA<BackupException>()),
      );
    });

    test('sans code, la clé de l’appareil reste utilisée', () async {
      final BackupService device = BackupService.withKey(
        const EmptyAkibaStore(),
        List<int>.generate(32, (int index) => index + 1),
      );
      final Map<String, dynamic> envelope = await device.createEnvelope(
        deviceId: 'poste-1',
      );
      expect(envelope['kdf'], 'device-key');
      final Map<String, dynamic> payload = await device.decryptEnvelope(
        envelope,
      );
      expect(payload['counts'], isA<Map>());
    });

    test('une enveloppe Google reste ouvrable avec le compte', () async {
      final GoogleAccount account = GoogleAccount.normalized(
        email: 'paul@gmail.com',
      );
      final Map<String, dynamic> envelope = await service().createEnvelope(
        deviceId: 'poste-1',
        account: account,
      );
      expect(envelope['kdf'], 'PBKDF2-HMAC-SHA256');

      final Map<String, dynamic> payload = await service().decryptEnvelope(
        envelope,
        account: account,
      );
      expect(payload['counts'], isA<Map>());
    });
  });
}
