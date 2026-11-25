import 'models/transaction_record.dart';

/// Reclassement d'un mouvement : la catégorie est la seule clé de
/// correspondance, aucune autre donnée (montant, date, compte) ne change.
abstract final class TransactionReclassifier {
  static const List<String> expenseCategories = <String>[
    'Alimentation',
    'Transport',
    'Loyer',
    'Santé',
    'École',
    'Tontine',
    'Autre',
  ];

  static const List<String> incomeCategories = <String>[
    'Salaire',
    'Vente',
    'Don',
    'Autre',
  ];

  /// Catégories proposées pour ce mouvement.
  static List<String> categoriesFor(TransactionRecord record) =>
      record.kind == TransactionKind.income
      ? incomeCategories
      : expenseCategories;

  /// Seules les entrées et sorties réelles sont reclassables : l'argent de
  /// tiers, les transferts, l'épargne et les soldes d'ouverture sont hors
  /// budget et n'ont donc pas de catégorie.
  static bool canReclassify(TransactionRecord record) =>
      !record.isNeutral &&
      (record.kind == TransactionKind.expense ||
          record.kind == TransactionKind.income);

  /// Copie du mouvement avec une nouvelle catégorie (`null` la retire).
  ///
  /// L'identifiant est conservé : l'écriture est remplacée, jamais dupliquée,
  /// donc les soldes dérivés restent exacts.
  static TransactionRecord withCategory(
    TransactionRecord record,
    String? category,
  ) => TransactionRecord(
    id: record.id,
    accountId: record.accountId,
    amount: record.amount,
    kind: record.kind,
    category: category,
    note: record.note,
    occurredAt: record.occurredAt,
    createdAt: record.createdAt,
    isNeutral: record.isNeutral,
    thirdPartyId: record.thirdPartyId,
    transferAccountId: record.transferAccountId,
    savingsPotId: record.savingsPotId,
  );
}
