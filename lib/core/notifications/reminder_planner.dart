/// Planification locale des rappels (matin, midi, soir) et des périodes de
/// fête.
///
/// Aucun réseau, aucun montant : les messages ne contiennent jamais de FCFA,
/// donc le masquage est respecté par construction. Un filtre de sécurité
/// supprime en plus tout montant qui aurait été introduit par erreur.
library;

class ReminderConfig {
  const ReminderConfig({
    required this.morningEnabled,
    required this.noonEnabled,
    required this.eveningEnabled,
    required this.morningTime,
    required this.noonTime,
    required this.eveningTime,
    required this.dndEnabled,
    required this.dndStart,
    required this.dndEnd,
    required this.festiveEnabled,
    required this.festiveLabel,
    required this.masked,
  });

  final bool morningEnabled;
  final bool noonEnabled;
  final bool eveningEnabled;
  final String morningTime;
  final String noonTime;
  final String eveningTime;
  final bool dndEnabled;
  final String dndStart;
  final String dndEnd;
  final bool festiveEnabled;
  final String festiveLabel;
  final bool masked;
}

class ReminderPlan {
  const ReminderPlan({
    required this.slot,
    required this.title,
    required this.body,
    required this.when,
    required this.festive,
  });

  final String slot;
  final String title;
  final String body;
  final DateTime when;
  final bool festive;
}

abstract final class ReminderPlanner {
  static const List<String> morningMessages = <String>[
    'Tu as dépensé pour ton petit déjeuner ou ton transport ce matin ? '
        'Note-le en 3 touches.',
    'Bonjour ! Pense à noter ton trajet ou ton café du matin pour garder ton '
        'budget à jour.',
    'Rappel du matin : vérifie tes échéances du jour avant de démarrer.',
    'Un trajet, un café, une recharge : trois secondes pour tout noter.',
  ];

  static const List<String> noonMessages = <String>[
    'Pause déjeuner : tu as pris à manger ou fait un achat ce midi ? '
        'Pense à l’enregistrer.',
    'Mi-journée : un transfert Flooz ou Mixx by Yas à noter ? Fais-le en '
        'quelques secondes.',
    'Le repas du midi compte aussi dans ton budget : note-le maintenant.',
    'Une petite dépense oubliée ? Le cochon t’attend.',
  ];

  static const List<String> eveningMessages = <String>[
    'Bilan du soir : as-tu noté toutes tes dépenses de la journée avant de '
        'passer à demain ?',
    'Fin de journée : prends 10 secondes pour vérifier tes comptes et ton '
        'épargne du jour.',
    'Rappel épargne : un petit versement vers ton objectif aujourd’hui ?',
    'Ferme la journée proprement : une entrée, une sortie, et c’est réglé.',
  ];

  static const List<String> festiveMessages = <String>[
    'Période de fête : les petits extras s’additionnent vite. Garde un œil '
        'sur ton budget !',
    'Préparation des fêtes : pense à isoler l’argent des cotisations ou de '
        'tiers dans AKIBA.',
    'Bonnes fêtes ! Note tes achats festifs au fur et à mesure pour éviter '
        'les mauvaises surprises.',
  ];

  /// Vrai si la date tombe dans une fenêtre festive : fin d'année
  /// (15 décembre → 5 janvier) ou période personnalisée.
  static bool isFestive(
    DateTime date, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final int month = date.month;
    final int day = date.day;
    if ((month == 12 && day >= 15) || (month == 1 && day <= 5)) return true;
    if (customStart != null && customEnd != null) {
      final DateTime dayOnly = DateTime(date.year, date.month, date.day);
      return !dayOnly.isBefore(
            DateTime(customStart.year, customStart.month, customStart.day),
          ) &&
          !dayOnly.isAfter(
            DateTime(customEnd.year, customEnd.month, customEnd.day),
          );
    }
    return false;
  }

  /// Construit les prochains rappels à partir de [now].
  static List<ReminderPlan> plan(
    ReminderConfig config, {
    required DateTime now,
    DateTime? customStart,
    DateTime? customEnd,
    int horizonDays = 1,
  }) {
    final List<ReminderPlan> plans = <ReminderPlan>[];
    final bool festive =
        config.festiveEnabled &&
        isFestive(now, customStart: customStart, customEnd: customEnd);
    final int seed = now.difference(DateTime(now.year)).inDays;

    for (int offset = 0; offset < horizonDays; offset++) {
      final DateTime day = now.add(Duration(days: offset));
      _addSlot(
        plans,
        enabled: config.morningEnabled,
        label: 'Matin',
        time: config.morningTime,
        day: day,
        messages: morningMessages,
        seed: seed + offset,
        config: config,
        festive: festive,
      );
      _addSlot(
        plans,
        enabled: config.noonEnabled,
        label: 'Midi',
        time: config.noonTime,
        day: day,
        messages: noonMessages,
        seed: seed + offset + 1,
        config: config,
        festive: festive,
      );
      _addSlot(
        plans,
        enabled: config.eveningEnabled,
        label: 'Soir',
        time: config.eveningTime,
        day: day,
        messages: eveningMessages,
        seed: seed + offset + 2,
        config: config,
        festive: festive,
      );
    }

    plans.removeWhere((ReminderPlan plan) => !plan.when.isAfter(now));
    plans.sort((ReminderPlan a, ReminderPlan b) => a.when.compareTo(b.when));
    return plans;
  }

  static void _addSlot(
    List<ReminderPlan> plans, {
    required bool enabled,
    required String label,
    required String time,
    required DateTime day,
    required List<String> messages,
    required int seed,
    required ReminderConfig config,
    required bool festive,
  }) {
    if (!enabled) return;
    final ({int hour, int minute}) parsed = parseTime(time);
    final DateTime when = DateTime(
      day.year,
      day.month,
      day.day,
      parsed.hour,
      parsed.minute,
    );
    if (config.dndEnabled && isInDnd(when, config.dndStart, config.dndEnd)) {
      return;
    }
    final bool festiveSlot = festive && label == 'Soir';
    final List<String> pool = festiveSlot ? festiveMessages : messages;
    final String body = sanitize(
      pool[seed % pool.length],
      masked: config.masked,
    );
    plans.add(
      ReminderPlan(
        slot: label,
        title: festiveSlot
            ? (config.festiveLabel.isEmpty
                  ? 'Période de fête'
                  : config.festiveLabel)
            : 'AKIBA · $label',
        body: body,
        when: when,
        festive: festiveSlot,
      ),
    );
  }

  static ({int hour, int minute}) parseTime(String value) {
    final List<String> parts = value.split(':');
    final int hour = parts.isEmpty
        ? 0
        : (int.tryParse(parts[0]) ?? 0).clamp(0, 23);
    final int minute = parts.length < 2
        ? 0
        : (int.tryParse(parts[1]) ?? 0).clamp(0, 59);
    return (hour: hour, minute: minute);
  }

  /// Plage « Ne pas déranger », éventuellement à cheval sur minuit.
  static bool isInDnd(DateTime when, String start, String end) {
    final ({int hour, int minute}) s = parseTime(start);
    final ({int hour, int minute}) e = parseTime(end);
    final int minutes = when.hour * 60 + when.minute;
    final int from = s.hour * 60 + s.minute;
    final int to = e.hour * 60 + e.minute;
    if (from == to) return false;
    if (from < to) return minutes >= from && minutes < to;
    return minutes >= from || minutes < to;
  }

  /// Retire tout montant en FCFA d'un texte de notification.
  static String sanitize(String text, {required bool masked}) {
    if (!masked) return text;
    return text.replaceAll(
      RegExp(r'\d[\d .]*\s*(?:FCFA|XOF|CFA)', caseSensitive: false),
      '•••••• FCFA',
    );
  }
}
