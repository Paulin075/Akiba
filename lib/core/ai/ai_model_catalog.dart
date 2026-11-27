import 'dart:convert';

/// Un modèle de langage utilisable par l'assistant.
class AiModel {
  const AiModel({required this.id, required this.label});

  /// Identifiant envoyé à l'API (`gemini-2.0-flash`).
  final String id;

  /// Nom lisible affiché dans les réglages.
  final String label;

  /// Libellé court pour l'indicateur discret de l'assistant.
  String get shortLabel => label.length <= 22 ? label : label.substring(0, 22);

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'label': label};

  static AiModel? fromJson(Object? value) {
    if (value is! Map) return null;
    final Object? id = value['id'];
    if (id is! String || id.trim().isEmpty) return null;
    final Object? label = value['label'];
    return AiModel(
      id: id.trim(),
      label: label is String && label.trim().isNotEmpty
          ? label.trim()
          : id.trim(),
    );
  }

  @override
  bool operator ==(Object other) => other is AiModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Catalogue des modèles : valeurs de départ, analyse de la réponse de l'API,
/// cache local et ordre de priorité.
///
/// Aucune clé n'est manipulée ici : tout est pur et testable hors réseau.
abstract final class AiModelCatalog {
  /// Modèles proposés tant qu'aucune liste n'a été récupérée.
  ///
  /// Les alias `…-latest` sont préférés aux versions figées : Google les fait
  /// pointer vers le modèle courant, alors qu'une version retirée (les 1.5 ne
  /// répondent plus) provoque une erreur 404 au premier appel.
  static const List<AiModel> seeds = <AiModel>[
    AiModel(id: 'gemini-flash-latest', label: 'Gemini Flash (à jour)'),
    AiModel(
      id: 'gemini-flash-lite-latest',
      label: 'Gemini Flash Lite (à jour)',
    ),
    AiModel(id: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash'),
    AiModel(id: 'gemini-2.5-pro', label: 'Gemini 2.5 Pro'),
  ];

  /// Lit la réponse `models.list` et ne garde que les modèles qui savent
  /// générer du contenu.
  static List<AiModel> parseList(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const <AiModel>[];
    }
    if (decoded is! Map) return const <AiModel>[];
    final Object? raw = decoded['models'];
    if (raw is! List) return const <AiModel>[];

    final List<AiModel> models = <AiModel>[];
    for (final Object? entry in raw) {
      if (entry is! Map) continue;
      final Object? name = entry['name'];
      if (name is! String) continue;
      final List<Object?> methods =
          entry['supportedGenerationMethods'] as List<Object?>? ??
          const <Object?>[];
      if (methods.isNotEmpty && !methods.contains('generateContent')) continue;
      final String id = name.startsWith('models/')
          ? name.substring('models/'.length)
          : name;
      if (id.isEmpty) continue;
      if (models.any((AiModel m) => m.id == id)) continue;
      final Object? display = entry['displayName'];
      models.add(
        AiModel(
          id: id,
          label: display is String && display.trim().isNotEmpty
              ? display.trim()
              : id,
        ),
      );
    }
    return models;
  }

  /// Lit la réponse `data` d'une API compatible OpenAI. Le libellé n'existe
  /// pas : l'identifiant sert des deux côtés.
  static List<AiModel> parseOpenAiList(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const <AiModel>[];
    }
    if (decoded is! Map) return const <AiModel>[];
    final Object? raw = decoded['data'];
    if (raw is! List) return const <AiModel>[];
    final List<AiModel> models = <AiModel>[];
    for (final Object? entry in raw) {
      if (entry is! Map) continue;
      final Object? id = entry['id'];
      if (id is! String || id.trim().isEmpty) continue;
      if (models.any((AiModel model) => model.id == id.trim())) continue;
      models.add(AiModel(id: id.trim(), label: id.trim()));
    }
    return models;
  }

  static String encode(List<AiModel> models) =>
      jsonEncode(models.map((AiModel m) => m.toJson()).toList());

  /// Relit le cache ; toute anomalie retombe sur les modèles de départ.
  static List<AiModel> decode(String raw) {
    if (raw.trim().isEmpty) return seeds;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return seeds;
    }
    if (decoded is! List) return seeds;
    final List<AiModel> models = <AiModel>[
      for (final Object? entry in decoded)
        if (AiModel.fromJson(entry) case final AiModel model) model,
    ];
    return models.isEmpty ? seeds : models;
  }

  /// Modèles réellement utilisables : l'ordre enregistré, sans les modèles
  /// décochés. Un réglage vide signifie « tous les modèles connus ».
  ///
  /// Un identifiant enregistré mais absent du catalogue est ignoré : il ne
  /// peut donc pas bloquer un appel sur un modèle inexistant.
  static List<AiModel> selected(List<AiModel> available, String stored) {
    final List<String> order = stored
        .split(',')
        .map((String id) => id.trim())
        .where((String id) => id.isNotEmpty)
        .toList();
    if (order.isEmpty) return available;
    return <AiModel>[
      for (final String id in order)
        for (final AiModel model in available)
          if (model.id == id) model,
    ];
  }
}
