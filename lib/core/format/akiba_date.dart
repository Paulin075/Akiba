/// Formatage des dates AKIBA (français, fuseau de l'appareil).
///
/// Dates `jj/mm/aaaa`, heures `HH h mm`, conformément au cahier des charges.
abstract final class AkibaDate {
  static const List<String> _weekdays = <String>[
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];

  static const List<String> _months = <String>[
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  /// « Mercredi 19 novembre ».
  static String long(DateTime date) {
    final String day = _weekdays[date.weekday - 1];
    return '${day[0].toUpperCase()}${day.substring(1)} ${date.day} '
        '${_months[date.month - 1]}';
  }

  /// Préférence de format : `jj/mm/aaaa` (défaut) ou `aaaa-mm-jj`.
  static bool isoStyle = false;

  /// « 19/11/2026 » (ou « 2026-11-19 » selon la préférence).
  static String short(DateTime date) => isoStyle
      ? '${date.year}-${_two(date.month)}-${_two(date.day)}'
      : '${_two(date.day)}/${_two(date.month)}/${date.year}';

  /// « 07 h 42 ».
  static String time(DateTime date) =>
      '${_two(date.hour)} h ${_two(date.minute)}';

  /// « Aujourd'hui », « Hier », sinon la date courte.
  static String dayLabel(DateTime date, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final DateTime local = date.toLocal();
    final int days = DateTime(
      reference.year,
      reference.month,
      reference.day,
    ).difference(DateTime(local.year, local.month, local.day)).inDays;
    return switch (days) {
      0 => "Aujourd'hui",
      1 => 'Hier',
      _ => short(local),
    };
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
