import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/analysis.dart';
import '../../data/models/savings_pot.dart';
import '../../data/models/third_party.dart';
import '../theme/akiba_colors.dart';
import 'monthly_report.dart';

/// Construit le PDF du rapport mensuel, **entièrement hors ligne**.
///
/// Mise en page demandée : logo AKIBA en haut, puis les indicateurs et le
/// détail de la période, puis vers le bas les graphiques récapitulatifs et
/// l'avis/conseils de l'assistant. La langue et la palette du thème actif sont
/// appliquées au document. Les montants sont toujours écrits en clair.
class ReportPdfBuilder {
  const ReportPdfBuilder({this.logoBytes});

  /// Logo imposé (tests) ; sinon le logo embarqué du thème est chargé.
  final Uint8List? logoBytes;

  static const String fontName = 'Helvetica';

  /// Nom de fichier proposé au partage.
  static String fileName(MonthlyReport report) =>
      'akiba_rapport_${report.from.year}-'
      '${report.from.month.toString().padLeft(2, '0')}.pdf';

  static String subject(MonthlyReport report) =>
      '${report.title} · ${report.periodLabel}';

  /// Corps de message pour Email / WhatsApp (aucun secret, montants du rapport).
  static String shareBody(MonthlyReport report) {
    final bool en = report.isEnglish;
    final StringBuffer buffer = StringBuffer()
      ..writeln(
        en
            ? 'AKIBA ${report.title.toLowerCase()} — ${report.periodLabel}'
            : 'AKIBA — ${report.title.toLowerCase()} · ${report.periodLabel}',
      )
      ..writeln(
        en
            ? 'Income: ${report.amount(report.income)} | Expenses: ${report.amount(report.expense)} | Net: ${report.amount(report.net)}'
            : 'Entrées : ${report.amount(report.income)} | Sorties : ${report.amount(report.expense)} | Solde : ${report.amount(report.net)}',
      )
      ..writeln(
        en
            ? 'Verdict: ${report.advice.headline}'
            : 'Avis : ${report.advice.headline}',
      );
    if (report.simulation) {
      buffer.writeln(
        en
            ? 'Simulation data (local trial).'
            : 'Données de simulation (essai local).',
      );
    }
    buffer.writeln(
      en
          ? 'Generated locally by AKIBA. The PDF is attached.'
          : 'Généré localement par AKIBA. Le PDF est joint.',
    );
    return buffer.toString();
  }

  Future<Uint8List> build(MonthlyReport report) async {
    final AkibaColors palette = report.theme.palette;
    final PdfColor background = _pdfColor(palette.background);
    final PdfColor surface = _pdfColor(palette.surface);
    final PdfColor ink = _pdfColor(palette.textPrimary);
    final PdfColor muted = _pdfColor(palette.textMuted);
    final PdfColor accent = _pdfColor(palette.terracotta);
    final PdfColor accentSoft = _pdfColor(palette.terracottaDeep);
    final PdfColor ochre = _pdfColor(palette.ochre);
    final PdfColor success = _pdfColor(palette.success);
    final PdfColor warning = _pdfColor(palette.warning);
    final bool en = report.isEnglish;

    final Uint8List? logo = logoBytes ?? await _loadLogo(palette.isDark);
    final pw.MemoryImage? logoImage = (logo == null || logo.isEmpty)
        ? null
        : pw.MemoryImage(logo);
    final Uint8List? avatar = report.profilePhotoBytes;
    final pw.MemoryImage? avatarImage = avatar == null || avatar.isEmpty
        ? null
        : pw.MemoryImage(avatar);
    final List<String> nameParts = report.profileName
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    final String initials = nameParts.isEmpty
        ? 'A'
        : nameParts.take(2).map((String part) => part[0].toUpperCase()).join();

    final pw.ThemeData theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
    );

    String t(String fr, String enText) => en ? enText : fr;

    pw.Widget card({
      required pw.Widget child,
      PdfColor? color,
      PdfColor? border,
      double padding = 12,
    }) => pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(padding),
      decoration: pw.BoxDecoration(
        color: color ?? surface,
        borderRadius: pw.BorderRadius.circular(8),
        border: border == null
            ? null
            : pw.Border.all(color: border, width: 0.8),
      ),
      child: child,
    );

    pw.Widget sectionTitle(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6, top: 4),
      child: pw.Text(
        _safe(text.toUpperCase()),
        style: pw.TextStyle(
          color: muted,
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );

    pw.Widget kpi(String label, String value, PdfColor color) => pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: surface,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: color, width: 0.7),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                color: muted,
                fontSize: 7.5,
                letterSpacing: 0.6,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              _safe(value),
              style: pw.TextStyle(
                color: ink,
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );

    pw.Widget detailRow(String label, String value, {PdfColor? valueColor}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Text(
                  _safe(label),
                  style: pw.TextStyle(color: ink, fontSize: 9.5),
                ),
              ),
              pw.Text(
                _safe(value),
                style: pw.TextStyle(
                  color: valueColor ?? ink,
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        );

    pw.Widget bar(
      MonthTotal month, {
      required bool income,
      required double max,
    }) {
      final int value = income ? month.income : month.expense;
      final double ratio = max <= 0 ? 0 : (value / max).clamp(0.0, 1.0);
      return pw.Container(
        height: 7,
        width: 300 * ratio + 1,
        decoration: pw.BoxDecoration(
          color: income ? success : accent,
          borderRadius: pw.BorderRadius.circular(3),
        ),
      );
    }

    final double maxMonth = report.months.fold<double>(0, (
      double max,
      MonthTotal m,
    ) {
      final int value = m.income > m.expense ? m.income : m.expense;
      return value > max ? value.toDouble() : max;
    });

    final List<CategoryTotal> topExpenses = report.expenseCategories
        .take(6)
        .toList(growable: false);
    final List<AccountPeriodTotal> activeAccounts = report.accounts
        .where((AccountPeriodTotal a) => !a.isEmpty)
        .toList(growable: false);

    final pw.Document document = pw.Document(
      compress: false,
      title: '${report.title} · ${report.periodLabel}',
      author: 'AKIBA',
      creator: 'AKIBA',
      subject: subject(report),
    );

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(34, 34, 34, 30),
          theme: theme,
          buildBackground: (pw.Context context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: background),
          ),
        ),
        header: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: <pw.Widget>[
                if (logoImage != null)
                  pw.Container(
                    width: 46,
                    height: 46,
                    padding: const pw.EdgeInsets.all(4),
                    decoration: pw.BoxDecoration(
                      color: surface,
                      borderRadius: pw.BorderRadius.circular(10),
                    ),
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  ),
                pw.SizedBox(width: 10),
                ...<pw.Widget>[
                  pw.ClipOval(
                    child: avatarImage == null
                        ? pw.Container(
                            width: 38,
                            height: 38,
                            alignment: pw.Alignment.center,
                            color: accentSoft,
                            child: pw.Text(
                              _safe(initials),
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          )
                        : pw.Image(
                            avatarImage,
                            width: 38,
                            height: 38,
                            fit: pw.BoxFit.cover,
                          ),
                  ),
                  pw.SizedBox(width: 7),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      pw.Text(
                        _safe(
                          report.profileName.isEmpty
                              ? 'AKIBA'
                              : report.profileName,
                        ),
                        style: pw.TextStyle(
                          color: ink,
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        _safe(t('Rapport personnel', 'Personal report')),
                        style: pw.TextStyle(color: muted, fontSize: 7),
                      ),
                    ],
                  ),
                  pw.SizedBox(width: 10),
                ],
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(
                      'AKIBA',
                      style: pw.TextStyle(
                        color: accent,
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    pw.Text(
                      _safe(
                        t(
                          'Tirelire numérique · FCFA',
                          'Digital piggy bank · FCFA',
                        ),
                      ),
                      style: pw.TextStyle(color: muted, fontSize: 8),
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: <pw.Widget>[
                    pw.Text(
                      _safe(report.title),
                      style: pw.TextStyle(
                        color: ink,
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      _safe(report.periodLabel),
                      style: pw.TextStyle(color: muted, fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),
            if (report.simulation)
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 8),
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: ochre,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  _safe(report.simulationLabel),
                  style: pw.TextStyle(
                    color: ink,
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            pw.SizedBox(height: 8),
            pw.Divider(color: accent, thickness: 1.1),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (pw.Context context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              _safe(
                t(
                  'Généré localement · aucun serveur maître · base chiffrée AES-256',
                  'Generated locally · no master server · AES-256 encrypted database',
                ),
              ),
              style: pw.TextStyle(color: muted, fontSize: 7.5),
            ),
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: pw.TextStyle(color: muted, fontSize: 7.5),
            ),
          ],
        ),
        build: (pw.Context context) => <pw.Widget>[
          // 1. Indicateurs de la période.
          pw.Row(
            children: <pw.Widget>[
              kpi(
                t('Entrées', 'Income'),
                report.amount(report.income),
                success,
              ),
              pw.SizedBox(width: 8),
              kpi(
                t('Sorties', 'Expenses'),
                report.amount(report.expense),
                accent,
              ),
              pw.SizedBox(width: 8),
              kpi(
                t('Solde', 'Net'),
                report.amount(report.net),
                report.net < 0 ? warning : accentSoft,
              ),
              pw.SizedBox(width: 8),
              kpi(
                t('Épargne', 'Savings'),
                report.amount(report.savingsHeld),
                ochre,
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            _safe(
              report.profileName.isEmpty
                  ? t(
                      'Rapport personnel · ${report.period.label('fr')}',
                      'Personal report · ${report.period.label('en')}',
                    )
                  : t(
                      'Rapport de ${report.profileName} · ${report.period.label('fr')}',
                      'Report for ${report.profileName} · ${report.period.label('en')}',
                    ),
            ),
            style: pw.TextStyle(color: muted, fontSize: 8.5),
          ),
          pw.SizedBox(height: 12),

          // 2. Détail de la période.
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(
                child: card(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      sectionTitle(t('Principales sorties', 'Top expenses')),
                      if (topExpenses.isEmpty)
                        pw.Text(
                          _safe(
                            t(
                              'Aucune sortie sur la période.',
                              'No expense in this period.',
                            ),
                          ),
                          style: pw.TextStyle(color: muted, fontSize: 9),
                        )
                      else
                        for (final CategoryTotal category in topExpenses)
                          detailRow(
                            category.label,
                            report.amount(category.amount),
                            valueColor: accent,
                          ),
                      pw.SizedBox(height: 6),
                      sectionTitle(t('Comptes', 'Accounts')),
                      if (activeAccounts.isEmpty)
                        pw.Text(
                          _safe(
                            t(
                              'Aucun mouvement de compte.',
                              'No account movement.',
                            ),
                          ),
                          style: pw.TextStyle(color: muted, fontSize: 9),
                        )
                      else
                        for (final AccountPeriodTotal account
                            in activeAccounts.take(5))
                          detailRow(
                            account.account.name,
                            t(
                              '${report.amount(account.income)} / ${report.amount(account.expense)}',
                              '${report.amount(account.income)} / ${report.amount(account.expense)}',
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  children: <pw.Widget>[
                    card(
                      color: background,
                      border: ochre,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: <pw.Widget>[
                          sectionTitle(t('Épargne (coffre)', 'Savings vault')),
                          detailRow(
                            t('Total épargné', 'Total saved'),
                            report.amount(report.savingsHeld),
                            valueColor: ochre,
                          ),
                          if (report.savingsTarget > 0)
                            detailRow(
                              t('Objectifs cumulés', 'Combined targets'),
                              report.amount(report.savingsTarget),
                            ),
                          detailRow(
                            t('Réserve de sécurité', 'Safety reserve'),
                            report.amount(report.reserve),
                          ),
                          if (report.savingsPots.isNotEmpty) ...<pw.Widget>[
                            pw.SizedBox(height: 4),
                            for (final SavingsPotBalance pot
                                in report.savingsPots.take(4))
                              detailRow(pot.pot.name, report.amount(pot.held)),
                          ],
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    card(
                      color: background,
                      border: warning,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: <pw.Widget>[
                          sectionTitle(
                            t(
                              'Argent de tiers · isolé',
                              'Third-party money · isolated',
                            ),
                          ),
                          detailRow(
                            t('Détenu pour autrui', 'Held for others'),
                            report.amount(report.thirdPartyHeld),
                            valueColor: warning,
                          ),
                          for (final ThirdPartyBalance party
                              in report.thirdParties.take(4))
                            detailRow(party.name, report.amount(party.held)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            _safe(
                              t(
                                'Exclu des entrées, des sorties, du budget et de l’épargne.',
                                'Excluded from income, expenses, budget and savings.',
                              ),
                            ),
                            style: pw.TextStyle(color: muted, fontSize: 7.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          card(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                sectionTitle(
                  t(
                    'Créances et dettes · isolées',
                    'Receivables and debts · isolated',
                  ),
                ),
                pw.Row(
                  children: <pw.Widget>[
                    pw.Expanded(
                      child: detailRow(
                        t('On me doit', 'Owed to me'),
                        report.amount(report.receivable),
                        valueColor: success,
                      ),
                    ),
                    pw.Expanded(
                      child: detailRow(
                        t('Je dois', 'I owe'),
                        report.amount(report.payable),
                        valueColor: warning,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  _safe(
                    t(
                      'Ces montants ne sont ni des revenus ni des dépenses du mois.',
                      'These amounts are neither income nor expenses for the month.',
                    ),
                  ),
                  style: pw.TextStyle(color: muted, fontSize: 7.5),
                ),
              ],
            ),
          ),

          // 3. Graphiques récapitulatifs, puis avis de l'assistant.
          pw.SizedBox(height: 12),
          sectionTitle(t('Six derniers mois', 'Last six months')),
          card(
            child: pw.Column(
              children: <pw.Widget>[
                for (final MonthTotal month in report.months)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: <pw.Widget>[
                        pw.SizedBox(
                          width: 34,
                          child: pw.Text(
                            '${month.month.toString().padLeft(2, '0')}/${month.year % 100}',
                            style: pw.TextStyle(color: muted, fontSize: 8),
                          ),
                        ),
                        pw.SizedBox(
                          width: 306,
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: <pw.Widget>[
                              bar(month, income: true, max: maxMonth),
                              pw.SizedBox(height: 2),
                              bar(month, income: false, max: maxMonth),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: pw.Text(
                            '${report.amount(month.income)} / ${report.amount(month.expense)}',
                            style: pw.TextStyle(color: ink, fontSize: 7.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                pw.SizedBox(height: 4),
                pw.Row(
                  children: <pw.Widget>[
                    pw.Container(width: 8, height: 8, color: success),
                    pw.SizedBox(width: 4),
                    pw.Text(
                      t('Entrées', 'Income'),
                      style: pw.TextStyle(color: muted, fontSize: 7.5),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Container(width: 8, height: 8, color: accent),
                    pw.SizedBox(width: 4),
                    pw.Text(
                      t('Sorties', 'Expenses'),
                      style: pw.TextStyle(color: muted, fontSize: 7.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          sectionTitle(
            t('Avis et conseils de l’assistant', 'Assistant review and advice'),
          ),
          card(
            color: surface,
            border: accent,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  _safe(report.advice.headline),
                  style: pw.TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                for (final String tip in report.advice.tips)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        pw.Text(
                          '- ',
                          style: pw.TextStyle(color: accent, fontSize: 9.5),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            _safe(tip),
                            style: pw.TextStyle(
                              color: ink,
                              fontSize: 9.5,
                              lineSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                pw.SizedBox(height: 3),
                pw.Text(
                  _safe(
                    report.advice.fromAi
                        ? t(
                            'Avis généré par ${report.advice.engine}, puis intégré localement au PDF.',
                            'Review generated by ${report.advice.engine}, then embedded locally in the PDF.',
                          )
                        : t(
                            'Analyse locale déterministe (aucune clé IA ou hors ligne).',
                            'Deterministic local analysis (no AI key or offline).',
                          ),
                  ),
                  style: pw.TextStyle(
                    color: muted,
                    fontSize: 7.5,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            _safe(
              t(
                'Les montants de ce rapport sont affichés en clair, même si le masquage est actif dans l’application. L’argent de tiers et les créances/dettes restent isolés.',
                'Amounts in this report are shown in clear, even when masking is on in the app. Third-party money and receivables/debts stay isolated.',
              ),
            ),
            style: pw.TextStyle(color: muted, fontSize: 7.5),
          ),
        ],
      ),
    );

    return document.save();
  }

  /// Charge le logo embarqué adapté au fond (noir sur clair, clair sur sombre).
  Future<Uint8List?> _loadLogo(bool dark) async {
    final String asset = dark
        ? 'assets/brand/akiba_mark_dark.png'
        : 'assets/brand/akiba_mark_light.png';
    try {
      final ByteData data = await rootBundle.load(asset);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Couleur du thème convertie pour le PDF (utile aux tests de fidélité).
  static PdfColor pdfColorFor(Color color) =>
      PdfColor.fromInt(color.toARGB32());

  static PdfColor _pdfColor(Color color) => pdfColorFor(color);

  /// Les polices standard PDF sont en WinAnsi : on remplace les caractères
  /// hors table pour ne jamais produire de glyphe manquant.
  static String _safe(String value) => value
      .replaceAll('\u00A0', ' ')
      .replaceAll('−', '-')
      .replaceAll('’', "'")
      .replaceAll('…', '...')
      .replaceAll('•', '-')
      .replaceAll('→', '->');
}
