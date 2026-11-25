import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/akiba_store.dart';
import '../backup/backup_service.dart';
import '../backup/home_lab_setup.dart';
import '../notifications/local_notifications.dart';
import '../profile/profile_photo.dart';
import '../state/akiba_settings.dart';
import 'monthly_report.dart';
import 'report_pdf.dart';

/// Rapport de fin de mois, **100 % local**.
///
/// Quand l'option est active, le premier lancement d'un nouveau mois produit
/// silencieusement le rapport du mois écoulé, l'enregistre dans le dossier
/// privé de l'application et affiche une notification **sans montant**.
/// Aucun serveur maître, aucune planification distante : si l'application n'est
/// pas ouverte, rien n'est généré.
abstract final class ReportScheduler {
  static const String autoMonthSetting = 'report_auto_month';
  static const int notificationId = 912;

  /// Marqueur `AAAA-MM` du dernier rapport automatique.
  static String marker(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}';

  /// Renvoie le rapport généré, ou `null` si l'option est inactive, déjà
  /// honorée pour ce mois, ou si le stockage local échoue.
  static Future<MonthlyReport?> maybeGenerate({
    required AkibaStore store,
    required AkibaSettings settings,
    DateTime? now,
  }) async {
    if (!settings.flag('report_end_of_month')) return null;
    final DateTime today = now ?? DateTime.now();
    final DateTime previous = DateTime(today.year, today.month - 1);
    if (settings.raw(autoMonthSetting) == marker(previous)) return null;

    try {
      MonthlyReport report = await MonthlyReport.build(
        store: store,
        settings: settings,
        period: ReportPeriod.previousMonth,
        now: today,
        profilePhotoBytes: await ProfilePhotoStore().load(),
      );
      report = await const ReportAdvisor().enrich(report, settings);
      final List<int> bytes = await const ReportPdfBuilder().build(report);
      final Directory base = await getApplicationDocumentsDirectory();
      final File file = File(
        p.join(base.path, 'rapports', ReportPdfBuilder.fileName(report)),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);

      // Marqueur écrit seulement après succès : un échec réessaiera demain.
      await settings.set(autoMonthSetting, marker(previous));
      await settings.set(
        'report_last_generated_at',
        DateTime.now().toIso8601String(),
      );
      await LocalNotifications.show(
        id: notificationId,
        title: settings.language == 'en'
            ? 'Monthly report ready'
            : 'Rapport mensuel prêt',
        body: settings.language == 'en'
            ? 'Open Settings › Monthly report to preview and share it.'
            : 'Ouvrez Paramètres › Rapport mensuel pour le prévisualiser et le partager.',
      );
      return report;
    } catch (_) {
      // Stockage indisponible : le rapport reste générable à la demande.
      return null;
    }
  }

  /// Envoi explicite du PDF au Home Lab configuré (Wi-Fi domestique).
  ///
  /// Le corps est un JSON avec le PDF en base64 : le Home Lab n'est jamais un
  /// serveur maître, seulement une copie choisie par la personne.
  static Future<bool> sendToHomeLab({
    required AkibaSettings settings,
    required List<int> pdf,
    BackupService? service,
    LabTokenStore? tokenStore,
    String? token,
  }) async {
    final String url = settings.labUrl.trim();
    if (url.isEmpty) return false;
    // Jeton lu dans le coffre du système, jamais dans les réglages en clair.
    final String bearer = (token ?? '').trim().isNotEmpty
        ? token!.trim()
        : await (tokenStore ?? const SecureLabTokenStore()).read();
    try {
      await (service ?? BackupService(settings.store)).putRemote(
        url: url,
        token: bearer,
        envelope: <String, dynamic>{
          'kind': 'akiba_report',
          'format': 'pdf-base64',
          'generated_at': DateTime.now().toIso8601String(),
          'data': base64Encode(pdf),
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
