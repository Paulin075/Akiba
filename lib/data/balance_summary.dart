/// Synthèse des soldes AKIBA.
///
/// Règle unique du cahier des charges (§1.5) :
/// **Solde disponible = total des comptes + épargne − argent de tiers**.
/// L'épargne est un transfert entre poches de l'utilisateur : elle sort des
/// comptes mais reste à lui. L'argent de tiers est isolé, jamais dépensé, jamais
/// budgété, jamais compté dans les statistiques.
class BalanceSummary {
  const BalanceSummary({
    required this.totalAccounts,
    required this.savingsHeld,
    required this.thirdPartyHeld,
    this.monthIncome = 0,
    this.monthExpense = 0,
  });

  /// Construit la synthèse à partir des sommes brutes lues en base.
  ///
  /// [savingsTransfersSum] est la somme **signée** des transactions épargne
  /// (négative pour un versement) ; [neutralSum] est la somme signée des
  /// transactions neutres (entrées non soldées moins reversements).
  factory BalanceSummary.fromSums({
    required int accountsTotal,
    required int savingsTransfersSum,
    required int neutralSum,
    int monthIncome = 0,
    int monthExpense = 0,
  }) {
    return BalanceSummary(
      totalAccounts: accountsTotal,
      savingsHeld: -savingsTransfersSum,
      thirdPartyHeld: neutralSum,
      monthIncome: monthIncome,
      monthExpense: monthExpense,
    );
  }

  /// Somme des soldes de tous les comptes actifs.
  final int totalAccounts;

  /// Argent placé dans le coffre épargne.
  final int savingsHeld;

  /// Argent de tiers actuellement détenu (entrées neutres − reversements).
  final int thirdPartyHeld;

  /// Entrées du mois en cours, hors transactions neutres.
  final int monthIncome;

  /// Sorties du mois en cours, hors transactions neutres et épargne.
  final int monthExpense;

  /// Argent réellement possédé, épargne comprise.
  int get owned => totalAccounts + savingsHeld;

  /// Grand chiffre de l'accueil : ce qui est réellement à l'utilisateur.
  int get available => owned - thirdPartyHeld;

  static const BalanceSummary empty = BalanceSummary(
    totalAccounts: 0,
    savingsHeld: 0,
    thirdPartyHeld: 0,
  );
}
