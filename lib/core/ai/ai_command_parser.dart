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
    this.isSavingsGoal = false,
    this.dailyAmount = 0,
    this.goalName,
    this.targetAmount = 0,
    this.debtDirection,
    this.counterparty,
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

  /// Objectif d'épargne récurrent (« 100 FCFA par jour pour un moniteur »).
  /// Dans ce cas [amount] et [dailyAmount] valent le versement quotidien ;
  /// aucune dépense n'est enregistrée : un coffre est créé.
  bool isSavingsGoal;

  /// Montant mis de côté à chaque versement quotidien.
  int dailyAmount;

  /// Nom de l'objectif (« Moniteur »), sans montant ni phrase entière.
  String? goalName;

  /// Prix de l'objectif, quand la phrase le donne explicitement.
  int targetAmount;

  /// « owedToMe » (on me doit) ou « iOwe » (je dois), sinon `null`.
  String? debtDirection;

  /// Nom du contact extrait de la phrase (« Koffi me doit 5 000 »).
  String? counterparty;

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
    // Créance / dette d'abord : « Koffi me doit 5 000 » n'est ni une entrée
    // d'argent ni une sortie, et « je dois 5 000 à Ama » n'est pas une dépense
    // payée. Ces phrases créent une créance ou une dette, hors solde disponible.
    final _DebtPhrase? debt = _detectDebt(text);
    final bool owedToMe = debt?.direction == 'owedToMe';
    final bool iOwe = debt?.direction == 'iOwe';

    final bool savings =
        !owedToMe &&
        !iOwe &&
        (RegExp(r'[ée]pargn|coffre|tirelire| economis').hasMatch(lower) ||
            RegExp(r'\b(?:mets?|mettre|met)\b.*de c[ôo]t[ée]').hasMatch(lower));

    // Objectif d'épargne récurrent : « 100 francs par jour pour un moniteur ».
    // Le montant de la phrase est alors le versement quotidien, pas une
    // dépense : l'analyse locale le décide avant tout modèle distant, sinon
    // une telle phrase était comprise comme une sortie « Alimentation ».
    final bool recurring =
        savings &&
        RegExp(
          r'\b(?:par|chaque|tous les)\s+jours?\b|quotidien|'
          r'chaque\s+journ[ée]e',
        ).hasMatch(lower);
    if (recurring) {
      final DateTime base = now ?? DateTime.now();
      // Le premier versement est daté au jour (pas à l'heure de la phrase) :
      // « demain » devient le lendemain à minuit, comme un rappel quotidien.
      final DateTime start = lower.contains('demain')
          ? DateTime(
              base.year,
              base.month,
              base.day,
            ).add(const Duration(days: 1))
          : base;
      final int daily = _amountBeforeRate(lower) ?? amount;
      final String? goal = _goalName(text);
      return AiDraft(
        kind: TransactionKind.savings,
        amount: daily,
        note: goal ?? 'Objectif',
        isSavings: true,
        isSavingsGoal: true,
        dailyAmount: daily,
        goalName: goal ?? 'Objectif',
        occurredAt: start,
        confidence: goal != null ? 0.85 : 0.7,
      );
    }

    TransactionKind kind = TransactionKind.expense;
    if (savings) {
      kind = TransactionKind.savings;
    } else if (owedToMe) {
      // Argent attendu : rien n'entre en caisse aujourd'hui.
      kind = TransactionKind.income;
    } else if (RegExp(r'transf[ée]r|transfert|envoy[ée] sur').hasMatch(lower)) {
      kind = TransactionKind.transfer;
    } else if (RegExp(
      r're[çc]u|gagn[ée]|salaire|revenu|entr[ée]e|encaiss[ée]|cr[ée]dit',
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

    // « On me doit » / « je dois » : jamais une sortie neutre. Le suivi de la
    // créance ou de la dette est séparé du solde disponible ; neutraliser la
    // ligne la ferait disparaître des comptes sans la suivre.
    final bool neutral =
        !owedToMe &&
        !iOwe &&
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
      debtDirection: debt?.direction,
      counterparty: debt?.counterparty,
      confidence: debt != null ? 0.85 : (category == null ? 0.45 : 0.8),
    );
  }

  /// Reconnaît « on me doit », « Koffi me doit », « je dois à … ».
  ///
  /// En cas de phrase contenant les deux formes, la première citée gagne.
  /// Aucune écriture n'est faite ici : seul le sens est proposé.
  static _DebtPhrase? _detectDebt(String text) {
    final RegExpMatch? owed = RegExp(
      r"([\p{L}][\p{L}’'-]*)\s+me\s+(?:doit|doivent|redoivent|redoive|revaudra)|"
      r'me\s+(?:doit|doivent|redoivent|redoive|revaudra)|'
      r'cr[ée]ance|je\s+dois\s+recevoir|'
      r'j’?ai\s+pr[êe]t[ée]|pr[êe]t[ée]\s+[àa]|rembourse[rz]?\s+moi',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(text);
    final RegExpMatch? owes = RegExp(
      r'je\s+dois|je\s+doit|j’?ai\s+emprunt[ée]?|j’?emprunte|'
      r'je\s+rembourse|je\s+rembourserai|ma\s+dette|une\s+dette|'
      r'je\s+suis\s+redevable',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(text);

    if (owed == null && owes == null) return null;
    final bool owedFirst =
        owes == null || (owed != null && owed.start <= owes.start);
    if (owedFirst && owed != null) {
      return _DebtPhrase(
        direction: 'owedToMe',
        counterparty: _oweName(text, owed),
      );
    }
    return _DebtPhrase(direction: 'iOwe', counterparty: _debtName(text, owes!));
  }

  static final RegExp _stopWords = RegExp(
    r"^(?:le|la|les|un|une|des|du|de|mon|ma|mes|ton|ta|tes|son|sa|ses|"
    r"moi|toi|lui|on|il|elle|ils|elles|quelqu’?un|pour|avec|et|puis|ensuite|"
    r"hier|aujourd’?hui|demain|ce|mois|semaine)$",
    caseSensitive: false,
    unicode: true,
  );

  /// Nom du contact pour « Koffi me doit 5 000 ».
  static String? _oweName(String text, RegExpMatch match) {
    final String? captured = match.group(1);
    if (captured != null && !_stopWords.hasMatch(captured)) {
      return _capitalise(captured);
    }
    final String before = text.substring(0, match.start).trim();
    final List<String> words = before
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty && !RegExp(r'^\d').hasMatch(w))
        .toList(growable: false);
    for (int i = words.length - 1; i >= 0; i--) {
      final String word = words[i].replaceAll(
        RegExp(r"[^\p{L}’'-]", unicode: true),
        '',
      );
      if (word.isEmpty || _stopWords.hasMatch(word)) continue;
      return _capitalise(word);
    }
    return null;
  }

  /// Nom du contact pour « je dois 5 000 à Ama ».
  static String? _debtName(String text, RegExpMatch match) {
    final String after = text.substring(match.end);
    final RegExpMatch? to = RegExp(
      r"(?:^|\s)(?:à|a|chez|envers)\s+([\p{L}][\p{L}’'-]*)",
      caseSensitive: false,
      unicode: true,
    ).firstMatch(after);
    if (to != null) return _capitalise(to.group(1)!);
    return null;
  }

  static String _capitalise(String word) =>
      word[0].toUpperCase() + word.substring(1).toLowerCase();

  /// Montant placé juste avant « par jour » / « chaque jour ».
  ///
  /// « mettre 100 francs par jour » donne 100, même si la phrase contient un
  /// autre nombre (prix de l'objet, échéance).
  static int? _amountBeforeRate(String text) {
    final RegExpMatch? match = RegExp(
      r'(\d[\d .]*)\s*(?:FCFA|XOF|CFA|francs?)?\s*'
      r'(?:par|chaque|tous les)\s+jours?',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    final String digits = match
        .group(1)!
        .replaceAll(RegExp(r'[ .]'), '')
        .replaceAll(',', '');
    final int value = int.tryParse(digits) ?? 0;
    return value > 0 ? value : null;
  }

  /// Nom de l'objectif acheté : « pour me payer un moniteur » → « Moniteur ».
  ///
  /// Seuls les deux premiers mots utiles sont gardés : le reste de la phrase
  /// (« donc tu peux créer… ») n'est jamais un nom de coffre.
  static String? _goalName(String text) {
    final RegExpMatch? match = RegExp(
      r"(?:m['’]acheter|me payer|acheter|payer|pour)\s+"
      r"(?:un|une|mon|ma|mes|le|la|les|des|du)\s+"
      r"([\p{L}][\p{L}’' -]{1,40})",
      caseSensitive: false,
      unicode: true,
    ).firstMatch(text);
    if (match == null) return null;
    const Set<String> stop = <String>{
      'donc',
      'pour',
      'afin',
      'et',
      'puis',
      'tu',
      'je',
      'il',
      'elle',
      'que',
      'qui',
      'car',
      'ainsi',
      'avec',
      'dans',
      'si',
      'en',
      'a',
      'à',
      'de',
      'du',
      'des',
      'mon',
      'ma',
      'mes',
      'le',
      'la',
      'les',
      'un',
      'une',
      'peux',
      'peut',
      'pouvoir',
      'veux',
      'veut',
      'dois',
      'doit',
      'faut',
      'créer',
      'creer',
      'commencer',
      'économiser',
      'economiser',
    };
    // Les mots sont pris dans l'ordre et s'arrêtent au premier mot grammatical :
    // « moniteur donc tu peux… » ne garde que « moniteur ».
    final List<String> words = <String>[];
    for (final String raw in match.group(1)!.split(RegExp(r'\s+'))) {
      final String word = raw.trim();
      if (word.isEmpty) continue;
      if (stop.contains(word.toLowerCase())) break;
      words.add(word);
      if (words.length == 2) break;
    }
    if (words.isEmpty) return null;
    return words.map(_capitalise).join(' ');
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
    if (match == null) {
      // Dictée : le moteur vocal écrit souvent les nombres en lettres
      // (« Guy me doit trois mille francs »).
      return _extractNumberWords(text);
    }
    final String digits = match
        .group(1)!
        .replaceAll(RegExp(r'[ .]'), '')
        .replaceAll(',', '');
    final int parsed = int.tryParse(digits) ?? 0;
    return parsed > 0 ? parsed : _extractNumberWords(text);
  }

  /// Nombres écrits en lettres, comme les rend souvent la reconnaissance
  /// vocale française : « trois mille », « douze mille cinq cents »,
  /// « quatre-vingt mille », « un million ».
  ///
  /// Le résultat n'est retenu que si la phrase contient un multiplicateur
  /// (cent, mille, million) : « un café » ne devient jamais 1 FCFA.
  static int _extractNumberWords(String text) {
    const Map<String, int> units = <String, int>{
      'zero': 0,
      'un': 1,
      'une': 1,
      'deux': 2,
      'trois': 3,
      'quatre': 4,
      'cinq': 5,
      'six': 6,
      'sept': 7,
      'huit': 8,
      'neuf': 9,
      'dix': 10,
      'onze': 11,
      'douze': 12,
      'treize': 13,
      'quatorze': 14,
      'quinze': 15,
      'seize': 16,
      'vingt': 20,
      'trente': 30,
      'quarante': 40,
      'cinquante': 50,
      'soixante': 60,
      'cent': 100,
      'mille': 1000,
      'million': 1000000,
    };

    int total = 0;
    int current = 0;
    bool multiplier = false;

    for (final RegExpMatch match in RegExp(
      r"[a-zàâäéèêëîïôöùûüçœ]+",
    ).allMatches(text)) {
      final String word = match.group(0)!;
      // Pluriels : « cents », « millions ». Le mot exact est essayé d'abord
      // pour ne pas casser « trois » (qui finit par s).
      int? value = units[word];
      if (value == null && word.endsWith('s') && word.length > 2) {
        value = units[word.substring(0, word.length - 1)];
      }
      if (value == null) continue;
      if (value >= 1000) {
        multiplier = true;
        total += (current == 0 ? 1 : current) * value;
        current = 0;
      } else if (value == 100) {
        multiplier = true;
        current = (current == 0 ? 1 : current) * 100;
      } else if (value == 20 && current == 4) {
        // « quatre-vingt(s) » vaut 80, pas 24.
        current = 80;
      } else {
        current += value;
      }
    }

    final int amount = total + current;
    if (!multiplier || amount <= 0) return 0;
    return amount.clamp(0, 999999999);
  }

  static String? _brandIn(String text) {
    if (text.contains('flooz') || text.contains('moov')) return 'flooz';
    if (text.contains('mixx') || text.contains('yas')) return 'mixx';
    if (text.contains('orabank') || text.contains('banque')) return 'orabank';
    if (text.contains('liquide') || text.contains('cash')) return 'liquide';
    return null;
  }
}

/// Sens détecté pour une phrase de créance ou de dette.
///
/// `direction` vaut exactement `owedToMe` (on me doit) ou `iOwe` (je dois),
/// comme la colonne `direction` de la table `debts`.
class _DebtPhrase {
  const _DebtPhrase({required this.direction, this.counterparty});

  final String direction;
  final String? counterparty;
}
