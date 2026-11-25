/// Calculs purs autour de l'épargne : proposition de versement et date
/// d'atteinte estimée d'un objectif.
///
/// Aucun versement n'est automatique : la proposition est un montant pré-rempli
/// que la personne relit, modifie ou ignore.
abstract final class SavingsProjection {
  /// Part maximale proposée, en pourcentage du solde d'un compte.
  static const int maxPercent = 30;

  /// Nombre de cauris représentant le versement : un cauri par tranche
  /// complète de 100 FCFA. Tout versement positif affiche au moins un cauri.
  /// La valeur reste un entier non borné artificiellement, même pour les
  /// grands montants ; l'animation affiche le total sans répéter les images.
  static int cauriCountForAmount(int amount) {
    if (amount <= 0) return 0;
    return amount ~/ 100 < 1 ? 1 : amount ~/ 100;
  }

  /// Montant proposé pour un versement : [percent] (0 → 30 %) du solde du
  /// compte, arrondi au franc inférieur. Zéro si le solde ou la part est nul.
  static int suggestedDeposit({
    required int accountBalance,
    required int percent,
  }) {
    final int bounded = percent.clamp(0, maxPercent);
    if (accountBalance <= 0 || bounded == 0) return 0;
    return accountBalance * bounded ~/ 100;
  }

  /// Date d'atteinte estimée au rythme observé depuis la création du coffre.
  ///
  /// Le rythme est le montant déjà épargné divisé par le nombre de jours
  /// écoulés. `null` si l'objectif est atteint, absent, ou si aucun rythme ne
  /// peut être observé (coffre neuf, vide, ou échéance au-delà de dix ans).
  static DateTime? estimateTargetDate({
    required int held,
    required int target,
    required DateTime createdAt,
    required DateTime now,
  }) {
    if (target <= 0 || held <= 0 || held >= target) return null;
    final int elapsedDays = now.difference(createdAt).inDays;
    if (elapsedDays <= 0) return null;
    final double perDay = held / elapsedDays;
    if (perDay <= 0) return null;
    final int days = ((target - held) / perDay).ceil();
    if (days <= 0 || days > 3650) return null;
    return now.add(Duration(days: days));
  }
}
