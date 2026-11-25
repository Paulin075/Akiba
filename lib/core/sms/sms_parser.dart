/// Lecture locale des SMS financiers (Flooz, Mixx by Yas, Orabank).
///
/// Aucun réseau : le texte fourni par la personne est analysé, puis chaque
/// proposition est relue et validée à la main. Rien n'est enregistré sans
/// confirmation.
library;

enum SmsDirection { income, expense, unknown }

class SmsDraft {
  const SmsDraft({
    required this.raw,
    required this.amount,
    required this.direction,
    this.operator,
    this.reference,
    this.counterpart,
    this.fee,
    this.occurredAt,
    this.isNeutral = false,
  });

  final String raw;
  final int amount;
  final SmsDirection direction;
  final String? operator;
  final String? reference;
  final String? counterpart;
  final int? fee;
  final DateTime? occurredAt;
  final bool isNeutral;

  bool get isUsable => amount > 0 && direction != SmsDirection.unknown;

  SmsDraft copyWith({bool? isNeutral, int? amount, SmsDirection? direction}) {
    return SmsDraft(
      raw: raw,
      amount: amount ?? this.amount,
      direction: direction ?? this.direction,
      operator: operator,
      reference: reference,
      counterpart: counterpart,
      fee: fee,
      occurredAt: occurredAt,
      isNeutral: isNeutral ?? this.isNeutral,
    );
  }

  String get summary {
    final String sens = switch (direction) {
      SmsDirection.income => 'Entrée',
      SmsDirection.expense => 'Sortie',
      SmsDirection.unknown => 'À classer',
    };
    return '$sens · ${operator ?? 'opérateur inconnu'}';
  }
}

abstract final class SmsParser {
  static final RegExp _amount = RegExp(
    r'(\d{1,3}(?:[ .]\d{3})+|\d+)(?:[.,](\d{2}))?\s*(?:F\s?CFA|XOF|CFA)',
    caseSensitive: false,
  );

  static const List<String> _incomeWords = <String>[
    'reçu',
    'recu',
    'reception',
    'réception',
    'credit',
    'crédit',
    'credite',
    'crédité',
    'depose',
    'déposé',
    'depot',
    'dépôt',
    'versement',
    'verse',
    'versé',
    'virement recu',
    'virement reçu',
    'virement en votre faveur',
    'remboursement',
    'ajoute',
    'ajouté',
  ];

  static const List<String> _expenseWords = <String>[
    'envoyé',
    'envoye',
    'transféré',
    'transfere',
    'paiement',
    'payé',
    'paye',
    'achat',
    'retrait',
    'debit',
    'débit',
    'debite',
    'débité',
    'prelevé',
    'prélevé',
    'prelevement',
    'prélèvement',
    'virement emis',
    'virement émis',
    'cheque',
    'chèque',
    'facture',
    'dab',
    'carte bancaire',
    'commission',
  ];

  /// Banques reconnues en plus d'Orabank : le libellé reste générique quand le
  /// nom exact n'est pas dans la liste.
  static const List<String> _bankWords = <String>[
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

  /// Découpe un texte en messages (un SMS par ligne vide ou « --- »).
  static List<String> splitMessages(String text) {
    return text
        .split(RegExp(r'\n\s*---+\s*\n|\n\s*\n'))
        .map((String part) => part.trim())
        .where((String part) => part.length > 8)
        .toList(growable: false);
  }

  /// Analyse un texte libre et renvoie une proposition par SMS reconnu.
  static List<SmsDraft> parse(String text, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final List<SmsDraft> drafts = <SmsDraft>[];
    for (final String message in splitMessages(text)) {
      final SmsDraft? draft = parseOne(message, now: reference);
      if (draft != null) drafts.add(draft);
    }
    if (drafts.isEmpty) {
      final SmsDraft? single = parseOne(text.trim(), now: reference);
      if (single != null) drafts.add(single);
    }
    return drafts;
  }

  static SmsDraft? parseOne(String message, {DateTime? now}) {
    if (message.trim().isEmpty) return null;
    final RegExpMatch? match = _amount.firstMatch(message);
    if (match == null) return null;

    final String digits = (match.group(1) ?? '').replaceAll(
      RegExp(r'[ .]'),
      '',
    );
    final int amount = int.tryParse(digits) ?? 0;
    if (amount <= 0) return null;

    final String lower = message.toLowerCase();
    final int incomeIndex = _firstIndexOf(lower, _incomeWords);
    final int expenseIndex = _firstIndexOf(lower, _expenseWords);

    SmsDirection direction = SmsDirection.unknown;
    if (incomeIndex >= 0 && (expenseIndex < 0 || incomeIndex < expenseIndex)) {
      direction = SmsDirection.income;
    } else if (expenseIndex >= 0) {
      direction = SmsDirection.expense;
    }

    String? operator;
    if (lower.contains('flooz') || lower.contains('moov')) {
      operator = 'Flooz';
    } else if (lower.contains('mixx') || lower.contains('yas')) {
      operator = 'Mixx by Yas';
    } else if (lower.contains('orabank')) {
      operator = 'Orabank';
    } else if (_bankWords.any(lower.contains)) {
      // Banque non nommée précisément : on garde un libellé générique pour que
      // la fiche propose le compte bancaire sans inventer d'établissement.
      operator = 'Banque';
    }

    final RegExpMatch? reference = RegExp(
      r'(?:r[ée]f[ée]rence|reference|ref|transaction|id)[:\s#-]*([A-Z0-9]{4,})',
      caseSensitive: false,
    ).firstMatch(message);

    final RegExpMatch? fee = RegExp(
      r'frais[^0-9]{0,20}(\d[\d .]*)',
      caseSensitive: false,
    ).firstMatch(message);
    final int? feeAmount = fee == null
        ? null
        : int.tryParse(fee.group(1)!.replaceAll(RegExp(r'[ .]'), ''));

    final RegExpMatch? from = RegExp(
      r"(?:de|par|chez)\s+([A-ZÉÈÀÂ][\wéèàâçôû'-]{2,}(?:\s+[A-ZÉÈÀÂ][\wéèàâçû'-]+)?)",
    ).firstMatch(message);

    final RegExpMatch? date = RegExp(
      r'(\d{2})[/-](\d{2})[/-](\d{4})',
    ).firstMatch(message);
    DateTime? occurredAt;
    if (date != null) {
      occurredAt = DateTime(
        int.parse(date.group(3)!),
        int.parse(date.group(2)!),
        int.parse(date.group(1)!),
        now?.hour ?? 12,
        now?.minute ?? 0,
      );
    }

    return SmsDraft(
      raw: message,
      amount: amount,
      direction: direction,
      operator: operator,
      reference: reference?.group(1),
      counterpart: from?.group(1),
      fee: feeAmount,
      occurredAt: occurredAt ?? now,
      isNeutral: lower.contains('pour le compte de') || lower.contains('tiers'),
    );
  }

  static int _firstIndexOf(String text, List<String> words) {
    int best = -1;
    for (final String word in words) {
      final int index = text.indexOf(word);
      if (index >= 0 && (best < 0 || index < best)) best = index;
    }
    return best;
  }
}
