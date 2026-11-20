import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_model_catalog.dart';

/// Nature de la tâche : elle fixe le délai maximal de réponse.
///
/// Les tâches courtes restent impatientes (une saisie ne doit jamais faire
/// attendre), les analyses acceptent un peu plus de latence.
enum AiTask {
  quickEntry(Duration(seconds: 5), 'Saisie rapide'),
  smsReview(Duration(seconds: 6), 'Revue SMS'),
  analysis(Duration(seconds: 10), 'Analyse'),
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
  auth(
    'clé refusée',
    'La clé API est refusée : vérifiez-la dans les réglages.',
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
  const AiHttpException(this.statusCode);

  final int statusCode;

  AiFailureKind get kind {
    if (statusCode == 401 || statusCode == 403) return AiFailureKind.auth;
    if (statusCode == 429) return AiFailureKind.quota;
    if (statusCode >= 500) return AiFailureKind.server;
    if (statusCode == 408) return AiFailureKind.timeout;
    return AiFailureKind.invalidResponse;
  }

  @override
  String toString() => 'AiHttpException($statusCode)';
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

/// Transport réel vers l'API Google Generative Language.
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
  }) async {
    final HttpClient client = HttpClient()..connectionTimeout = timeout;
    try {
      final Uri uri = Uri.parse(
        '$base/models/$modelId:generateContent',
      ).replace(queryParameters: <String, String>{'key': apiKey});
      final HttpClientRequest request = await client
          .postUrl(uri)
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, Object?>{
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
            'responseMimeType': 'application/json',
          },
        }),
      );
      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );
      final String body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw AiHttpException(response.statusCode);
      }
      return _extractText(body);
    } finally {
      client.close(force: true);
    }
  }

  static String _extractText(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('réponse inattendue');
    final Object? candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const FormatException('aucune réponse');
    }
    final Object? first = candidates.first;
    if (first is! Map) throw const FormatException('candidat illisible');
    final Object? content = first['content'];
    if (content is! Map) throw const FormatException('contenu absent');
    final Object? parts = content['parts'];
    if (parts is! List) throw const FormatException('parties absentes');
    final StringBuffer buffer = StringBuffer();
    for (final Object? part in parts) {
      if (part is Map && part['text'] is String) {
        buffer.write(part['text'] as String);
      }
    }
    final String text = buffer.toString().trim();
    if (text.isEmpty) throw const FormatException('texte vide');
    return text;
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

/// Récupère les modèles autorisés par la clé (`models.list`).
///
/// En cas d'échec, la liste en cache reste utilisée : l'assistant continue de
/// fonctionner avec les modèles connus.
Future<AiModelsFetch> fetchAiModels(
  String apiKey, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final HttpClient client = HttpClient()..connectionTimeout = timeout;
  try {
    final Uri uri = Uri.parse('${GeminiTransport.base}/models').replace(
      queryParameters: <String, String>{'key': apiKey, 'pageSize': '50'},
    );
    final HttpClientRequest request = await client.getUrl(uri).timeout(timeout);
    final HttpClientResponse response = await request.close().timeout(timeout);
    final String body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    if (response.statusCode != 200) {
      return AiModelsFetch(failure: AiHttpException(response.statusCode).kind);
    }
    final List<AiModel> models = AiModelCatalog.parseList(body);
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
