import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_model_catalog.dart';
import 'ai_provider.dart';

/// Nature de la tâche : elle fixe le délai maximal de réponse.
///
/// Les tâches courtes restent impatientes (une saisie ne doit jamais faire
/// attendre), les analyses acceptent un peu plus de latence.
enum AiTask {
  quickEntry(Duration(seconds: 5), 'Saisie rapide'),
  smsReview(Duration(seconds: 6), 'Revue SMS'),
  analysis(Duration(seconds: 18), 'Analyse'),
  coaching(Duration(seconds: 12), 'Coaching');

  const AiTask(this.timeout, this.label);

  final Duration timeout;
  final String label;

  int get seconds => timeout.inSeconds;
}

/// Pourquoi un modèle n'a pas répondu.
enum AiFailureKind {
  timeout('délai dépassé', 'Le modèle n’a pas répondu à temps.'),
  quota(
    'quota ou débit',
    'Quota atteint ou trop de requêtes : réessayez plus tard.',
  ),
  server('service indisponible', 'Le service a renvoyé une erreur.'),
  model(
    'modèle introuvable',
    'Ce modèle n’existe plus ou n’est pas autorisé pour cette clé : '
        'choisissez-en un autre dans la liste.',
  ),
  auth(
    'clé refusée',
    'La clé API est refusée : vérifiez-la dans les réglages (elle doit être '
        'complète, sans espace ni guillemet).',
  ),
  network('hors ligne', 'Aucune connexion exploitable.'),
  invalidResponse('réponse illisible', 'Le modèle a répondu hors format.');

  const AiFailureKind(this.label, this.hint);

  final String label;
  final String hint;

  /// Une clé refusée arrête la cascade : inutile d'essayer les autres modèles.
  bool get isTerminal => this == AiFailureKind.auth;
}

/// Erreur HTTP portant le code, traduite en [AiFailureKind].
class AiHttpException implements Exception {
  const AiHttpException(this.statusCode, [this.detail = '']);

  final int statusCode;

  /// Message du fournisseur, tronqué et jamais journalisé : il sert à classer
  /// l'échec, pas à être affiché tel quel.
  final String detail;

  AiFailureKind get kind {
    final String text = detail.toLowerCase();
    if (statusCode == 401 || statusCode == 403) return AiFailureKind.auth;
    if (statusCode == 429) return AiFailureKind.quota;
    if (statusCode >= 500) return AiFailureKind.server;
    if (statusCode == 408 || statusCode == 504) return AiFailureKind.timeout;
    if (statusCode == 404) return AiFailureKind.model;
    // 400 est ambigu : Gemini y place la clé refusée (`400 API_KEY_INVALID`),
    // un modèle retiré ou une requête refusée. Le corps tranche, sinon la
    // personne lisait « hors format » alors que sa clé était simplement
    // refusée.
    if (_mentions(text, _authSigns)) return AiFailureKind.auth;
    if (_mentions(text, _quotaSigns)) return AiFailureKind.quota;
    if (_mentions(text, _modelSigns)) return AiFailureKind.model;
    return AiFailureKind.invalidResponse;
  }

  @override
  String toString() => 'AiHttpException($statusCode)';
}

/// Safe, user-facing category for failures in the settings connectivity check.
class AiTestException implements Exception {
  const AiTestException(this.kind);

  final AiFailureKind kind;

  String get message => kind.hint;
}

/// Signature d'un envoi : remplaçable par un faux transport dans les tests.
typedef AiTransport =
    Future<String> Function({
      required String modelId,
      required String prompt,
      required Duration timeout,
    });

/// Une tentative, conservée pour l'indicateur discret et le diagnostic.
class AiAttempt {
  const AiAttempt({
    required this.modelId,
    required this.kind,
    required this.elapsed,
  });

  final String modelId;
  final AiFailureKind kind;
  final Duration elapsed;
}

/// Résultat d'un appel : soit un texte, soit un motif de repli.
class AiCallResult {
  const AiCallResult({
    this.text,
    this.modelId,
    this.failure,
    this.attempts = const <AiAttempt>[],
  });

  const AiCallResult.failed(AiFailureKind kind, {this.attempts = const []})
    : text = null,
      modelId = null,
      failure = kind;

  final String? text;
  final String? modelId;
  final AiFailureKind? failure;
  final List<AiAttempt> attempts;

  bool get ok => text != null;

  /// Mention discrète affichée dans l'assistant.
  String get note {
    if (ok) return 'Modèle : ${modelId ?? 'inconnu'}';
    final String reason = failure?.label ?? 'indisponible';
    return attempts.isEmpty
        ? 'Analyse locale · $reason'
        : 'Analyse locale · $reason (${attempts.length} essai'
              '${attempts.length > 1 ? 's' : ''})';
  }
}

/// Client IA avec cascade de modèles.
///
/// Règles appliquées :
/// - un seul essai par modèle, plafonné par `maxAttempts` ;
/// - délai propre à la tâche (5 / 6 / 10 / 12 s) ;
/// - bascule sur le modèle suivant si délai dépassé, 429, 5xx, réseau ;
/// - arrêt immédiat si la clé est refusée (inutile d'insister) ;
/// - un modèle qui échoue deux fois de suite est mis en veille 10 minutes ;
/// - aucun appel n'écrit quoi que ce soit : le texte revient à l'interface.
class AkibaAiClient {
  AkibaAiClient({
    required List<AiModel> models,
    required this.transport,
    this.maxAttempts = 3,
    this.cooldown = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : models = List<AiModel>.unmodifiable(models),
       _now = now ?? DateTime.now;

  final List<AiModel> models;
  final int maxAttempts;
  final Duration cooldown;
  final AiTransport transport;
  final DateTime Function() _now;

  final Map<String, int> _failures = <String, int>{};
  final Map<String, DateTime> _sleepingUntil = <String, DateTime>{};

  bool isSleeping(String modelId) {
    final DateTime? until = _sleepingUntil[modelId];
    if (until == null) return false;
    if (until.isAfter(_now())) return true;
    _sleepingUntil.remove(modelId);
    _failures.remove(modelId);
    return false;
  }

  /// Modèles réellement sollicités, dans l'ordre, sans ceux en veille.
  List<AiModel> get chain =>
      models.where((AiModel m) => !isSleeping(m.id)).toList(growable: false);

  Future<AiCallResult> generate({
    required AiTask task,
    required String prompt,
  }) async {
    final List<AiAttempt> attempts = <AiAttempt>[];
    final List<AiModel> chain = this.chain;
    if (chain.isEmpty) {
      return const AiCallResult.failed(AiFailureKind.quota);
    }

    int provided = 0;
    for (final AiModel model in chain) {
      if (provided >= maxAttempts) break;
      provided++;
      final Stopwatch watch = Stopwatch()..start();
      try {
        final String text = await transport(
          modelId: model.id,
          prompt: prompt,
          timeout: task.timeout,
        ).timeout(task.timeout);
        if (text.trim().isEmpty) throw const FormatException('réponse vide');
        _failures[model.id] = 0;
        return AiCallResult(text: text, modelId: model.id, attempts: attempts);
      } on TimeoutException catch (_) {
        attempts.add(
          AiAttempt(
            modelId: model.id,
            kind: AiFailureKind.timeout,
            elapsed: watch.elapsed,
          ),
        );
        _registerFailure(model.id);
      } on AiHttpException catch (error) {
        attempts.add(
          AiAttempt(
            modelId: model.id,
            kind: error.kind,
            elapsed: watch.elapsed,
          ),
        );
        _registerFailure(model.id);
        if (error.kind.isTerminal) {
          return AiCallResult.failed(error.kind, attempts: attempts);
        }
      } on FormatException catch (_) {
        attempts.add(
          AiAttempt(
            modelId: model.id,
            kind: AiFailureKind.invalidResponse,
            elapsed: watch.elapsed,
          ),
        );
        _registerFailure(model.id);
      } catch (_) {
        // Erreur réseau, DNS, TLS : jamais de détail technique dans l'UI.
        attempts.add(
          AiAttempt(
            modelId: model.id,
            kind: AiFailureKind.network,
            elapsed: watch.elapsed,
          ),
        );
        _registerFailure(model.id);
      }
    }

    return AiCallResult.failed(
      attempts.isEmpty ? AiFailureKind.quota : attempts.last.kind,
      attempts: attempts,
    );
  }

  void _registerFailure(String modelId) {
    final int count = (_failures[modelId] ?? 0) + 1;
    _failures[modelId] = count;
    if (count >= 2) _sleepingUntil[modelId] = _now().add(cooldown);
  }
}

/// Requête prête à envoyer : URI, en-têtes et corps JSON.
///
/// Séparer la construction de l'envoi permet de vérifier le routage par
/// fournisseur (Gemini natif ou `/chat/completions`) sans aucun réseau.
class AiProviderCall {
  const AiProviderCall({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

/// Construit l'appel du fournisseur, sans jamais journaliser la clé.
AiProviderCall buildAiProviderCall({
  required AiProvider provider,
  required String baseUrl,
  String? apiKey,
  required String modelId,
  required String prompt,
  bool jsonMode = true,
  // Les modèles « à réflexion » consomment des jetons avant de répondre :
  // une limite trop basse renvoyait une réponse vide (donc « hors format »).
  int maxOutputTokens = 1024,
}) {
  final String base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final Map<String, String> headers = <String, String>{
    'Content-Type': 'application/json',
  };

  if (provider.isGemini) {
    // La clé part en en-tête `x-goog-api-key` : Google l'accepte pour les clés
    // historiques (`AIza…`) comme pour les nouvelles (`AQ.…`), alors qu'un
    // `?key=` ne convient pas à toutes. L'URL ne contient donc plus la clé.
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['x-goog-api-key'] = apiKey;
    }
    return AiProviderCall(
      uri: Uri.parse('$base/models/$modelId:generateContent'),
      headers: headers,
      body: jsonEncode(<String, Object?>{
        'contents': <Object?>[
          <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{'text': prompt},
            ],
          },
        ],
        'generationConfig': <String, Object?>{
          'temperature': 0.2,
          'maxOutputTokens': maxOutputTokens,
          // Le diagnostic de connexion attend une phrase lisible ; les ordres
          // de l'assistant, eux, restent contraints au JSON.
          if (jsonMode) 'responseMimeType': 'application/json',
        },
      }),
    );
  }

  // DeepSeek, OpenRouter, Ollama : dialecte OpenAI. Le jeton est facultatif
  // (une instance locale peut accepter les appels sans authentification).
  if (apiKey != null && apiKey.isNotEmpty) {
    headers['Authorization'] = 'Bearer $apiKey';
  }
  return AiProviderCall(
    uri: Uri.parse('$base/chat/completions'),
    headers: headers,
    body: jsonEncode(<String, Object?>{
      'model': modelId,
      'messages': <Object?>[
        <String, Object?>{'role': 'user', 'content': prompt},
      ],
      'temperature': 0.2,
      'max_tokens': maxOutputTokens,
      'stream': false,
    }),
  );
}

/// Lit la réponse du fournisseur et n'en garde que le texte.
///
/// Tolérant à dessein : Gemini peut renvoyer plusieurs candidats ou des
/// parties de raisonnement, et les API compatibles OpenAI exposent le texte
/// sous `content`, `reasoning_content`, `text` ou une liste de parties. Toute
/// réponse texte réellement exploitable est acceptée ; seul un corps vide,
/// illisible ou sans aucun texte lève [FormatException].
///
/// [allowPlainText] accepte un corps qui n'est pas du JSON (certains proxys
/// locaux renvoient le texte directement). Réservé au diagnostic de connexion.
String extractAiText(
  AiProvider provider,
  String body, {
  bool allowPlainText = false,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    if (allowPlainText) return _requireText(body);
    throw const FormatException('réponse non JSON');
  }
  if (decoded is! Map) {
    if (allowPlainText && decoded is String) return _requireText(decoded);
    throw const FormatException('réponse inattendue');
  }

  if (provider.isGemini) {
    final StringBuffer buffer = StringBuffer();
    final Object? candidates = decoded['candidates'];
    if (candidates is List) {
      for (final Object? candidate in candidates) {
        if (candidate is! Map) continue;
        final Object? content = candidate['content'];
        if (content is! Map) continue;
        final Object? parts = content['parts'];
        if (parts is! List) continue;
        for (final Object? part in parts) {
          // `thought: true` = raisonnement interne, jamais la réponse.
          if (part is Map &&
              part['thought'] != true &&
              part['text'] is String) {
            buffer.write(part['text'] as String);
          }
        }
      }
    }
    final String text = buffer.toString();
    if (text.trim().isNotEmpty) return _requireText(text);
    // Repli : certains proxys aplatissent la réponse à la racine.
    return _firstString(decoded, const <String>[
      'text',
      'output_text',
      'response',
    ]);
  }

  final Object? choices = decoded['choices'];
  if (choices is List) {
    for (final Object? choice in choices) {
      if (choice is! Map) continue;
      final Object? message = choice['message'];
      if (message is Map) {
        final Object? content = message['content'];
        if (content is String && content.trim().isNotEmpty) {
          return _requireText(content);
        }
        if (content is List) {
          final StringBuffer buffer = StringBuffer();
          for (final Object? part in content) {
            if (part is Map && part['text'] is String) {
              buffer.write(part['text'] as String);
            }
          }
          if (buffer.toString().trim().isNotEmpty) {
            return _requireText(buffer.toString());
          }
        }
        // Modèles à raisonnement : le texte utile peut être ici alors que
        // `content` est vide (DeepSeek Reasoner, Qwen, proxies Ollama).
        for (final String key in const <String>[
          'reasoning_content',
          'reasoning',
          'text',
        ]) {
          final Object? value = message[key];
          if (value is String && value.trim().isNotEmpty) {
            return _requireText(value);
          }
        }
      }
      final Object? legacy = choice['text'];
      if (legacy is String && legacy.trim().isNotEmpty) {
        return _requireText(legacy);
      }
    }
  }
  return _firstString(decoded, const <String>[
    'text',
    'output_text',
    'response',
    'content',
  ]);
}

String _firstString(Map<dynamic, dynamic> source, List<String> keys) {
  for (final String key in keys) {
    final Object? value = source[key];
    if (value is String && value.trim().isNotEmpty) {
      return _requireText(value);
    }
  }
  throw const FormatException('contenu absent');
}

String _requireText(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) throw const FormatException('texte vide');
  return text;
}

/// Texte d'erreur d'un fournisseur, tronqué, pour **classer** l'échec.
///
/// Les codes seuls ne suffisent pas : Gemini répond `400 API_KEY_INVALID`
/// pour une clé refusée, `404` pour un modèle retiré et `503` en cas de
/// surcharge. On lit donc `error.status`, `error.message` et
/// `details[].reason`. La clé n'est jamais recopiée : le corps ne la contient
/// pas, et la valeur n'est ni journalisée ni affichée.
String aiErrorText(String body, {String secret = ''}) {
  final String text = body.trim();
  if (text.isEmpty || text.startsWith('<')) return '';
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return _clipError(_redactSecret(text, secret));
  }
  if (decoded is! Map) return '';

  final Object? error = decoded['error'];
  if (error is Map) {
    final StringBuffer buffer = StringBuffer();
    for (final String key in const <String>['message', 'status']) {
      final Object? value = error[key];
      if (value is String && value.trim().isNotEmpty) {
        buffer.write(' ${value.trim()}');
      }
    }
    final Object? details = error['details'];
    if (details is List) {
      for (final Object? item in details) {
        if (item is Map && item['reason'] is String) {
          buffer.write(' ${(item['reason'] as String).trim()}');
        }
      }
    }
    final String joined = buffer.toString().trim();
    if (joined.isNotEmpty) return _clipError(_redactSecret(joined, secret));
  }
  for (final String key in const <String>['message', 'detail', 'error']) {
    final Object? value = decoded[key];
    if (value is String && value.trim().isNotEmpty) {
      return _clipError(_redactSecret(value.trim(), secret));
    }
  }
  return '';
}

String _clipError(String value) =>
    value.length <= 300 ? value : value.substring(0, 300);

/// Retire la clé d'un texte d'erreur.
///
/// Certains fournisseurs recopient la clé reçue dans leur message ("Incorrect
/// API key provided: sk-…"). Ce détail ne sert qu'à classer l'échec et n'est
/// jamais affiché, mais il ne doit pas non plus pouvoir l'être un jour.
String _redactSecret(String value, String secret) {
  final String key = secret.trim();
  if (key.length < 8) return value;
  return value.replaceAll(key, '••••');
}

const List<String> _authSigns = <String>[
  'api_key_invalid',
  'api key not valid',
  'invalid api key',
  'invalid_api_key',
  'incorrect api key',
  'unauthenticated',
  'credentials_missing',
  'access_token_type_unsupported',
  'permission_denied',
];

const List<String> _quotaSigns = <String>[
  'resource_exhausted',
  'quota',
  'rate limit',
  'rate_limit',
  'too many requests',
];

const List<String> _modelSigns = <String>[
  'not_found',
  'not found',
  'no such model',
  'unknown model',
  'model_not_found',
  'not supported',
  'does not exist',
  'deprecated',
];

bool _mentions(String haystack, List<String> needles) =>
    needles.any(haystack.contains);

/// Envoi réel vers Gemini (API native).
///
/// La clé n'est jamais journalisée ; l'URL complète non plus (elle la contient).
class GeminiTransport {
  GeminiTransport({required this.apiKey});

  final String apiKey;

  static const String base = 'https://generativelanguage.googleapis.com/v1beta';

  Future<String> call({
    required String modelId,
    required String prompt,
    required Duration timeout,
  }) => _send(
    provider: AiProvider.gemini,
    baseUrl: base,
    apiKey: apiKey,
    modelId: modelId,
    prompt: prompt,
    timeout: timeout,
  );
}

/// Envoi réel vers une API compatible OpenAI (`/v1/chat/completions`).
class OpenAiCompatibleTransport {
  OpenAiCompatibleTransport({
    required this.provider,
    required this.baseUrl,
    this.apiKey,
  });

  final AiProvider provider;
  final String baseUrl;
  final String? apiKey;

  Future<String> call({
    required String modelId,
    required String prompt,
    required Duration timeout,
  }) => _send(
    provider: provider,
    baseUrl: baseUrl,
    apiKey: apiKey,
    modelId: modelId,
    prompt: prompt,
    timeout: timeout,
  );
}

Future<String> _send({
  required AiProvider provider,
  required String baseUrl,
  required String? apiKey,
  required String modelId,
  required String prompt,
  required Duration timeout,
}) async {
  final AiProviderCall call = buildAiProviderCall(
    provider: provider,
    baseUrl: baseUrl,
    apiKey: apiKey,
    modelId: modelId,
    prompt: prompt,
  );
  final HttpClient client = HttpClient()..connectionTimeout = timeout;
  try {
    final HttpClientRequest request = await client
        .postUrl(call.uri)
        .timeout(timeout);
    call.headers.forEach(request.headers.set);
    // `write` encoderait en latin1 faute de charset déclaré : les accents
    // français partaient alors en octets invalides. On envoie de l'UTF-8.
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(call.body));
    final HttpClientResponse response = await request.close().timeout(timeout);
    final String body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw AiHttpException(
        response.statusCode,
        aiErrorText(body, secret: apiKey ?? ''),
      );
    }
    return extractAiText(provider, body);
  } finally {
    client.close(force: true);
  }
}

/// Résultat de la récupération de la liste des modèles.
class AiModelsFetch {
  const AiModelsFetch({this.models = const <AiModel>[], this.failure});

  final List<AiModel> models;
  final AiFailureKind? failure;

  bool get ok => models.isNotEmpty && failure == null;

  String get note {
    if (ok) {
      return '${models.length} modèle${models.length > 1 ? 's' : ''} '
          'disponible${models.length > 1 ? 's' : ''}';
    }
    return failure?.hint ?? 'Liste indisponible.';
  }
}

/// Récupère les modèles proposés par le fournisseur (`models.list`).
///
/// Gemini répond `{models: […]}` ; les API compatibles OpenAI répondent
/// `{data: [{id: …}]}`. En cas d'échec, la liste en cache reste utilisée.
Future<AiModelsFetch> fetchAiModels({
  required AiProvider provider,
  required String baseUrl,
  String? apiKey,
  // 8 s suffisaient à peine sur un réseau mobile : la liste des modèles
  // échouait alors en « délai dépassé » avant même le test du modèle.
  Duration timeout = const Duration(seconds: 20),
}) async {
  final String base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final HttpClient client = HttpClient()..connectionTimeout = timeout;
  try {
    final HttpClientRequest request = await client
        .getUrl(Uri.parse('$base/models'))
        .timeout(timeout);
    if (provider.isGemini) {
      // Même en-tête que la génération : valable pour les clés `AIza…` que
      // pour les nouvelles clés `AQ.…`, et la clé reste hors de l'URL.
      if (apiKey != null && apiKey.isNotEmpty) {
        request.headers.set('x-goog-api-key', apiKey);
      }
      request.headers.set('Accept', 'application/json');
    } else if (apiKey != null && apiKey.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $apiKey');
    }
    final HttpClientResponse response = await request.close().timeout(timeout);
    final String body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    if (response.statusCode != 200) {
      return AiModelsFetch(
        failure: AiHttpException(
          response.statusCode,
          aiErrorText(body, secret: apiKey ?? ''),
        ).kind,
      );
    }
    final List<AiModel> models = provider.isGemini
        ? AiModelCatalog.parseList(body)
        : AiModelCatalog.parseOpenAiList(body);
    return AiModelsFetch(
      models: models,
      failure: models.isEmpty ? AiFailureKind.invalidResponse : null,
    );
  } on TimeoutException catch (_) {
    return const AiModelsFetch(failure: AiFailureKind.timeout);
  } catch (_) {
    return const AiModelsFetch(failure: AiFailureKind.network);
  } finally {
    client.close(force: true);
  }
}

/// Sends a short diagnostic prompt and returns the provider's actual reply.
/// This is a settings check, so it does not modify the daily assistant quota.
Future<String> fetchAiTestReply({
  required AiProvider provider,
  required String baseUrl,
  String? apiKey,
  required String modelId,
  // Un modèle qui « réfléchit » dépasse facilement 8 s : le diagnostic attend
  // vraiment sa réponse au lieu d'annoncer un délai dépassé à tort.
  Duration timeout = const Duration(seconds: 40),
}) async {
  try {
    return await _fetchAiTestReplyOnce(
      provider: provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelId: modelId,
      timeout: timeout,
    );
  } on AiTestException catch (error) {
    // 5xx = surcharge passagère du fournisseur : un seul second essai.
    if (error.kind != AiFailureKind.server) rethrow;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return _fetchAiTestReplyOnce(
      provider: provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelId: modelId,
      timeout: timeout,
    );
  }
}

Future<String> _fetchAiTestReplyOnce({
  required AiProvider provider,
  required String baseUrl,
  String? apiKey,
  required String modelId,
  required Duration timeout,
}) async {
  final HttpClient client = HttpClient()..connectionTimeout = timeout;
  try {
    final AiProviderCall call = buildAiProviderCall(
      provider: provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelId: modelId,
      prompt: 'Réponds uniquement par: AKIBA OK',
      // Gemini ne doit pas forcer un JSON pour une réponse de diagnostic.
      jsonMode: false,
      // Assez de jetons pour les modèles à réflexion : sans cela, la réponse
      // revenait vide et le test annonçait « hors format » à tort.
      maxOutputTokens: 1024,
    );
    final HttpClientRequest request = await client
        .postUrl(call.uri)
        .timeout(timeout);
    call.headers.forEach(request.headers.set);
    // UTF-8 explicite : sans charset, `write` encoderait en latin1 et le
    // fournisseur recevrait un corps invalide (accents).
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(call.body));
    final HttpClientResponse response = await request.close().timeout(timeout);
    final String body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw AiHttpException(
        response.statusCode,
        aiErrorText(body, secret: apiKey ?? ''),
      );
    }
    // Un corps texte non JSON reste une réponse valide pour un diagnostic.
    final String reply = extractAiText(
      provider,
      body,
      allowPlainText: true,
    ).trim();
    if (reply.isEmpty) throw const FormatException('empty test reply');
    return reply;
  } on AiHttpException catch (error) {
    throw AiTestException(error.kind);
  } on TimeoutException {
    throw const AiTestException(AiFailureKind.timeout);
  } on FormatException {
    throw const AiTestException(AiFailureKind.invalidResponse);
  } catch (_) {
    // Avoid exposing URL, headers, response body, or credentials in UI/errors.
    throw const AiTestException(AiFailureKind.network);
  } finally {
    client.close(force: true);
  }
}
