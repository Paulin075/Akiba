/// Formatage des montants AKIBA.
///
/// FCFA (XOF), sans décimales, séparateur de milliers.
/// Exemple : `15000` devient `15 000 FCFA` (espaces insécables, pour éviter
/// qu'un montant soit coupé en fin de ligne).
abstract final class AkibaMoney {
  /// Libellé de devise (FCFA ou XOF), réglable dans Profil.
  static String currency = 'FCFA';
  static const String mask = '••••••';

  /// Espace insécable utilisé comme séparateur de milliers.
  static const String _thinSpace = '\u00A0';

  static String format(num amount, {bool masked = false}) {
    if (masked) return '$mask$_thinSpace$currency';

    final int rounded = amount.round();
    final String digits = rounded.abs().toString();
    final StringBuffer groups = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        groups.write(_thinSpace);
      }
      groups.write(digits[i]);
    }

    final String sign = rounded < 0 ? '−' : '';
    return '$sign$groups$_thinSpace$currency';
  }

  /// Variante signée pour les listes : `+ 10 000 FCFA` / `− 3 500 FCFA`.
  static String formatSigned(num amount, {bool masked = false}) {
    if (masked) return '$mask$_thinSpace$currency';
    final String prefix = amount < 0 ? '− ' : '+ ';
    return '$prefix${format(amount.abs())}';
  }

  /// Pourcentage arrondi, sans décimale superflue.
  static String percent(num value) {
    final int rounded = value.round();
    return '$rounded$_thinSpace%';
  }
}
