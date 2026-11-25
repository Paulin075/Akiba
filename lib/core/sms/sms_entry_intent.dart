import 'sms_parser.dart';

/// Détection d'un SMS financier exploitable (Flooz, Mixx by Yas, banque).
///
/// Ce prédicat est utilisé **avant** d'ouvrir la fiche préremplie et sert de
/// source de vérité testable pour le filtre du récepteur Android : un message
/// doit citer un opérateur ou une banque **et** un montant en FCFA.
abstract final class SmsDetector {
  static const List<String> mobileMoneyNames = <String>[
    'flooz',
    'moov',
    'mixx',
    'yas',
  ];

  static const List<String> bankNames = <String>[
    'orabank',
    'bank',
    'banque',
    'boa',
    'ecobank',
    'coris',
    'nsia',
    'ubs',
    'bsic',
    'attijari',
    'société générale',
    'societe generale',
    'sgci',
  ];

  /// Vrai si [body] ressemble à un SMS de dépôt/retrait mobil-money ou bancaire.
  static bool isFinancialSms(String body) {
    final String lower = body.toLowerCase();
    final bool knownSource =
        mobileMoneyNames.any(lower.contains) || bankNames.any(lower.contains);
    if (!knownSource) return false;
    return SmsParser.parseOne(body)?.isUsable ?? false;
  }
}

/// Données de préremplissage de la saisie rapide, issues d'un SMS.
///
/// Aucune écriture n'est faite ici : la fiche ouverte reste **à confirmer**.
class SmsEntryIntent {
  const SmsEntryIntent({
    required this.amount,
    required this.income,
    required this.note,
    this.brandName,
    this.counterparty,
    this.isNeutral = false,
    this.occurredAt,
    this.reference,
  });

  /// Montant en FCFA entiers.
  final int amount;

  /// Vrai pour un dépôt/crédit, faux pour un retrait/débit/paiement.
  final bool income;

  /// Libellé court (opérateur, contact, référence), sans recopier tout le SMS.
  final String note;

  /// Nom technique du support (`flooz`, `mixxByYas`, `orabank`), sinon `null`.
  final String? brandName;

  final String? counterparty;
  final bool isNeutral;
  final DateTime? occurredAt;
  final String? reference;

  /// Traduit une proposition SMS en préremplissage, ou `null` si le message
  /// n'est pas exploitable (montant absent ou sens incertain).
  static SmsEntryIntent? fromDraft(SmsDraft draft) {
    if (!draft.isUsable) return null;
    final String? brandName = switch (draft.operator) {
      'Flooz' => 'flooz',
      'Mixx by Yas' => 'mixxByYas',
      'Orabank' => 'orabank',
      _ => null,
    };
    final List<String> parts = <String>[
      if (draft.operator != null) 'SMS ${draft.operator}',
      if (draft.counterpart != null) draft.counterpart!,
      if (draft.reference != null) 'Réf ${draft.reference}',
    ];
    return SmsEntryIntent(
      amount: draft.amount,
      income: draft.direction == SmsDirection.income,
      note: parts.isEmpty ? 'SMS détecté' : parts.join(' · '),
      brandName: brandName,
      counterparty: draft.counterpart,
      isNeutral: draft.isNeutral,
      occurredAt: draft.occurredAt,
      reference: draft.reference,
    );
  }
}
