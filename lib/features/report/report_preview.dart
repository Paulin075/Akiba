import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/report/monthly_report.dart';
import '../../core/report/report_pdf.dart';
import '../../core/state/akiba_settings.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/pinch_zoom.dart';

/// Prévisualisation directe du PDF généré, dans l'application.
///
/// Le document est construit une seule fois (Paramètres ou fin de mois), puis
/// affiché page par page. Les actions rapides ouvrent le composeur Email, le
/// fil WhatsApp ou la feuille de partage du système avec le PDF en pièce
/// jointe. Aucun octet ne quitte l'appareil sans ce geste explicite.
class ReportPreviewScreen extends StatefulWidget {
  const ReportPreviewScreen({
    super.key,
    required this.report,
    required this.bytes,
    required this.settings,
  });

  final MonthlyReport report;
  final Uint8List bytes;
  final AkibaSettings settings;

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  bool _sharing = false;

  /// Zoom tactile du PDF : pincer pour agrandir, double-tap pour revenir.
  final TransformationController _zoom = TransformationController();
  bool _zoomed = false;

  MonthlyReport get _report => widget.report;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoomChanged);
  }

  @override
  void dispose() {
    _zoom
      ..removeListener(_onZoomChanged)
      ..dispose();
    super.dispose();
  }

  void _onZoomChanged() {
    final bool zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);
  }

  void _resetZoom() => _zoom.value = Matrix4.identity();

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    final AkibaColors c = AkibaColors.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? c.danger : c.textPrimary,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  Future<void> _share({List<String>? emails}) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bool ok = await Printing.sharePdf(
        bytes: widget.bytes,
        filename: ReportPdfBuilder.fileName(_report),
        subject: ReportPdfBuilder.subject(_report),
        body: ReportPdfBuilder.shareBody(_report),
        emails: emails == null || emails.isEmpty ? null : emails,
      );
      if (!ok) _toast('Partage indisponible sur cet appareil.', error: true);
    } catch (_) {
      _toast('Partage impossible : réessayez.', error: true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _email() async {
    final String email = widget.settings.raw('report_email').trim();
    if (email.isEmpty) {
      _toast(
        'Renseignez un destinataire Email dans Paramètres › Rapport mensuel.',
      );
      return;
    }
    await _share(emails: <String>[email]);
  }

  Future<void> _whatsApp() async {
    final String digits = widget.settings
        .raw('report_whatsapp')
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      _toast(
        'Renseignez un numéro WhatsApp dans Paramètres › Rapport mensuel.',
      );
      return;
    }
    final Uri uri = Uri.https('wa.me', '/$digits', <String, String>{
      'text': ReportPdfBuilder.shareBody(_report),
    });
    try {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw StateError('launch');
    } catch (_) {
      _toast(
        'WhatsApp indisponible : le rapport reste partageable.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final bool en = _report.isEnglish;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        title: Text(
          en ? 'Report preview' : 'Aperçu du rapport',
          style: AkibaTypography.label.copyWith(color: c.textPrimary),
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AkibaSpacing.lg,
              AkibaSpacing.sm,
              AkibaSpacing.lg,
              AkibaSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  en
                      ? 'Amounts are shown in clear in this report only. Third-party money and debts stay isolated.'
                      : 'Les montants sont affichés en clair dans ce rapport uniquement. L’argent de tiers et les dettes restent isolés.',
                  style: AkibaTypography.legend.copyWith(
                    color: c.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AkibaSpacing.sm),
                Wrap(
                  spacing: AkibaSpacing.sm,
                  runSpacing: AkibaSpacing.sm,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _sharing ? null : _email,
                      icon: const Icon(Icons.mail_outline_rounded, size: 18),
                      label: const Text('Email'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _sharing ? null : _whatsApp,
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('WhatsApp'),
                    ),
                    FilledButton.icon(
                      onPressed: _sharing ? null : () => _share(),
                      style: FilledButton.styleFrom(
                        backgroundColor: c.terracotta,
                        foregroundColor: c.onTerracotta,
                      ),
                      icon: _sharing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Partager'),
                    ),
                  ],
                ),
                const SizedBox(height: AkibaSpacing.xs),
                Text(
                  '${ReportPdfBuilder.fileName(_report)} · ${_report.periodLabel} · '
                  '${_report.advice.fromAi ? _report.advice.engine : (en ? 'local analysis' : 'analyse locale')}',
                  style: AkibaTypography.legend.copyWith(
                    color: c.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: AkibaSpacing.xs),
                Row(
                  children: <Widget>[
                    Icon(Icons.pinch_rounded, size: 14, color: c.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        en
                            ? 'Pinch to zoom, double-tap to reset.'
                            : 'Pincez pour zoomer, double-tap pour revenir.',
                        style: AkibaTypography.legend.copyWith(
                          color: c.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (_zoomed)
                      TextButton(
                        onPressed: _resetZoom,
                        child: Text(en ? 'Reset' : 'Réinitialiser'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: PinchZoom(
              controller: _zoom,
              // Le défilement vertical reste au PDF tant que rien n'est zoomé ;
              // une fois agrandi, on déplace la page du doigt. L'échelle
              // maximale est très élevée (AkibaZoom.maxScale) : le pincement
              // n'est jamais bloqué à un faible facteur.
              panEnabled: _zoomed,
              child: PdfPreview(
                build: (PdfPageFormat format) async => widget.bytes,
                pdfFileName: ReportPdfBuilder.fileName(_report),
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                allowPrinting: false,
                allowSharing: false,
                useActions: false,
                dynamicLayout: false,
                padding: const EdgeInsets.all(AkibaSpacing.sm),
                loadingWidget: Center(
                  child: CircularProgressIndicator(color: c.terracotta),
                ),
                onError: (BuildContext context, Object error) => Center(
                  child: Text(
                    'Aperçu indisponible.',
                    style: TextStyle(color: c.textMuted),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
