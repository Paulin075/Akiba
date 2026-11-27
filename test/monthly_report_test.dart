import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:akiba/core/database/akiba_database.dart';
import 'package:akiba/core/database/akiba_secure_key.dart';
import 'package:akiba/core/format/akiba_money.dart';
import 'package:akiba/core/report/monthly_report.dart';
import 'package:akiba/core/report/report_pdf.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/core/theme/akiba_theme.dart';
import 'package:akiba/data/models/account.dart';
import 'package:akiba/data/models/analysis.dart';
import 'package:akiba/data/models/savings_pot.dart';
import 'package:akiba/data/models/third_party.dart';
import 'package:akiba/data/models/transaction_record.dart';
import 'package:akiba/data/sqlite_akiba_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory directory;
  late Database db;
  late SqliteAkibaStore store;
  late AkibaSettings settings;
  late Account account;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('akiba_report');
    db = AkibaDatabase.openEncrypted(
      p.join(directory.path, 'akiba.db'),
      keyHex: AkibaSecureKey.generateHexKey(),
    );
    store = SqliteAkibaStore(db);
    await store.ensureDefaultAccounts();
    account = (await store.accounts()).first;
    settings = AkibaSettings(store);
    await settings.load();

    final DateTime now = DateTime.now();
    await store.saveTransaction(
      TransactionRecord(
        id: 'tx-income',
        accountId: account.id,
        amount: 25000,
        kind: TransactionKind.income,
        category: 'Salaire',
        occurredAt: now,
        createdAt: now,
      ),
    );
    await store.saveTransaction(
      TransactionRecord(
        id: 'tx-expense',
        accountId: account.id,
        amount: -12000,
        kind: TransactionKind.expense,
        category: 'Alimentation',
        occurredAt: now,
        createdAt: now,
      ),
    );
    // Argent de tiers : ni revenu, ni dépense personnelle.
    final ThirdParty party = ThirdParty(
      id: 'tp-1',
      name: 'Client Ama',
      createdAt: now,
    );
    await store.saveThirdParty(party);
    await store.saveTransaction(
      TransactionRecord(
        id: 'tx-neutral',
        accountId: account.id,
        amount: 50000,
        kind: TransactionKind.income,
        isNeutral: true,
        thirdPartyId: party.id,
        occurredAt: now,
        createdAt: now,
      ),
    );
    // Épargne : exclue du budget, comptée dans le coffre.
    final SavingsPot pot = SavingsPot(
      id: 'pot-1',
      name: 'Voyage',
      kind: SavingsKind.free,
      targetAmount: 200000,
      createdAt: now,
    );
    await store.saveSavingsPot(pot);
    await store.saveTransaction(
      TransactionRecord(
        id: 'tx-savings',
        accountId: account.id,
        amount: -5000,
        kind: TransactionKind.savings,
        savingsPotId: pot.id,
        occurredAt: now,
        createdAt: now,
      ),
    );
  });

  tearDown(() {
    db.close();
    directory.deleteSync(recursive: true);
  });

  test(
    'les montants restent en clair et l’argent de tiers est isolé',
    () async {
      final MonthlyReport report = await MonthlyReport.build(
        store: store,
        settings: settings,
      );
      expect(report.income, 25000);
      expect(report.expense, 12000);
      expect(report.net, 13000);
      expect(report.savingsHeld, 5000);
      expect(report.thirdPartyHeld, 50000);
      expect(report.expenseCategories.single.label, 'Alimentation');
      expect(report.expenseCategories.single.amount, 12000);

      // Aucun masquage n'entre dans le rapport : les montants sont lisibles.
      expect(report.amount(report.income), AkibaMoney.format(25000));
      expect(report.amount(report.income), isNot(contains('••••')));
      expect(RegExp(r'25').hasMatch(report.amount(report.income)), isTrue);
    },
  );

  test('les bornes de période sont exactes', () {
    final DateTime now = DateTime(2026, 3, 15, 10);
    final (DateTime currentFrom, DateTime currentTo) = MonthlyReport.bounds(
      ReportPeriod.currentMonth,
      now: now,
    );
    expect(currentFrom, DateTime(2026, 3));
    expect(currentTo, DateTime(2026, 4));

    final (DateTime lastFrom, DateTime lastTo) = MonthlyReport.bounds(
      ReportPeriod.previousMonth,
      now: now,
    );
    expect(lastFrom, DateTime(2026, 2));
    expect(lastTo, DateTime(2026, 3));

    final (DateTime daysFrom, DateTime daysTo) = MonthlyReport.bounds(
      ReportPeriod.last30Days,
      now: now,
    );
    expect(daysTo.difference(daysFrom).inDays, 30);
  });

  test('avis local déterministe en français et en anglais', () {
    final ReportAdvice fr = ReportAdvisor.localAdvice(
      income: 25000,
      expense: 12000,
      categories: const <CategoryTotal>[],
      savingsHeld: 5000,
      thirdPartyHeld: 50000,
      payable: 0,
      language: 'fr',
    );
    expect(fr.engine, 'local');
    expect(fr.tips, hasLength(3));
    expect(fr.tips.join(' '), contains('argent de tiers'));
    final ReportAdvice en = ReportAdvisor.localAdvice(
      income: 25000,
      expense: 12000,
      categories: const <CategoryTotal>[],
      savingsHeld: 5000,
      thirdPartyHeld: 50000,
      payable: 0,
      language: 'en',
    );
    expect(en.tips.join(' ').toLowerCase(), contains('third-party'));
  });

  test(
    'le PDF inclut le rapport, les montants, le thème et l’avis local',
    () async {
      await settings.setThemeId(AkibaThemeId.or);
      final MonthlyReport report = await MonthlyReport.build(
        store: store,
        settings: settings,
      );
      final Uint8List bytes = await ReportPdfBuilder(
        logoBytes: Uint8List(0),
      ).build(report);
      final String raw = latin1.decode(bytes, allowInvalid: true);

      expect(raw.startsWith('%PDF'), isTrue);
      expect(raw, contains('AKIBA'));
      // Le PDF écrit chaque mot séparément : on vérifie les mots du titre.
      expect(raw, contains('Rapport'));
      expect(raw, contains('mensuel'));
      expect(raw, contains('25'));
      expect(raw, contains('FCFA'));
      expect(raw, contains('Alimentation'));
      expect(raw, contains('ARGENT'));
      expect(raw, contains('TIERS'));
      expect(raw, contains('AVIS'));
      expect(raw, isNot(contains('••••')));
      expect(report.theme, AkibaThemeId.or);

      // La couleur du thème actif est bien celle injectée dans le document.
      final PdfColor accent = ReportPdfBuilder.pdfColorFor(
        AkibaThemeId.or.palette.terracotta,
      );
      final Color expected = AkibaThemeId.or.palette.terracotta;
      expect(accent.red, closeTo(expected.r, 0.01));
      expect(accent.green, closeTo(expected.g, 0.01));
      expect(accent.blue, closeTo(expected.b, 0.01));
    },
  );

  test('le PDF inclut le nom complet et la photo de profil', () async {
    final Uint8List avatar = File('assets/brand/cochon.png').readAsBytesSync();
    await settings.set('first_name', 'Ama');
    await settings.set('last_name', 'Koffi');
    final MonthlyReport report = await MonthlyReport.build(
      store: store,
      settings: settings,
      profilePhotoBytes: avatar,
    );
    expect(report.profileName, 'Ama Koffi');
    final Uint8List bytes = await ReportPdfBuilder(
      logoBytes: Uint8List(0),
    ).build(report);
    final String raw = latin1.decode(bytes, allowInvalid: true);
    // PDF dessine les mots de police séparément, comme les autres assertions.
    expect(raw, contains('(Ama)'));
    expect(raw, contains('(Koffi)'));
    // Le logo de test est désactivé : cet objet XObject est l'avatar fourni.
    expect(raw, contains('/XObject<</I'));
  });

  test('langue anglaise, simulation et avis IA intégrés au PDF', () async {
    await settings.setLanguage('en');
    await settings.setFlag('simulation_mode', true);
    await settings.setFlag('ai_remote_enabled', true);
    await settings.set('ai_provider', 'ollama');

    MonthlyReport report = await MonthlyReport.build(
      store: store,
      settings: settings,
    );
    expect(report.language, 'en');
    expect(report.simulation, isTrue);
    expect(report.title, 'Monthly report');

    report = await ReportAdvisor(
      transportOverride:
          ({
            required String modelId,
            required String prompt,
            required Duration timeout,
          }) async =>
              'A controlled month\nCap food spending\nMove part of the surplus to the vault\nClear the nearest debt',
    ).enrich(report, settings);

    expect(report.advice.fromAi, isTrue);
    expect(report.advice.engine, 'Home Lab / Ollama');
    expect(report.advice.headline, 'A controlled month');
    expect(report.advice.tips, hasLength(3));

    final Uint8List bytes = await ReportPdfBuilder(
      logoBytes: Uint8List(0),
    ).build(report);
    final String raw = latin1.decode(bytes, allowInvalid: true);
    expect(raw, contains('Monthly'));
    expect(raw, contains('SIMULATION'));
    expect(raw, contains('controlled'));
    expect(raw, contains('Cap'));
    expect(raw, contains('spending'));
    await settings.setLanguage('fr');
  });

  test('une réponse JSON du modèle arrive telle quelle dans le PDF', () async {
    await settings.setFlag('ai_remote_enabled', true);
    await settings.set('ai_provider', 'ollama');
    final MonthlyReport base = await MonthlyReport.build(
      store: store,
      settings: settings,
    );
    final MonthlyReport enriched = await ReportAdvisor(
      transportOverride:
          ({
            required String modelId,
            required String prompt,
            required Duration timeout,
          }) async =>
              '{"avis": "Un mois sous contrôle", "conseils": ["Plafonnez '
              'l’alimentation", "Versez au coffre avant de dépenser", '
              '"Réglez la dette la plus proche"]}',
    ).enrich(base, settings);

    expect(enriched.advice.fromAi, isTrue);
    expect(enriched.advice.headline, 'Un mois sous contrôle');
    expect(enriched.advice.tips, hasLength(3));
    expect(enriched.advice.tips.first, contains('Plafonnez'));

    final Uint8List bytes = await ReportPdfBuilder(
      logoBytes: Uint8List(0),
    ).build(enriched);
    final String raw = latin1.decode(bytes, allowInvalid: true);
    expect(raw, contains('contrôle'));
    expect(raw, contains('Plafonnez'));
  });

  test('sans IA disponible, le rapport garde son avis local', () async {
    final MonthlyReport base = await MonthlyReport.build(
      store: store,
      settings: settings,
    );
    final MonthlyReport enriched = await const ReportAdvisor().enrich(
      base,
      settings,
    );
    expect(enriched.advice.fromAi, isFalse);
    expect(enriched.advice.engine, 'local');
    expect(enriched.advice.tips, hasLength(3));
  });
}
