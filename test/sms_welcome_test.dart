import 'dart:io';

import 'package:akiba/core/database/akiba_database.dart';
import 'package:akiba/core/database/akiba_secure_key.dart';
import 'package:akiba/core/notifications/app_notifications.dart';
import 'package:akiba/core/sms/sms_entry_intent.dart';
import 'package:akiba/core/sms/sms_parser.dart';
import 'package:akiba/core/state/akiba_data_revision.dart';
import 'package:akiba/core/state/akiba_l10n.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/core/theme/akiba_theme.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:akiba/data/sqlite_akiba_store.dart';
import 'package:akiba/features/quick_entry/quick_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Détection SMS (mobil-money et banque), préremplissage de la fiche et
/// notification de bienvenue.
void main() {
  group('Détection SMS bancaire', () {
    test('un dépôt Orabank devient une entrée préremplie', () {
      const String body =
          'Orabank: Depot de 150 000 FCFA sur votre compte 001234 '
          'le 24/11/2026. Reference OR7788.';
      expect(SmsDetector.isFinancialSms(body), isTrue);
      final SmsDraft draft = SmsParser.parseOne(body)!;
      expect(draft.amount, 150000);
      expect(draft.direction, SmsDirection.income);
      expect(draft.operator, 'Orabank');

      final SmsEntryIntent intent = SmsEntryIntent.fromDraft(draft)!;
      expect(intent.income, isTrue);
      expect(intent.amount, 150000);
      expect(intent.brandName, 'orabank');
      expect(intent.note, contains('Orabank'));
      expect(intent.reference, 'OR7788');
    });

    test('un retrait / paiement Orabank devient une sortie', () {
      const String body =
          'Orabank: Debit de 12 500 FCFA - PAIEMENT CARTE LE 24/11.';
      expect(SmsDetector.isFinancialSms(body), isTrue);
      final SmsDraft draft = SmsParser.parseOne(body)!;
      expect(draft.direction, SmsDirection.expense);
      final SmsEntryIntent intent = SmsEntryIntent.fromDraft(draft)!;
      expect(intent.income, isFalse);
      expect(intent.amount, 12500);
      expect(intent.brandName, 'orabank');
    });

    test('une banque non nommée reste une banque générique', () {
      const String body =
          'Bank of Africa: Virement recu de 40 000 FCFA en votre faveur.';
      final SmsDraft draft = SmsParser.parseOne(body)!;
      expect(draft.operator, 'Banque');
      expect(draft.direction, SmsDirection.income);
      final SmsEntryIntent intent = SmsEntryIntent.fromDraft(draft)!;
      expect(intent.brandName, isNull);
      expect(intent.income, isTrue);
    });

    test('« F CFA » espacé est reconnu', () {
      final SmsDraft? draft = SmsParser.parseOne(
        'Orabank: credit de 5 000 F CFA sur votre compte.',
      );
      expect(draft, isNotNull);
      expect(draft!.amount, 5000);
      expect(draft.direction, SmsDirection.income);
    });

    test('Flooz et Mixx by Yas gardent leur support', () {
      final SmsDraft flooz = SmsParser.parseOne(
        'Flooz: Vous avez recu 25000 FCFA de KOFFI Ama.',
      )!;
      expect(SmsEntryIntent.fromDraft(flooz)!.brandName, 'flooz');
      expect(SmsEntryIntent.fromDraft(flooz)!.income, isTrue);

      final SmsDraft mixx = SmsParser.parseOne(
        'Mixx by Yas: Paiement de 3500 FCFA effectue chez ALIMENTATION.',
      )!;
      expect(SmsEntryIntent.fromDraft(mixx)!.brandName, 'mixxByYas');
      expect(SmsEntryIntent.fromDraft(mixx)!.income, isFalse);
    });

    test('un message non financier ou sans montant est ignoré', () {
      expect(
        SmsDetector.isFinancialSms('Mixx by Yas vous souhaite une bonne fête.'),
        isFalse,
      );
      expect(
        SmsDetector.isFinancialSms('Bonjour, on se voit demain à midi.'),
        isFalse,
      );
      expect(
        SmsParser.parseOne('Orabank: votre relevé est disponible.'),
        isNull,
      );
    });
  });

  group('Notification de bienvenue', () {
    late List<String> sent;

    setUp(() {
      sent = <String>[];
      AppNotifications.senderOverride = (String title, String body) async {
        sent.add('$title|$body');
        return true;
      };
    });

    tearDown(() {
      AppNotifications.senderOverride = null;
      AppNotifications.permissionCheckOverride = null;
    });

    test('rien n’est envoyé quand le système refuse', () async {
      AppNotifications.permissionCheckOverride = () async => false;
      final AkibaSettings settings = AkibaSettings(const EmptyAkibaStore());
      await settings.load();
      await settings.setFlag('permission_notifications', true);
      final bool shown = await AppNotifications.welcome(settings);
      expect(shown, isFalse);
      expect(sent, isEmpty);
    });

    test('la permission accordée déclenche un message sans montant', () async {
      AppNotifications.permissionCheckOverride = () async => true;
      final AkibaSettings settings = AkibaSettings(const EmptyAkibaStore());
      await settings.load();
      final bool shown = await AppNotifications.welcome(settings);
      expect(shown, isTrue);
      expect(sent, hasLength(1));
      expect(sent.single, contains('Bienvenue dans AKIBA'));
      expect(sent.single, isNot(contains('FCFA')));
      expect(RegExp(r'\d').hasMatch(sent.single), isFalse);
    });

    test('le message suit la langue choisie', () async {
      AppNotifications.permissionCheckOverride = () async => true;
      final AkibaSettings settings = AkibaSettings(const EmptyAkibaStore());
      await settings.load();
      await settings.setLanguage('en');
      await AppNotifications.welcome(settings);
      expect(sent.single, contains('Welcome to AKIBA'));
      await settings.setLanguage('fr');
      AkibaL10n.setLanguage('fr');
    });
  });

  testWidgets(
    'la fiche SMS s’ouvre préremplie et n’écrit rien avant confirmation',
    (WidgetTester tester) async {
      final Directory directory = Directory.systemTemp.createTempSync(
        'akiba_sms_ui',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final Database db = AkibaDatabase.openEncrypted(
        p.join(directory.path, 'akiba.db'),
        keyHex: AkibaSecureKey.generateHexKey(),
      );
      addTearDown(db.close);
      final SqliteAkibaStore store = SqliteAkibaStore(db);
      await store.ensureDefaultAccounts();
      final AkibaDataRevision revision = AkibaDataRevision();
      addTearDown(revision.dispose);
      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const String body =
          'Orabank: Depot de 150 000 FCFA sur votre compte 001234.';
      final SmsEntryIntent intent = SmsEntryIntent.fromDraft(
        SmsParser.parseOne(body)!,
      )!;

      await tester.pumpWidget(
        MaterialApp(
          theme: AkibaTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: TextButton(
                  onPressed: () => openQuickEntry(
                    context,
                    store: store,
                    revision: revision,
                    mode: QuickEntryMode.income,
                    prefill: intent,
                  ),
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      expect(
        find.text('Prérempli depuis un SMS · vérifiez puis confirmez.'),
        findsOneWidget,
      );
      expect(find.text('150000'), findsOneWidget);
      // Aucune écriture : la base reste vide avant le bouton d'enregistrement.
      expect(await store.transactions(), isEmpty);

      await tester.ensureVisible(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(await store.transactions(), hasLength(1));
      final List<dynamic> rows = await store.transactions();
      expect(rows.single.amount, 150000);
      expect(tester.takeException(), isNull);
    },
  );
}
