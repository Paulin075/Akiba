import 'dart:typed_data';

import '../../data/akiba_store.dart';
import '../../data/models/analysis.dart';
import '../../data/models/debt.dart';
import '../../data/models/savings_pot.dart';
import '../../data/models/third_party.dart';
import '../ai/ai_client.dart';
import '../ai/ai_quota.dart';
import '../ai/ai_text.dart';
import '../ai/ai_remote.dart';
import '../format/akiba_money.dart';
import '../state/akiba_settings.dart';
import '../theme/akiba_theme.dart';

/// Période proposée pour le rapport mensuel.
enum ReportPeriod {
  currentMonth('Mois en cours', 'This month'),
  previousMonth('Mois dernier', 'Last month'),
  last30Days('30 derniers jours', 'Last 30 days');

  const ReportPeriod(this.labelFr, this.labelEn);

  final String labelFr;
  final String labelEn;

  String label(String language) => language == 'en' ? labelEn : labelFr;

  static ReportPeriod fromStorage(String? value) {
    for (final ReportPeriod period in values) {
      if (period.name == value) return period;
    }
    return ReportPeriod.currentMonth;
  }
}

/// Avis et conseils de l'assistant, intégrés au rapport et au PDF.
class ReportAdvice {
  const ReportAdvice({
    required this.headline,
    required this.tips,
    required this.engine,
    required this.language,
  });

  /// Verdict en une phrase courte.
  final String headline;

  /// Trois conseils actionnables au maximum.
  final List<String> tips;

  /// `local` ou le libellé du fournisseur IA qui a répondu.
  final String engine;

  final String language;

  bool get fromAi => engine != 'local';

  /// Lit une réponse du modèle : première ligne = verdict, suivantes =
  /// conseils. Le JSON (`{"avis": ..., "conseils": [...]}`) et le Markdown
  /// sont ramenés à ce même texte, pour que l'avis réel arrive au PDF.
  /// Renvoie `null` si la réponse n'est pas exploitable.
  static ReportAdvice? parse(
    String raw, {
    required String engine,
    required String language,
  }) {
    final List<String> lines = AiText.lines(raw);
    if (lines.isEmpty) return null;
    // Réponse en une seule phrase : on la découpe aux phrases pour garder un
    // verdict et des conseils plutôt que de tout perdre.
    final List<String> parts = lines.length > 1
        ? lines
        : _sentences(lines.first);
    if (parts.length < 2) return null;
    final String headline = parts.first.length > 160
        ? '${parts.first.substring(0, 157)}…'
        : parts.first;
    final List<String> tips = parts
        .skip(1)
        .take(3)
        .map(
          (String tip) => tip.length > 200 ? '${tip.substring(0, 197)}…' : tip,
        )
        .toList(growable: false);
    if (tips.isEmpty) return null;
    return ReportAdvice(
      headline: headline,
      tips: tips,
      engine: engine,
      language: language,
    );
  }

  /// Découpe un paragraphe en phrases (la première sert de verdict).
  static List<String> _sentences(String text) => text
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((String part) => part.trim())
      .where((String part) => part.isNotEmpty)
      .toList(growable: false);
}

/// Rapport financier d'une période, **100 % local**.
///
/// Règle AKIBA explicite : les montants du rapport et du PDF sont **toujours
/// affichés en clair**, même quand le masquage global est actif ailleurs. En
/// revanche l'isolation reste stricte : l'argent de tiers, l'épargne et les
/// créances/dettes ne sont jamais additionnés aux revenus ou aux dépenses
/// personnelles. Aucun total n'est stocké : tout est recalculé à la demande.
class MonthlyReport {
  const MonthlyReport({
    required this.from,
    required this.to,
    required this.period,
    required this.simulation,
    required this.language,
    required this.theme,
    required this.income,
    required this.expense,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.accounts,
    required this.months,
    required this.savingsPots,
    required this.thirdParties,
    required this.receivable,
    required this.payable,
    required this.reserve,
    required this.advice,
    this.profileName = '',
    this.profilePhotoBytes,
    this.generatedAt,
  });

  final DateTime from;
  final DateTime to;
  final ReportPeriod period;
  final bool simulation;
  final String language;
  final AkibaThemeId theme;

  /// Entrées personnelles de la période (argent de tiers exclu).
  final int income;

  /// Sorties personnelles de la période (épargne, virements et tiers exclus).
  final int expense;

  final List<CategoryTotal> expenseCategories;
  final List<CategoryTotal> incomeCategories;
  final List<AccountPeriodTotal> accounts;
  final List<MonthTotal> months;
  final List<SavingsPotBalance> savingsPots;
  final List<ThirdPartyBalance> thirdParties;

  /// Créances en cours (« on me doit »), dettes en cours (« je dois »).
  final int receivable;
  final int payable;

  /// Réserve de sécurité enregistrée dans les réglages.
  final int reserve;

  final ReportAdvice advice;
  final String profileName;
  final Uint8List? profilePhotoBytes;
  final DateTime? generatedAt;

  bool get isEnglish => language == 'en';

  int get net => income - expense;

  int get savingsHeld =>
      savingsPots.fold<int>(0, (int sum, SavingsPotBalance p) => sum + p.held);

  int get savingsTarget => savingsPots.fold<int>(
    0,
    (int sum, SavingsPotBalance p) => sum + p.pot.targetAmount,
  );

  int get thirdPartyHeld =>
      thirdParties.fold<int>(0, (int sum, ThirdPartyBalance p) => sum + p.held);

  bool get hasMovements => income != 0 || expense != 0;

  /// Montant **toujours en clair** : le rapport ne consulte jamais le
  /// masquage global.
  String amount(int value) => AkibaMoney.format(value);

  String get title => isEnglish ? 'Monthly report' : 'Rapport mensuel';

  String get periodLabel =>
      '${_date(from)} → ${_date(to.subtract(const Duration(days: 1)))}';

  String get simulationLabel =>
      isEnglish ? 'SIMULATION DATA' : 'DONNÉES DE SIMULATION';

  String _date(DateTime value) {
    final String day = value.day.toString().padLeft(2, '0');
    final String month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  MonthlyReport withAdvice(ReportAdvice value) => MonthlyReport(
    from: from,
    to: to,
    period: period,
    simulation: simulation,
    language: language,
    theme: theme,
    income: income,
    expense: expense,
    expenseCategories: expenseCategories,
    incomeCategories: incomeCategories,
    accounts: accounts,
    months: months,
    savingsPots: savingsPots,
    thirdParties: thirdParties,
    receivable: receivable,
    payable: payable,
    reserve: reserve,
    advice: value,
    profileName: profileName,
    profilePhotoBytes: profilePhotoBytes,
    generatedAt: generatedAt,
  );

  /// Calcule les bornes de la période demandée (fin exclusive).
  static (DateTime, DateTime) bounds(ReportPeriod period, {DateTime? now}) {
    final DateTime today = now ?? DateTime.now();
    final DateTime day = DateTime(today.year, today.month, today.day);
    return switch (period) {
      ReportPeriod.currentMonth => (
        DateTime(today.year, today.month),
        DateTime(today.year, today.month + 1),
      ),
      ReportPeriod.previousMonth => (
        DateTime(today.year, today.month - 1),
        DateTime(today.year, today.month),
      ),
      ReportPeriod.last30Days => (
        day.subtract(const Duration(days: 29)),
        day.add(const Duration(days: 1)),
      ),
    };
  }

  /// Construit le rapport depuis la base active (réelle ou simulation).
  static Future<MonthlyReport> build({
    required AkibaStore store,
    required AkibaSettings settings,
    ReportPeriod period = ReportPeriod.currentMonth,
    DateTime? now,
    String? profileName,
    Uint8List? profilePhotoBytes,
  }) async {
    final (DateTime from, DateTime to) = bounds(period, now: now);
    final List<CategoryTotal> expenses = await store.categoryTotals(
      from: from,
      to: to,
    );
    final List<CategoryTotal> incomes = await store.categoryTotals(
      from: from,
      to: to,
      expenses: false,
    );
    final List<AccountPeriodTotal> accounts = await store.accountTotals(
      from: from,
      to: to,
    );
    final List<MonthTotal> months = await store.monthlyTotals(months: 6);
    final List<SavingsPotBalance> pots = await store.savingsBalances();
    final List<ThirdPartyBalance> parties = await store.thirdPartyBalances();
    final List<Debt> debts = await store.debts();
    final int reserve = await store.settingInt('reserve_securite');
    final int income = incomes.fold<int>(
      0,
      (int s, CategoryTotal c) => s + c.amount,
    );
    final int expense = expenses.fold<int>(
      0,
      (int s, CategoryTotal c) => s + c.amount,
    );
    int receivable = 0;
    int payable = 0;
    for (final Debt debt in debts) {
      if (debt.direction == DebtDirection.owedToMe) {
        receivable += debt.remaining;
      } else {
        payable += debt.remaining;
      }
    }

    final String language = settings.language;
    final MonthlyReport base = MonthlyReport(
      from: from,
      to: to,
      period: period,
      simulation: settings.simulationMode,
      language: language,
      theme: settings.themeId,
      income: income,
      expense: expense,
      expenseCategories: expenses,
      incomeCategories: incomes,
      accounts: accounts,
      months: months,
      savingsPots: pots,
      thirdParties: parties,
      receivable: receivable,
      payable: payable,
      reserve: reserve,
      advice: ReportAdvisor.localAdvice(
        income: income,
        expense: expense,
        categories: expenses,
        savingsHeld: pots.fold<int>(
          0,
          (int s, SavingsPotBalance p) => s + p.held,
        ),
        thirdPartyHeld: parties.fold<int>(
          0,
          (int s, ThirdPartyBalance p) => s + p.held,
        ),
        payable: payable,
        language: language,
      ),
      profileName:
          profileName ??
          <String>[
            settings.firstName.trim(),
            settings.lastName.trim(),
          ].where((String part) => part.isNotEmpty).join(' '),
      profilePhotoBytes: profilePhotoBytes,
      generatedAt: now ?? DateTime.now(),
    );
    return base;
  }
}

/// Analyse locale déterministe, puis enrichissement IA **optionnel**.
class ReportAdvisor {
  const ReportAdvisor({this.transportOverride, this.now});

  final AiTransport? transportOverride;
  final DateTime Function()? now;

  /// Trois conseils locaux, sans réseau : même données, même résultat.
  static ReportAdvice localAdvice({
    required int income,
    required int expense,
    required List<CategoryTotal> categories,
    required int savingsHeld,
    required int thirdPartyHeld,
    required int payable,
    required String language,
  }) {
    final bool en = language == 'en';
    final int net = income - expense;
    final List<CategoryTotal> sorted = List<CategoryTotal>.of(
      categories,
    )..sort((CategoryTotal a, CategoryTotal b) => b.amount.compareTo(a.amount));
    final CategoryTotal? top = sorted.isEmpty ? null : sorted.first;
    final List<String> tips = <String>[];

    if (income == 0 && expense == 0) {
      return ReportAdvice(
        headline: en
            ? 'A first month, a first base'
            : 'Premier mois, première base',
        tips: en
            ? <String>[
                'Record at least one income and one expense to see real trends.',
                'Set a small weekly savings target you can keep.',
                'Check this report again at the end of the month.',
              ]
            : <String>[
                'Enregistrez au moins une entrée et une sortie pour voir de vraies tendances.',
                'Fixez un petit objectif d’épargne hebdomadaire tenable.',
                'Relisez ce rapport à la fin du mois.',
              ],
        engine: 'local',
        language: language,
      );
    }

    if (top != null) {
      tips.add(
        en
            ? 'Your biggest category is ${top.label} (${AkibaMoney.format(top.amount)}): cap it next month.'
            : 'Votre première catégorie est ${top.label} (${AkibaMoney.format(top.amount)}) : plafonnez-la le mois prochain.',
      );
    }
    if (net < 0) {
      tips.add(
        en
            ? 'Spending exceeded income by ${AkibaMoney.format(-net)}: cut one non-essential expense first.'
            : 'Les sorties dépassent les entrées de ${AkibaMoney.format(-net)} : coupez d’abord une dépense non essentielle.',
      );
    } else {
      tips.add(
        en
            ? 'You kept ${AkibaMoney.format(net)}: send part of it to the vault before spending it.'
            : 'Vous avez gardé ${AkibaMoney.format(net)} : versez une part au coffre avant de la dépenser.',
      );
    }
    if (payable > 0) {
      tips.add(
        en
            ? 'You still owe ${AkibaMoney.format(payable)}: clear the closest due date first.'
            : 'Vous devez encore ${AkibaMoney.format(payable)} : réglez d’abord l’échéance la plus proche.',
      );
    } else if (thirdPartyHeld > 0) {
      tips.add(
        en
            ? '${AkibaMoney.format(thirdPartyHeld)} of third-party money is isolated: it is not your income.'
            : '${AkibaMoney.format(thirdPartyHeld)} d’argent de tiers est isolé : ce n’est pas votre revenu.',
      );
    } else if (savingsHeld == 0) {
      tips.add(
        en
            ? 'Your vault is empty: start with a small automatic deposit.'
            : 'Votre coffre est vide : commencez par un petit versement régulier.',
      );
    } else {
      tips.add(
        en
            ? 'Your vault holds ${AkibaMoney.format(savingsHeld)}: keep the same pace next month.'
            : 'Votre coffre contient ${AkibaMoney.format(savingsHeld)} : gardez le même rythme le mois prochain.',
      );
    }
    while (tips.length < 3) {
      tips.add(
        en
            ? 'Review this report once a month, not once a day.'
            : 'Relisez ce rapport une fois par mois, pas une fois par jour.',
      );
    }

    return ReportAdvice(
      headline: net < 0
          ? (en
                ? 'The month cost more than it earned'
                : 'Le mois a coûté plus qu’il n’a rapporté')
          : (en ? 'A month in the green' : 'Un mois dans le vert'),
      tips: tips.take(3).toList(growable: false),
      engine: 'local',
      language: language,
    );
  }

  /// Demande un avis à l'IA configurée ; en cas d'absence, de quota atteint,
  /// d'erreur réseau ou de réponse illisible, le rapport local est renvoyé tel
  /// quel (aucune exception visible).
  Future<MonthlyReport> enrich(
    MonthlyReport report,
    AkibaSettings settings,
  ) async {
    if (!settings.aiRemoteEnabled) return report;
    final AiRemoteResolution resolution = await resolveAiRemote(
      settings,
      // Le rapport affiche les montants par règle : l'analyse porte sur eux.
      masked: false,
    );
    final AiRemoteSetup? setup = resolution.setup;
    if (setup == null) return report;
    if (!await AiQuota(settings, now: now).consume()) return report;
    final AkibaAiClient client = AkibaAiClient(
      models: setup.models,
      transport: transportOverride ?? setup.transport,
      maxAttempts: settings.aiMaxAttempts,
    );
    final AiCallResult result = await client.generate(
      task: AiTask.analysis,
      prompt: _prompt(report),
    );
    if (!result.ok || result.text == null) return report;
    final ReportAdvice? advice = ReportAdvice.parse(
      result.text!,
      engine: setup.provider.label,
      language: report.language,
    );
    return advice == null ? report : report.withAdvice(advice);
  }

  String _prompt(MonthlyReport report) {
    final bool en = report.isEnglish;
    final StringBuffer buffer = StringBuffer();
    buffer.writeln(
      en
          ? 'You are AKIBA’s careful financial coach. Analyse this month and answer in English.'
          : 'Tu es le conseiller financier prudent d’AKIBA. Analyse ce mois et réponds en français.',
    );
    buffer.writeln(
      en
          ? 'Income: ${report.amount(report.income)}; expenses: ${report.amount(report.expense)}; net: ${report.amount(report.net)}.'
          : 'Entrées : ${report.amount(report.income)} ; sorties : ${report.amount(report.expense)} ; solde : ${report.amount(report.net)}.',
    );
    final String categories = report.expenseCategories
        .take(4)
        .map((CategoryTotal c) => '${c.label} ${report.amount(c.amount)}')
        .join(', ');
    if (categories.isNotEmpty) {
      buffer.writeln(
        en
            ? 'Top expenses: $categories.'
            : 'Principales sorties : $categories.',
      );
    }
    buffer.writeln(
      en
          ? 'Savings vault: ${report.amount(report.savingsHeld)}; money owed to you: ${report.amount(report.receivable)}; money you owe: ${report.amount(report.payable)}; third-party money held (never yours): ${report.amount(report.thirdPartyHeld)}.'
          : 'Coffre épargne : ${report.amount(report.savingsHeld)} ; créances : ${report.amount(report.receivable)} ; dettes : ${report.amount(report.payable)} ; argent de tiers détenu (jamais le vôtre) : ${report.amount(report.thirdPartyHeld)}.',
    );
    buffer.writeln(
      en
          ? 'Reply only with a JSON object, no text around it: {"avis": "verdict of 10 words max", "conseils": ["actionable tip 1", "actionable tip 2", "actionable tip 3"]}. Tips are concrete and kind; no amount in the verdict.'
          : 'Réponds uniquement par un objet JSON, sans texte autour : {"avis": "verdict de 10 mots maximum", "conseils": ["conseil concret 1", "conseil concret 2", "conseil concret 3"]}. Les conseils sont concrets et bienveillants ; aucun montant dans le verdict.',
    );
    return buffer.toString();
  }
}
