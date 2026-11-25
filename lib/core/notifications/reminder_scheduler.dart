import '../../data/akiba_store.dart';
import '../../data/models/debt.dart';
import '../state/akiba_settings.dart';
import 'background_reminders.dart';
import 'local_notifications.dart';
import 'reminder_planner.dart';

/// Reprogrammation des rappels à partir des réglages persistants.
///
/// Utilisée au démarrage (les rappels planifiés survivent aux mises à jour du
/// système) et après un changement de réglage. Aucun montant n'est transmis :
/// les messages sont filtrés avec `masked: true` par précaution.
abstract final class ReminderScheduler {
  /// Vrai si au moins une famille de rappels est active.
  static bool anyEnabled(AkibaSettings settings) =>
      settings.morningEnabled ||
      settings.noonEnabled ||
      settings.eveningEnabled ||
      settings.expenseReminderEnabled ||
      settings.flag('notif_debt');

  /// Replanifie les rappels des sept prochains jours, plus les échéances de
  /// créances et de dettes quand [store] est fourni.
  ///
  /// Le greffon est **initialisé avant** toute planification ou demande
  /// d'autorisation, et l'autorisation n'est redemandée que si
  /// [requestPermission] est vrai : au démarrage, aucune fenêtre système ne
  /// s'ouvre. La tâche Workmanager n'est inscrite qu'une fois par réglage.
  ///
  /// Renvoie le nombre de rappels fixes planifiés.
  static Future<int> reprogram(
    AkibaSettings settings, {
    AkibaStore? store,
    bool requestPermission = false,
  }) async {
    if (!anyEnabled(settings)) {
      await LocalNotifications.cancelAll();
      await BackgroundReminders.cancel();
      return 0;
    }

    final DateTime now = DateTime.now();
    final List<ReminderPlan> plans = <ReminderPlan>[
      ...ReminderPlanner.plan(
        ReminderConfig(
          morningEnabled: settings.morningEnabled,
          noonEnabled: settings.noonEnabled,
          eveningEnabled: settings.eveningEnabled,
          morningTime: settings.morningTime,
          noonTime: settings.noonTime,
          eveningTime: settings.eveningTime,
          dndEnabled: settings.dndEnabled,
          dndStart: settings.dndStart,
          dndEnd: settings.dndEnd,
          festiveEnabled: settings.festiveEnabled,
          festiveLabel: settings.festiveLabel,
          masked: true,
        ),
        now: now,
        horizonDays: 7,
      ),
      if (settings.flag('notif_debt'))
        ...await _debtPlans(store: store, now: now),
    ]..sort((ReminderPlan a, ReminderPlan b) => a.when.compareTo(b.when));

    // Windows : la livraison système n'est pas prise en charge ; les messages
    // restent consultables dans l'application (le Profil l'explique).
    if (!LocalNotifications.supported) return 0;

    // Initialisation du greffon AVANT `schedule` / `requestPermission`.
    if (!await LocalNotifications.ensureReady(timezone: settings.timezone)) {
      return 0;
    }

    // Le drapeau mémorisé peut être périmé (permission accordée hors AKIBA ou
    // révoquée depuis) : l'état réel du système fait foi. Sans cette relecture,
    // un rappel refusé à tort restait bloqué sur « autorisation refusée ».
    bool granted = await LocalNotifications.permissionGranted();
    if (requestPermission && !granted) {
      granted = await LocalNotifications.requestPermission();
    }
    // Au démarrage (sans nouvelle demande), le drapeau mémorisé sert de repli
    // si le greffon ne sait pas relire l'état ; une demande explicite, elle,
    // ne se contente pas d'un ancien drapeau.
    final bool allowed =
        granted ||
        (!requestPermission && settings.flag('permission_notifications'));
    if (granted && !settings.flag('permission_notifications')) {
      await settings.setFlag('permission_notifications', true);
    }
    if (!allowed) return 0;

    final int scheduled = await LocalNotifications.schedule(plans);
    await BackgroundReminders.ensureScheduled(settings);
    return scheduled;
  }

  /// Rappels d'échéance : un par créance ou dette non soldée. Le message ne
  /// cite ni le contact ni le montant.
  static Future<List<ReminderPlan>> _debtPlans({
    required AkibaStore? store,
    required DateTime now,
  }) async {
    if (store == null) return const <ReminderPlan>[];
    try {
      final List<Debt> debts = await store.debts();
      return ReminderPlanner.planDebts(
        <DebtDue>[
          for (final Debt debt in debts)
            if (debt.dueDate != null)
              DebtDue(
                id: debt.id,
                dueDate: debt.dueDate!.toLocal(),
                owedToMe: debt.direction == DebtDirection.owedToMe,
                remaining: debt.remaining,
              ),
        ],
        now: now,
        time: ReminderPlanner.debtReminderTime,
      );
    } catch (_) {
      // Base indisponible : les rappels de repas restent planifiés.
      return const <ReminderPlan>[];
    }
  }
}
