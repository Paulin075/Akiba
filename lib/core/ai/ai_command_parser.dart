import '../../data/models/transaction_record.dart';

/// Proposition d'opération produite par l'assistant, toujours éditable.
///
/// Aucune opération n'est écrite automatiquement : l'interface montre cette
/// carte, permet de corriger chaque champ, puis enregistre sur confirmation.
class AiDraft {
  AiDraft({
    required this.kind,
    required this.amount,
    this.category,
    this.note,
    this.isNeutral = false,
    this.occurredAt,
    this.fromBrand,
    this.toBrand,
    this.isSavings = false,
    this.debtDirection,
    this.confidence = 0.5,
  });

  TransactionKind kind;
  int amount;
  String? category;
  String? note;
  bool isNeutral;
  DateTime? occurredAt;
  String? fromBrand;
  String? toBrand;

  /// Versement d'épargne détecté (« mets 5 000 de côté »).
  bool isSavings;

  /// « owedToMe » (on me doit) ou « iOwe » (je dois), sinon `null`.
  String? debtDirection;

  double confidence;

  bool get isComplete => amount > 0;
}

/// Analyse locale d'une phrase en français (aucun réseau, aucune clé).
///
/// Exemples reconnus : « j'ai payé 5 000 pour le transport »,
/// « reçu 25 000 salaire », « transféré 10 000 de flooz vers mixx »,
/// « avancé 3 000 pour un client » (argent de tiers).
abstract final class AiCommandParser {
  static final RegExp _amountWithSuffix = RegExp(
    r'(\d[\d .]*)\s*(?:FCFA|XOF|CFA|francs?)?',
    caseSensitive: false,
  );

  static const Map<String, List<String>> _categories = <String, List<String>>{
    'Alimentation': <String>[
      'manger',
      'repas',
      'déjeuner',
      'dejeuner',
      'petit déjeuner',
      'nourriture',
      'restaurant',
      'café',
      'cafe',
      'provisions',
      'maquis',
    ],
    'Transport': <String>[
      'transport',
      'taxi',
      'zémidjan',
      'zemidjan',
      'carburant',
      'essence',
      'moto',
      'bus',
      'trajet',
    ],
    'Loyer': <String>['loyer', 'maison', 'bail'],
    'Santé': <String>[
      'santé',
      'sante',
      'pharmacie',
      'médecin',
      'medecin',
      'hôpital',
      'hopital',
    ],
    'École': <String>[
      'école',
      'ecole',
      'frais scolaires',
      'scolarité',
      'scolarite',
      'fournitures',
    ],
    'Tontine': <String>['tontine', 'cotisation'],
    'Salaire': <String>['salaire', 'paie', 'paye du mois'],
    'Vente': <String>['vente', 'vendu', 'client'],
  };

  static AiDraft? parse(String text, {DateTime? now}) {
    final String lower = text.toLowerCase().trim();
    if (lower.isEmpty) return null;

    final int amount = _extractAmount(lower);
    if (amount <= 0) return null;

    // Détection locale, sans clé ni réseau : l'ordre compte.
    final bool savings = RegExp(
      r'[ée]pargn|mets? de c[ôo]t[ée]|coffre|tirelire| economis',
    ).hasMatch(lower);
    final bool owedToMe = RegExp(
      r'on me doit|il me doit|elle me doit|on doit me|cr[ée]ance|pr[êe]t[ée] [àa]',
    ).hasMatch(lower);
    final bool iOwe = RegExp(
      r'je dois|j’?ai emprunt|j’?emprunte|dette|je rembourse',
    ).hasMatch(lower);

    TransactionKind kind = TransactionKind.expense;
    if (savings) {
      kind = TransactionKind.savings;
    } else if (RegExp(r'transf[ée]r|transfert|envoy[ée] sur').hasMatch(lower)) {
      kind = TransactionKind.transfer;
    } else if (RegExp(
      r're[çc]u|gagn[ée]|salaire|revenu|entr[ée]e|encaiss[ée]|cr[ée]dit|'
      r'on me doit|il me doit|elle me doit',
    ).hasMatch(lower)) {
      kind = TransactionKind.income;
    }

    String? category;
    for (final MapEntry<String, List<String>> entry in _categories.entries) {
      if (entry.value.any((String word) => lower.contains(word))) {
        category = entry.key;
        break;
      }
    }

    final String? from = _brandIn(lower.split('vers').first);
    final String? to = lower.contains('vers')
        ? _brandIn(lower.split('vers').last)
        : null;

    // « On me doit » : l'argent n'est pas encore encaissé → neutre.
    final bool neutral =
        owedToMe ||
        RegExp(
          r'pour (?:un |le |la |mon |ma )?(?:client|tiers|quelqu|autrui)|'
          r'argent de tiers|cotisation|au nom de',
        ).hasMatch(lower);

    DateTime? when = now;
    if (lower.contains('hier')) {
      when = (now ?? DateTime.now()).subtract(const Duration(days: 1));
    } else if (lower.contains('avant-hier')) {
      when = (now ?? DateTime.now()).subtract(const Duration(days: 2));
    }

    return AiDraft(
      kind: kind,
      amount: amount,
      category: category,
      note: text.trim(),
      isNeutral: neutral,
      occurredAt: when,
      fromBrand: from,
      toBrand: to,
      isSavings: savings,
      debtDirection: owedToMe
          ? 'owedToMe'
          : iOwe
          ? 'iOwe'
          : null,
      confidence: category == null ? 0.45 : 0.8,
    );
  }

  /// Extrait un montant : « 5 000 », « 5000 FCFA », « 5k », « 2,5k ».
  static int _extractAmount(String text) {
    final RegExpMatch? k = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*k\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (k != null) {
      final double value =
          double.tryParse(k.group(1)!.replaceAll(',', '.')) ?? 0;
      return (value * 1000).round();
    }

    final RegExpMatch? match = _amountWithSuffix.firstMatch(text);
    if (match == null) return 0;
    final String digits = match
        .group(1)!
        .replaceAll(RegExp(r'[ .]'), '')
        .replaceAll(',', '');
    return int.tryParse(digits) ?? 0;
  }

  static String? _brandIn(String text) {
    if (text.contains('flooz') || text.contains('moov')) return 'flooz';
    if (text.contains('mixx') || text.contains('yas')) return 'mixx';
    if (text.contains('orabank') || text.contains('banque')) return 'orabank';
    if (text.contains('liquide') || text.contains('cash')) return 'liquide';
    return null;
  }
}
