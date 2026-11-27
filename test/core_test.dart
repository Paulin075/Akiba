import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:akiba/core/ai/ai_client.dart';
import 'package:akiba/core/ai/ai_command_parser.dart';
import 'package:akiba/core/ai/ai_key_vault.dart';
import 'package:akiba/core/ai/ai_model_catalog.dart';
import 'package:akiba/core/ai/ai_quota.dart';
import 'package:akiba/core/format/akiba_currency.dart';
import 'package:akiba/core/format/akiba_money.dart';
import 'package:akiba/core/backup/backup_service.dart';
import 'package:akiba/core/backup/google_account.dart';
import 'package:akiba/core/config/google_oauth_config.dart';
import 'package:akiba/core/database/akiba_database.dart';
import 'package:akiba/core/database/akiba_secure_key.dart';
import 'package:akiba/core/notifications/reminder_planner.dart';
import 'package:akiba/core/notifications/background_reminders.dart';
import 'package:akiba/core/security/pin_vault.dart';
import 'package:akiba/core/sms/sms_parser.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:akiba/data/models/account.dart';
import 'package:akiba/data/models/account_brand.dart';
import 'package:akiba/data/models/debt.dart';
import 'package:akiba/data/models/transaction_record.dart';
import 'package:akiba/data/sqlite_akiba_store.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 19, 10, 15);

  group('Coffre du PIN', () {
    late Directory directory;
    late Database db;
    late SqliteAkibaStore store;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('akiba_pin');
      db = AkibaDatabase.openEncrypted(
        p.join(directory.path, 'akiba.db'),
        keyHex: AkibaSecureKey.generateHexKey(),
      );
      store = SqliteAkibaStore(db);
    });

    tearDown(() {
      db.close();
      directory.deleteSync(recursive: true);
    });

    test('l’empreinte dépend du PIN et du sel', () {
      final String salt = '00112233445566778899aabbccddeeff';
      final String other = 'ffeeddccbbaa99887766554433221100';
      expect(PinVault.hashPin('4271', salt), PinVault.hashPin('4271', salt));
      expect(
        PinVault.hashPin('4271', salt, rounds: 10),
        isNot(PinVault.hashPin('4272', salt, rounds: 10)),
      );
      expect(
        PinVault.hashPin('4271', salt, rounds: 10),
        isNot(PinVault.hashPin('4271', other, rounds: 10)),
      );
    });

    test('les PIN triviaux sont refusés', () {
      expect(PinVault.isTrivial('0000'), isTrue);
      expect(PinVault.isTrivial('1234'), isTrue);
      expect(PinVault.isTrivial('4321'), isTrue);
      expect(PinVault.isTrivial('12'), isTrue);
      expect(PinVault.isTrivial('4271'), isFalse);
    });

    test('le PIN n’est jamais stocké et se vérifie', () async {
      final PinVault vault = PinVault(store);
      await vault.setPin('4271');

      expect(await vault.isConfigured(), isTrue);
      expect(await store.setting('pin_hash'), isNot('4271'));
      expect(await vault.verify('4271'), isTrue);
      expect(await vault.verify('4272'), isFalse);

      await vault.clear(store);
      expect(await vault.isConfigured(), isFalse);
      expect(await vault.verify('4271'), isFalse);
    });

    test('un PIN trivial ne peut pas être défini', () async {
      final PinVault vault = PinVault(store);
      expect(() => vault.setPin('1234'), throwsArgumentError);
      expect(() => vault.setPin('abcd'), throwsArgumentError);
    });
  });

  group('Réglages', () {
    late Directory directory;
    late Database db;
    late SqliteAkibaStore store;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('akiba_settings');
      db = AkibaDatabase.openEncrypted(
        p.join(directory.path, 'akiba.db'),
        keyHex: AkibaSecureKey.generateHexKey(),
      );
      store = SqliteAkibaStore(db);
    });

    tearDown(() {
      db.close();
      directory.deleteSync(recursive: true);
    });

    test('les valeurs par défaut sont sûres', () async {
      final AkibaSettings settings = AkibaSettings(store);
      await settings.load();

      expect(settings.loaded, isTrue);
      expect(settings.reduceAnimations, isFalse);
      expect(settings.pinEnabled, isFalse);
      expect(settings.raw('currency'), 'FCFA');
    });

    test('un réglage écrit revient au rechargement', () async {
      final AkibaSettings settings = AkibaSettings(store);
      await settings.load();
      await settings.setReduceAnimations(true);
      await settings.setFlag('notif_morning', true);

      final AkibaSettings reloaded = AkibaSettings(store);
      await reloaded.load();
      expect(reloaded.reduceAnimations, isTrue);
      expect(reloaded.flag('notif_morning'), isTrue);
    });
  });

  group('Rappels locaux', () {
    test('le rappel de dépenses est borné et ne révèle aucun montant', () {
      expect(expenseMessageFor(DateTime(2026, 11, 20, 16, 59)), isNull);
      final String? message = expenseMessageFor(DateTime(2026, 11, 20, 17));
      expect(message, isNotNull);
      expect(message, isNot(contains('FCFA')));
      expect(message, isNot(contains('XOF')));
      expect(expenseMessageFor(DateTime(2026, 11, 20, 20)), isNull);
    });

    test('l’heure se lit sans erreur', () {
      expect(ReminderPlanner.parseTime('07:30'), (hour: 7, minute: 30));
      expect(ReminderPlanner.parseTime('99:99'), (hour: 23, minute: 59));
      expect(ReminderPlanner.parseTime('n’importe quoi'), (hour: 0, minute: 0));
    });

    test('la plage « ne pas déranger » passe minuit', () {
      final DateTime at22 = DateTime(2026, 11, 19, 22, 30);
      final DateTime at6 = DateTime(2026, 11, 19, 6, 30);
      final DateTime at12 = DateTime(2026, 11, 19, 12, 0);

      expect(ReminderPlanner.isInDnd(at22, '21:00', '07:00'), isTrue);
      expect(ReminderPlanner.isInDnd(at6, '21:00', '07:00'), isTrue);
      expect(ReminderPlanner.isInDnd(at12, '21:00', '07:00'), isFalse);
      expect(ReminderPlanner.isInDnd(at12, '12:00', '12:00'), isFalse);
    });

    test('les fêtes couvrent la fin d’année et une période choisie', () {
      expect(ReminderPlanner.isFestive(DateTime(2026, 12, 20)), isTrue);
      expect(ReminderPlanner.isFestive(DateTime(2026, 1, 3)), isTrue);
      expect(ReminderPlanner.isFestive(DateTime(2026, 7, 4)), isFalse);
      expect(
        ReminderPlanner.isFestive(
          DateTime(2026, 7, 4),
          customStart: DateTime(2026, 7, 1),
          customEnd: DateTime(2026, 7, 10),
        ),
        isTrue,
      );
    });

    test('aucun message ne contient de montant', () {
      for (final List<String> pool in <List<String>>[
        ReminderPlanner.morningMessages,
        ReminderPlanner.noonMessages,
        ReminderPlanner.eveningMessages,
        ReminderPlanner.festiveMessages,
      ]) {
        for (final String message in pool) {
          expect(message.contains('FCFA'), isFalse);
          expect(message.contains('XOF'), isFalse);
        }
      }
      expect(
        ReminderPlanner.sanitize('Reste 12 500 FCFA', masked: true),
        'Reste •••••• FCFA',
      );
      expect(
        ReminderPlanner.sanitize('Reste 12 500 FCFA', masked: false),
        'Reste 12 500 FCFA',
      );
    });

    test('planifier respecte l’heure, la DND et le masquage', () {
      const ReminderConfig config = ReminderConfig(
        morningEnabled: true,
        noonEnabled: true,
        eveningEnabled: true,
        morningTime: '07:00',
        noonTime: '12:30',
        eveningTime: '21:00',
        dndEnabled: true,
        dndStart: '21:00',
        dndEnd: '06:00',
        festiveEnabled: true,
        festiveLabel: 'Fêtes',
        masked: true,
      );

      final List<ReminderPlan> plans = ReminderPlanner.plan(
        config,
        now: DateTime(2026, 11, 19, 6, 0),
      );

      expect(plans.map((ReminderPlan p) => p.slot), <String>['Matin', 'Midi']);
      expect(plans.first.when, DateTime(2026, 11, 19, 7, 0));
      expect(plans.every((ReminderPlan p) => p.festive == false), isTrue);
    });

    test('la période de fête remplace le rappel du soir', () {
      const ReminderConfig config = ReminderConfig(
        morningEnabled: false,
        noonEnabled: false,
        eveningEnabled: true,
        morningTime: '07:00',
        noonTime: '12:30',
        eveningTime: '20:00',
        dndEnabled: false,
        dndStart: '22:00',
        dndEnd: '06:00',
        festiveEnabled: true,
        festiveLabel: 'Fêtes de fin d’année',
        masked: false,
      );

      final List<ReminderPlan> plans = ReminderPlanner.plan(
        config,
        now: DateTime(2026, 12, 20, 10, 0),
      );

      expect(plans.single.festive, isTrue);
      expect(plans.single.title, 'Fêtes de fin d’année');
    });
  });

  group('Requête OAuth Google pour application installée', () {
    test('emploie un loopback racine et les paramètres OAuth supportés', () {
      final Uri request = GoogleOAuthConfig.authorizationUri(
        port: 49152,
        codeChallenge: 'pkce-challenge',
        state: 'csrf-state',
      );
      final Map<String, String> query = request.queryParameters;

      expect(request.origin, 'https://accounts.google.com');
      expect(request.path, '/o/oauth2/v2/auth');
      // Un identifiant vide n'est jamais envoyé (`client_id=` déclenche
      // « invalid_request ») : la clé est alors absente de la requête.
      if (GoogleOAuthConfig.clientId.isEmpty) {
        expect(query.containsKey('client_id'), isFalse);
      } else {
        expect(query['client_id'], GoogleOAuthConfig.clientId);
      }
      expect(query['redirect_uri'], 'http://127.0.0.1:49152');
      expect(query['response_type'], 'code');
      expect(
        query['scope'],
        contains('https://www.googleapis.com/auth/drive.appdata'),
      );
      expect(query['code_challenge'], 'pkce-challenge');
      expect(query['code_challenge_method'], 'S256');
      expect(query['state'], 'csrf-state');
      expect(
        query.keys,
        containsAll(<String>[
          'redirect_uri',
          'response_type',
          'scope',
          'code_challenge',
          'code_challenge_method',
          'state',
        ]),
      );
      expect(query.containsKey('include_granted_scopes'), isFalse);
      // `access_type=offline` + `prompt=consent` garantissent le jeton de
      // rafraîchissement, sans quoi la sauvegarde Drive échouerait juste après
      // une connexion pourtant réussie.
      expect(query['access_type'], 'offline');
      expect(query['prompt'], 'consent');
    });

    test('les espaces du scope partent en %20, jamais en +', () {
      final Uri request = GoogleOAuthConfig.authorizationUri(
        port: 49152,
        codeChallenge: 'pkce-challenge',
        state: 'csrf-state',
      );

      // `Uri.queryParameters` encode l'espace en « + » : Google peut refuser
      // cette forme. On vérifie la chaîne réellement envoyée.
      expect(request.query.contains('+'), isFalse);
      expect(request.query, contains('openid%20email%20'));
      expect(
        request.queryParameters['scope'],
        GoogleOAuthConfig.scopes.join(' '),
      );
      expect(
        request.queryParameters['redirect_uri'],
        GoogleOAuthConfig.redirectUri(49152),
      );
    });

    test('la redirection loopback est exactement http://127.0.0.1:port', () {
      expect(GoogleOAuthConfig.redirectUri(51234), 'http://127.0.0.1:51234');
    });

    test('les identifiants locaux sont chargés puis nettoyés', () async {
      final Directory dir = Directory.systemTemp.createTempSync('akiba_oauth');
      final File file = File(p.join(dir.path, 'google_oauth.json'));
      file.writeAsStringSync(
        jsonEncode(<String, String>{
          'AKIBA_GOOGLE_CLIENT_ID': '  123-abc.apps.googleusercontent.com \n',
          'AKIBA_GOOGLE_CLIENT_SECRET': '',
        }),
      );

      await GoogleOAuthConfig.load(devPath: file.path);

      expect(GoogleOAuthConfig.clientId, '123-abc.apps.googleusercontent.com');
      expect(GoogleOAuthConfig.isConfigured, isTrue);
      expect(GoogleOAuthConfig.clientSecret, isEmpty);

      // Un identifiant qui n'est pas un client Google n'ouvre rien.
      file.writeAsStringSync(
        jsonEncode(<String, String>{'AKIBA_GOOGLE_CLIENT_ID': 'pas-un-client'}),
      );
      await GoogleOAuthConfig.load(devPath: file.path);
      expect(GoogleOAuthConfig.isConfigured, isFalse);

      // Fichier absent : aucune exception, repli propre.
      await GoogleOAuthConfig.load(devPath: p.join(dir.path, 'absent.json'));
      dir.deleteSync(recursive: true);
    });
  });

  group('SMS mobile money', () {
    test('une sortie Flooz est reconnue', () {
      final SmsDraft? draft = SmsParser.parseOne(
        'Flooz: vous avez envoyé 5 000 FCFA au 90000000. '
        'Référence: AB12345. Frais 100 FCFA. 19/11/2026',
        now: now,
      );

      expect(draft, isNotNull);
      expect(draft!.amount, 5000);
      expect(draft.direction, SmsDirection.expense);
      expect(draft.operator, 'Flooz');
      expect(draft.reference, 'AB12345');
      expect(draft.fee, 100);
      expect(draft.occurredAt?.day, 19);
      expect(draft.isUsable, isTrue);
    });

    test('une entrée Mixx by Yas est reconnue', () {
      final SmsDraft? draft = SmsParser.parseOne(
        'Mixx by Yas : vous avez reçu un versement de 25 000 FCFA de Ama.',
        now: now,
      );

      expect(draft!.amount, 25000);
      expect(draft.direction, SmsDirection.income);
      expect(draft.operator, 'Mixx by Yas');
      expect(draft.counterpart, isNotNull);
    });

    test('l’argent de tiers est signalé', () {
      final SmsDraft? draft = SmsParser.parseOne(
        'Orabank: réception de 100 000 FCFA pour le compte de Client Ama.',
        now: now,
      );

      expect(draft!.operator, 'Orabank');
      expect(draft.isNeutral, isTrue);
    });

    test('plusieurs SMS se découpent et les textes vides sont ignorés', () {
      const String text =
          'Flooz: vous avez payé 1 500 FCFA chez le maquis.\n'
          '---\n'
          'Mixx : vous avez reçu 10 000 FCFA.\n'
          '---\n'
          'Bonjour, comment vas-tu ?';

      final List<String> messages = SmsParser.splitMessages(text);
      final List<SmsDraft> drafts = SmsParser.parse(text, now: now);

      expect(messages.length, 3);
      expect(drafts.length, 2);
      expect(drafts.first.amount, 1500);
      expect(drafts.last.direction, SmsDirection.income);
      expect(SmsParser.parseOne(''), isNull);
    });
  });

  group('Assistant local', () {
    test('une dépense catégorisée est proposée', () {
      final AiDraft? draft = AiCommandParser.parse(
        'j’ai payé 5 000 pour le transport',
        now: now,
      );

      expect(draft, isNotNull);
      expect(draft!.kind, TransactionKind.expense);
      expect(draft.amount, 5000);
      expect(draft.category, 'Transport');
      expect(draft.isComplete, isTrue);
      expect(draft.isNeutral, isFalse);
    });

    test('un revenu et un montant en « k » sont reconnus', () {
      final AiDraft? draft = AiCommandParser.parse(
        'reçu 25k de salaire hier',
        now: now,
      );

      expect(draft!.kind, TransactionKind.income);
      expect(draft.amount, 25000);
      expect(draft.category, 'Salaire');
      expect(draft.occurredAt, now.subtract(const Duration(days: 1)));
    });

    test('un transfert entre opérateurs est reconnu', () {
      final AiDraft? draft = AiCommandParser.parse(
        'transféré 10 000 de flooz vers mixx',
        now: now,
      );

      expect(draft!.kind, TransactionKind.transfer);
      expect(draft.fromBrand, 'flooz');
      expect(draft.toBrand, 'mixx');
      expect(draft.amount, 10000);
    });

    test('l’argent de tiers est marqué et reste éditable', () {
      final AiDraft? draft = AiCommandParser.parse(
        'avancé 3 000 pour un client',
        now: now,
      );

      expect(draft!.isNeutral, isTrue);
      draft.amount = 3500;
      expect(draft.amount, 3500);
    });

    test('une phrase sans montant ne produit rien', () {
      expect(AiCommandParser.parse('bonjour'), isNull);
      expect(AiCommandParser.parse('   '), isNull);
    });
  });

  group('Devises', () {
    tearDown(() => AkibaMoney.currency = 'FCFA');

    test('les quatre devises sont proposées avec leur logo', () {
      expect(AkibaCurrency.values.length, 4);
      expect(AkibaCurrency.values.map((AkibaCurrency c) => c.name), <String>[
        'FCFA',
        'Euro',
        'Dollar',
        'Yuan',
      ]);
      for (final AkibaCurrency currency in AkibaCurrency.values) {
        // Le drapeau est embarqué : aucun accès réseau pour l'afficher.
        expect(currency.assetPath, startsWith('assets/logos/currencies/'));
        expect(currency.assetPath, contains(currency.region));
        expect(currency.symbol, isNotEmpty);
      }
    });

    test('les anciennes valeurs enregistrées restent lisibles', () {
      expect(AkibaCurrency.fromStorage('FCFA'), AkibaCurrency.fcfa);
      expect(AkibaCurrency.fromStorage('XOF'), AkibaCurrency.fcfa);
      expect(AkibaCurrency.fromStorage('EUR'), AkibaCurrency.euro);
      expect(AkibaCurrency.fromStorage('Dollar'), AkibaCurrency.dollar);
      expect(AkibaCurrency.fromStorage('CNY'), AkibaCurrency.yuan);
      expect(AkibaCurrency.fromStorage(''), AkibaCurrency.fcfa);
      expect(AkibaCurrency.fromStorage('inconnu'), AkibaCurrency.fcfa);
    });

    test('le format suit la devise choisie, sans conversion', () {
      AkibaMoney.currency = AkibaCurrency.euro.symbol;
      expect(AkibaMoney.format(15000), '15\u00A0000\u00A0€');
      expect(AkibaMoney.format(15000, masked: true), '••••••\u00A0€');

      AkibaMoney.currency = AkibaCurrency.yuan.symbol;
      expect(AkibaMoney.format(-3500), '−3\u00A0500\u00A0¥');
    });
  });

  group('Créances et dettes', () {
    late Directory directory;
    late Database db;
    late SqliteAkibaStore store;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('akiba_debt');
      db = AkibaDatabase.openEncrypted(
        p.join(directory.path, 'akiba.db'),
        keyHex: AkibaSecureKey.generateHexKey(),
      );
      store = SqliteAkibaStore(db);
    });

    tearDown(() {
      db.close();
      directory.deleteSync(recursive: true);
    });

    test('le sens « on me doit » et « je dois » fait l’aller-retour', () {
      for (final DebtDirection direction in DebtDirection.values) {
        final Debt debt = Debt(
          id: 'd-${direction.name}',
          direction: direction,
          counterparty: 'Ama',
          principal: 20000,
          settledAmount: 5000,
          createdAt: now,
        );
        final Debt back = Debt.fromRow(debt.toRow());
        expect(back.direction, direction);
        expect(back.remaining, 15000);
      }
      expect(
        DebtDirection.fromStorage(DebtDirection.owedToMe.name),
        DebtDirection.owedToMe,
      );
    });

    test(
      'une créance ou une dette ne change pas le solde disponible',
      () async {
        await store.saveAccount(
          Account(
            id: 'flooz',
            name: 'Flooz',
            brand: AccountBrand.flooz,
            createdAt: now,
          ),
        );
        await store.saveTransaction(
          TransactionRecord(
            id: 'open',
            accountId: 'flooz',
            amount: 20000,
            kind: TransactionKind.opening,
            occurredAt: now,
            createdAt: now,
          ),
        );
        for (final DebtDirection direction in DebtDirection.values) {
          await store.saveDebt(
            Debt(
              id: 'debt-${direction.name}',
              direction: direction,
              counterparty: 'Ama',
              principal: 50000,
              createdAt: now,
            ),
          );
        }

        final DashboardSnapshot snapshot = await store.loadDashboard();
        expect(snapshot.balance.available, 20000);
        expect(snapshot.balance.totalAccounts, 20000);
        expect((await store.debts()).length, 2);
      },
    );
  });

  group('Sauvegarde chiffrée', () {
    late Directory directory;
    late Database db;
    late SqliteAkibaStore store;
    late BackupService service;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('akiba_backup');
      db = AkibaDatabase.openEncrypted(
        p.join(directory.path, 'akiba.db'),
        keyHex: AkibaSecureKey.generateHexKey(),
      );
      store = SqliteAkibaStore(db);
      service = BackupService.withKey(
        store,
        List<int>.generate(32, (int i) => i + 1),
      );
      await store.saveAccount(
        Account(
          id: 'flooz',
          name: 'Flooz',
          brand: AccountBrand.flooz,
          createdAt: now,
        ),
      );
      await store.saveTransaction(
        TransactionRecord(
          id: 'tx-1',
          accountId: 'flooz',
          amount: 25000,
          kind: TransactionKind.income,
          occurredAt: now,
          createdAt: now,
          category: 'Salaire',
        ),
      );
      await store.setSetting('pin_hash', 'secret-local');
      await store.setSetting('notif_morning', '1');
    });

    tearDown(() {
      db.close();
      directory.deleteSync(recursive: true);
    });

    test('l’enveloppe ne contient aucun montant en clair', () async {
      final Map<String, dynamic> envelope = await service.createEnvelope(
        deviceId: 'poste-1',
      );

      expect(envelope['cipher'], 'AES-256-GCM');
      expect(envelope['kdf'], 'device-key');
      expect(envelope['ciphertext'], isA<String>());
      // Le clair (catégorie, identifiants) n'apparaît jamais dans l'enveloppe.
      expect(jsonEncode(envelope).contains('Salaire'), isFalse);
      expect(jsonEncode(envelope).contains('flooz'), isFalse);
      expect(BackupService.metadata(envelope).transactions, 1);
    });

    test('la clé de l’appareil restitue les données', () async {
      final Map<String, dynamic> envelope = await service.createEnvelope(
        deviceId: 'poste-1',
      );
      final Map<String, dynamic> payload = await service.decryptEnvelope(
        envelope,
      );

      expect((payload['transactions'] as List<dynamic>).length, 1);
      final Map<String, dynamic> settings = Map<String, dynamic>.from(
        payload['settings'] as Map,
      );
      expect(settings['pin_hash'], isNull);
      expect(settings['notif_morning'], '1');
    });

    test(
      'restauration automatique avec le même compte Google sur nouvel appareil',
      () async {
        final BackupService freshDevice = BackupService(store);
        final GoogleAccount account = GoogleAccount.normalized(
          id: 'google-sub-stable-123',
          email: 'Paulin@Gmail.com',
        );
        final Map<String, dynamic> envelope = await freshDevice.createEnvelope(
          deviceId: 'poste-1',
          account: account,
        );
        expect(envelope['kdf'], 'PBKDF2-HMAC-SHA256');
        expect(envelope['salt'], isA<String>());

        // Aucune clé locale préexistante : la même identité et le sel de
        // l'enveloppe suffisent à retrouver la clé AES-256-GCM.
        final BackupService reinstalled = BackupService(store);
        final Map<String, dynamic> payload = await reinstalled.decryptEnvelope(
          envelope,
          account: account,
        );
        expect((payload['transactions'] as List<dynamic>).length, 1);
        expect(
          () => reinstalled.decryptEnvelope(
            envelope,
            account: GoogleAccount.fromId('autre-compte'),
          ),
          throwsA(isA<BackupException>()),
        );
        expect(
          () => reinstalled.decryptEnvelope(envelope),
          throwsA(isA<BackupException>()),
        );
      },
    );

    test('une clé d’un autre appareil est refusée', () async {
      final Map<String, dynamic> envelope = await service.createEnvelope(
        deviceId: 'poste-1',
      );
      final BackupService other = BackupService.withKey(
        store,
        List<int>.generate(32, (int i) => 200 - i),
      );

      expect(
        () => other.decryptEnvelope(envelope),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => service.decryptEnvelope(<String, dynamic>{
          'format': 'akiba-backup',
          'cipher': 'AES-256-GCM',
          'ciphertext': 'illisible',
        }),
        throwsA(isA<BackupException>()),
      );
    });

    test('un format inconnu est refusé', () async {
      expect(
        () => service.decryptEnvelope(<String, dynamic>{
          'format': 'autre',
          'cipher': 'AES-256-GCM',
        }),
        throwsA(isA<BackupException>()),
      );
    });

    test('la restauration ne duplique ni ne supprime rien', () async {
      final Map<String, dynamic> envelope = await service.createEnvelope(
        deviceId: 'poste-1',
      );

      final Map<String, int> first = await service.restore(envelope);
      final Map<String, int> second = await service.restore(envelope);

      expect(first['accounts'], 0);
      expect(first['transactions'], 0);
      expect(second['transactions'], 0);
      expect((await store.transactions()).length, 1);
    });

    test('le dépôt dans un dossier se relit et se déchiffre', () async {
      final Directory folder = Directory(
        p.join(directory.path, 'drive-synchronise'),
      );
      final Map<String, dynamic> envelope = await service.createEnvelope(
        deviceId: 'poste-1',
      );

      final File written = await service.saveToFolder(envelope, folder.path);
      expect(await written.exists(), isTrue);
      expect(written.path, endsWith('.akiba'));
      expect(await written.readAsString(), isNot(contains('Salaire')));

      final Map<String, dynamic>? reread = await service.readFolder(
        folder.path,
      );
      expect(reread, isNotNull);
      final Map<String, dynamic> payload = await service.decryptEnvelope(
        reread!,
      );
      expect((payload['accounts'] as List<dynamic>).length, 1);
    });
  });

  group('Home Lab — transport chiffré', () {
    test('l’enveloppe fait l’aller-retour avec le jeton Bearer', () async {
      final Directory directory = Directory.systemTemp.createTempSync(
        'akiba_lab',
      );
      final Database db = AkibaDatabase.openEncrypted(
        p.join(directory.path, 'akiba.db'),
        keyHex: AkibaSecureKey.generateHexKey(),
      );
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      Map<String, dynamic>? received;
      String? authorization;
      final StreamSubscription<HttpRequest> subscription = server.listen((
        HttpRequest request,
      ) async {
        authorization = request.headers.value('authorization');
        if (request.method == 'PUT') {
          received =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
        } else {
          request.response.write(jsonEncode(received ?? <String, dynamic>{}));
        }
        await request.response.close();
      });

      try {
        final BackupService service = BackupService.withKey(
          SqliteAkibaStore(db),
          List<int>.generate(32, (int i) => i + 1),
        );
        final Map<String, dynamic> envelope = await service.createEnvelope(
          deviceId: 'poste-lab',
        );
        final String url = 'http://127.0.0.1:${server.port}/akiba/backup';

        await service.putRemote(
          url: url,
          token: 'jeton-lab',
          envelope: envelope,
        );
        expect(authorization, 'Bearer jeton-lab');

        final Map<String, dynamic>? fetched = await service.fetchRemote(
          url: url,
          token: 'jeton-lab',
        );
        expect(fetched, isNotNull);
        expect(fetched!['cipher'], 'AES-256-GCM');
        expect(jsonEncode(fetched), isNot(contains('Salaire')));

        final Map<String, dynamic> payload = await service.decryptEnvelope(
          fetched,
        );
        expect(payload['settings'], isA<Map>());
      } finally {
        await subscription.cancel();
        await server.close(force: true);
        db.close();
        directory.deleteSync(recursive: true);
      }
    });
  });

  group('Clé API et modèles IA', () {
    final List<int> master = List<int>.generate(32, (int i) => i);
    final List<int> other = List<int>.generate(32, (int i) => 255 - i);

    test(
      'la clé se chiffre, se relit, et refuse une autre clé maîtresse',
      () async {
        const String secret = 'AIza-une-cle-tres-secrete-0123456789';
        final String sealed = await AiKeyVault.seal(secret, master);

        expect(sealed, isNot(contains('AIza')));
        expect(await AiKeyVault.open(sealed, master), secret);
        expect(await AiKeyVault.open(sealed, other), isNull);
        expect(await AiKeyVault.open('${sealed}x', master), isNull);
        expect(await AiKeyVault.open('illisible', master), isNull);
      },
    );

    test('la saisie de la clé est contrôlée sans réseau', () {
      expect(AiKeyVault.validate(''), isNotNull);
      expect(AiKeyVault.validate('trop-court'), isNotNull);
      expect(AiKeyVault.validate('AIza-cle avec espace 0123456789'), isNotNull);
      expect(AiKeyVault.validate('AIzaSyB-0123456789abcdefghijklmnop'), isNull);
      expect(AiKeyVault.maskedLabel, '••••••••');
    });

    test('la liste des modèles est lue et filtrée', () {
      const String body =
          '{"models":['
          '{"name":"models/gemini-2.0-flash",'
          '"displayName":"Gemini 2.0 Flash",'
          '"supportedGenerationMethods":["generateContent"]},'
          '{"name":"models/gemini-2.0-flash",'
          '"displayName":"Doublon",'
          '"supportedGenerationMethods":["generateContent"]},'
          '{"name":"models/text-embedding-004",'
          '"displayName":"Embedding",'
          '"supportedGenerationMethods":["embedContent"]}]}';
      final List<AiModel> models = AiModelCatalog.parseList(body);

      // Le doublon est ignoré : un seul identifiant par modèle.
      expect(models.length, 1);
      expect(models.first.id, 'gemini-2.0-flash');
      expect(models.first.label, 'Gemini 2.0 Flash');
      expect(models.any((AiModel m) => m.id.contains('embedding')), isFalse);
      expect(AiModelCatalog.parseList('pas du json'), isEmpty);
    });

    test('l’ordre de priorité est respecté et nettoyé', () {
      final List<AiModel> available = AiModelCatalog.seeds;
      final String stored =
          '${available.last.id},inconnu,${available.first.id}';

      final List<AiModel> selected = AiModelCatalog.selected(available, stored);
      expect(selected.length, 2);
      expect(selected.first.id, available.last.id);
      expect(selected.last.id, available.first.id);
      expect(selected.any((AiModel m) => m.id == 'inconnu'), isFalse);

      // Un identifiant retiré du catalogue (les 1.5 ne répondent plus) est
      // ignoré au lieu de bloquer un appel sur un modèle inexistant.
      expect(AiModelCatalog.selected(available, 'gemini-1.5-pro'), isEmpty);

      // Un réglage vide garde tous les modèles connus.
      expect(AiModelCatalog.selected(available, '').length, available.length);

      final String cache = AiModelCatalog.encode(available);
      expect(AiModelCatalog.decode(cache).length, available.length);
      expect(AiModelCatalog.decode('').length, available.length);
    });
  });

  group('Cascade IA et délais', () {
    const List<AiModel> models = <AiModel>[
      AiModel(id: 'm1', label: 'Un'),
      AiModel(id: 'm2', label: 'Deux'),
      AiModel(id: 'm3', label: 'Trois'),
    ];

    test('les délais suivent le type de tâche', () {
      expect(AiTask.quickEntry.seconds, inInclusiveRange(4, 6));
      expect(AiTask.smsReview.seconds, inInclusiveRange(4, 6));
      expect(AiTask.analysis.seconds, inInclusiveRange(8, 20));
      expect(AiTask.coaching.seconds, inInclusiveRange(8, 12));
    });

    test('délai puis quota : le modèle suivant prend le relais', () async {
      final List<String> calls = <String>[];
      final AkibaAiClient client = AkibaAiClient(
        models: models,
        transport:
            ({
              required String modelId,
              required String prompt,
              required Duration timeout,
            }) async {
              calls.add(modelId);
              if (modelId == 'm1') throw TimeoutException('lent');
              if (modelId == 'm2') throw const AiHttpException(429);
              return '{"amount":5000}';
            },
      );

      final AiCallResult result = await client.generate(
        task: AiTask.quickEntry,
        prompt: 'test',
      );

      expect(result.ok, isTrue);
      expect(result.modelId, 'm3');
      expect(result.attempts.length, 2);
      expect(result.attempts.first.kind, AiFailureKind.timeout);
      expect(result.attempts.last.kind, AiFailureKind.quota);
      expect(calls, <String>['m1', 'm2', 'm3']);
    });

    test('une clé refusée arrête la cascade', () async {
      final List<String> calls = <String>[];
      final AkibaAiClient client = AkibaAiClient(
        models: models,
        transport:
            ({
              required String modelId,
              required String prompt,
              required Duration timeout,
            }) async {
              calls.add(modelId);
              throw const AiHttpException(401);
            },
      );

      final AiCallResult result = await client.generate(
        task: AiTask.analysis,
        prompt: 'test',
      );

      expect(result.ok, isFalse);
      expect(result.failure, AiFailureKind.auth);
      expect(result.attempts.length, 1);
      expect(calls, <String>['m1']);
    });

    test('le plafond d’essais borne la cascade', () async {
      final AkibaAiClient client = AkibaAiClient(
        models: models,
        maxAttempts: 2,
        transport:
            ({
              required String modelId,
              required String prompt,
              required Duration timeout,
            }) async => throw const AiHttpException(503),
      );

      final AiCallResult result = await client.generate(
        task: AiTask.smsReview,
        prompt: 'test',
      );

      expect(result.ok, isFalse);
      expect(result.failure, AiFailureKind.server);
      expect(result.attempts.length, 2);
      expect(result.note, contains('Analyse locale'));
    });

    test('un modèle en échec répété passe en veille', () async {
      final DateTime fixed = DateTime(2026, 11, 20, 9);
      final List<String> calls = <String>[];
      final AkibaAiClient client = AkibaAiClient(
        models: models,
        now: () => fixed,
        transport:
            ({
              required String modelId,
              required String prompt,
              required Duration timeout,
            }) async {
              calls.add(modelId);
              if (modelId == 'm1') throw TimeoutException('lent');
              return 'ok';
            },
      );

      await client.generate(task: AiTask.quickEntry, prompt: 'a');
      await client.generate(task: AiTask.quickEntry, prompt: 'b');
      expect(client.isSleeping('m1'), isTrue);
      expect(client.chain.map((AiModel m) => m.id), isNot(contains('m1')));

      calls.clear();
      final AiCallResult third = await client.generate(
        task: AiTask.quickEntry,
        prompt: 'c',
      );
      expect(third.ok, isTrue);
      expect(calls, <String>['m2']);
      expect(third.attempts, isEmpty);
    });
  });

  group('Quota IA journalier', () {
    late Directory directory;
    late Database db;
    late AkibaSettings settings;
    DateTime clock = DateTime(2026, 11, 20, 9);

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('akiba_quota');
      db = AkibaDatabase.openEncrypted(
        p.join(directory.path, 'akiba.db'),
        keyHex: AkibaSecureKey.generateHexKey(),
      );
      settings = AkibaSettings(SqliteAkibaStore(db));
      await settings.load();
    });

    tearDown(() {
      db.close();
      directory.deleteSync(recursive: true);
    });

    test('le quota se consomme puis repart à zéro le lendemain', () async {
      await settings.set('ai_quota_per_day', '2');
      final AiQuota quota = AiQuota(settings, now: () => clock);

      expect(quota.remaining, 2);
      expect(await quota.consume(), isTrue);
      expect(await quota.consume(), isTrue);
      expect(quota.exhausted, isTrue);
      expect(await quota.consume(), isFalse);
      expect(quota.used, 2);

      // Nouveau jour civil : le compteur daté ne s'applique plus.
      clock = DateTime(2026, 11, 21, 0, 5);
      expect(quota.used, 0);
      expect(quota.remaining, 2);
      expect(await quota.consume(), isTrue);
      expect(quota.used, 1);
    });

    test('un quota à zéro interdit l’appel distant', () async {
      await settings.set('ai_quota_per_day', '0');
      final AiQuota quota = AiQuota(settings, now: () => clock);

      expect(quota.exhausted, isTrue);
      expect(await quota.consume(), isFalse);
      expect(quota.label, contains('0 / 0'));
    });
  });

  group('Créances et dettes — états et trésorerie', () {
    late Directory directory;
    late Database db;
    late SqliteAkibaStore store;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('akiba_debts');
      db = AkibaDatabase.openEncrypted(
        p.join(directory.path, 'akiba.db'),
        keyHex: AkibaSecureKey.generateHexKey(),
      );
      store = SqliteAkibaStore(db);
    });

    tearDown(() {
      db.close();
      directory.deleteSync(recursive: true);
    });

    Debt debt({
      DebtDirection direction = DebtDirection.owedToMe,
      int principal = 20000,
      int settled = 0,
      DateTime? due,
    }) => Debt(
      id: 'debt-1',
      direction: direction,
      counterparty: 'Ami',
      principal: principal,
      settledAmount: settled,
      dueDate: due,
      createdAt: now,
    );

    test('les quatre états suivent l’ordre attendu', () {
      final DateTime today = DateTime(2026, 11, 20, 18);
      final Debt ongoing = debt(due: DateTime(2026, 12, 1));
      expect(ongoing.statusAt(today), DebtStatus.ongoing);

      final Debt partial = debt(settled: 5000);
      expect(partial.statusAt(today), DebtStatus.partiallySettled);
      expect(partial.progressPercent, 25);
      expect(partial.remaining, 15000);

      final Debt settled = debt(settled: 20000);
      expect(settled.statusAt(today), DebtStatus.settled);
      expect(settled.progressPercent, 100);

      final Debt late = debt(
        settled: 5000,
        due: DateTime(2026, 11, 19, 23, 59),
      );
      expect(late.statusAt(today), DebtStatus.overdue);

      // Le jour même n'est pas encore un retard.
      final Debt sameDay = debt(due: DateTime(2026, 11, 20, 8));
      expect(sameDay.statusAt(today), DebtStatus.ongoing);
    });

    test('un emprunt reçu reste hors du solde disponible', () async {
      await store.saveAccount(
        Account(
          id: 'flooz',
          name: 'Flooz',
          brand: AccountBrand.flooz,
          createdAt: now,
        ),
      );
      await store.saveDebt(debt(direction: DebtDirection.iOwe));
      await store.saveTransaction(
        TransactionRecord(
          id: 'tx-1',
          accountId: 'flooz',
          amount: 20000,
          kind: TransactionKind.income,
          note: 'Emprunt reçu · Ami',
          isNeutral: true,
          occurredAt: now,
          createdAt: now,
        ),
      );

      final DashboardSnapshot snapshot = await store.loadDashboard();
      expect(snapshot.balance.totalAccounts, 20000);
      expect(snapshot.balance.thirdPartyHeld, 20000);
      expect(snapshot.balance.available, 0);
      expect((await store.debts()).length, 1);
    });

    test('supprimer une dette ne touche pas aux comptes', () async {
      await store.saveAccount(
        Account(
          id: 'flooz',
          name: 'Flooz',
          brand: AccountBrand.flooz,
          createdAt: now,
        ),
      );
      await store.saveTransaction(
        TransactionRecord(
          id: 'tx-1',
          accountId: 'flooz',
          amount: 10000,
          kind: TransactionKind.income,
          occurredAt: now,
          createdAt: now,
        ),
      );
      await store.saveDebt(debt());
      expect((await store.debts()).length, 1);

      await store.deleteDebt('debt-1');

      expect(await store.debts(), isEmpty);
      expect((await store.loadDashboard()).balance.available, 10000);
    });
  });
}
