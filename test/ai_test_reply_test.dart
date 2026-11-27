import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:akiba/core/ai/ai_client.dart';
import 'package:akiba/core/ai/ai_provider.dart';

void main() {
  test('test model follows selected priority and fresh availability', () {
    expect(
      selectAiTestModel(
        provider: AiProvider.gemini,
        selectedGeminiModels: <String>['removed-model', 'chosen-model'],
        availableModelIds: <String>['chosen-model', 'other-model'],
        configuredModel: 'unused-model',
      ),
      'chosen-model',
    );
    expect(
      selectAiTestModel(
        provider: AiProvider.deepseek,
        selectedGeminiModels: <String>[],
        availableModelIds: <String>['catalog-model'],
        configuredModel: 'configured-model',
      ),
      'configured-model',
    );
  });

  test('test request uses the selected OpenAI-compatible model', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    String? requestedModel;
    final Future<void> serving = server.first.then((HttpRequest request) async {
      final Map<String, dynamic> body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      requestedModel = body['model'] as String?;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object>{
            'choices': <Object>[
              <String, Object>{
                'message': <String, String>{'content': 'AKIBA OK'},
              },
            ],
          }),
        );
      await request.response.close();
    });

    final String reply = await fetchAiTestReply(
      provider: AiProvider.ollama,
      baseUrl: 'http://${server.address.address}:${server.port}/v1',
      modelId: 'selected-local-model',
      timeout: const Duration(seconds: 2),
    );
    await serving;
    await server.close(force: true);

    expect(requestedModel, 'selected-local-model');
    expect(reply, 'AKIBA OK');
  });

  test('test failure is reduced to a safe, understandable category', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Future<void> serving = server.first.then((HttpRequest request) async {
      request.response.statusCode = HttpStatus.tooManyRequests;
      await request.response.close();
    });

    AiTestException? failure;
    try {
      await fetchAiTestReply(
        provider: AiProvider.deepseek,
        baseUrl: 'http://${server.address.address}:${server.port}/v1',
        apiKey: 'secret-test-key-value',
        modelId: 'selected-model',
        timeout: const Duration(seconds: 2),
      );
    } on AiTestException catch (error) {
      failure = error;
    }
    await serving;
    await server.close(force: true);

    expect(failure?.kind, AiFailureKind.quota);
    expect(failure?.message, AiFailureKind.quota.hint);
    expect(failure.toString(), isNot(contains('secret-test-key-value')));
  });

  test(
    'clé Gemini refusée (400 API_KEY_INVALID) : message « clé refusée »',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final Future<void> serving = server.first.then((
        HttpRequest request,
      ) async {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object>{
              'error': <String, Object>{
                'code': 400,
                'message': 'API key not valid. Please pass a valid API key.',
                'status': 'INVALID_ARGUMENT',
                'details': <Object>[
                  <String, Object>{'reason': 'API_KEY_INVALID'},
                ],
              },
            }),
          );
        await request.response.close();
      });

      AiTestException? failure;
      try {
        await fetchAiTestReply(
          provider: AiProvider.gemini,
          baseUrl: 'http://${server.address.address}:${server.port}/v1beta',
          apiKey: 'cle-refusee-test',
          modelId: 'gemini-flash-latest',
          timeout: const Duration(seconds: 2),
        );
      } on AiTestException catch (error) {
        failure = error;
      }
      await serving;
      await server.close(force: true);

      expect(failure?.kind, AiFailureKind.auth);
      expect(failure?.message, AiFailureKind.auth.hint);
      expect(failure.toString(), isNot(contains('cle-refusee-test')));
    },
  );

  test('modèle retiré (404) : annoncé comme modèle introuvable', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Future<void> serving = server.first.then((HttpRequest request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    AiTestException? failure;
    try {
      await fetchAiTestReply(
        provider: AiProvider.gemini,
        baseUrl: 'http://${server.address.address}:${server.port}/v1beta',
        apiKey: 'cle-test',
        modelId: 'gemini-1.5-pro',
        timeout: const Duration(seconds: 2),
      );
    } on AiTestException catch (error) {
      failure = error;
    }
    await serving;
    await server.close(force: true);

    expect(failure?.kind, AiFailureKind.model);
    expect(failure?.message, AiFailureKind.model.hint);
  });

  test('test timeout has a safe timeout message', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Future<void> serving = server.first.then((HttpRequest request) async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      request.response.write('{}');
      await request.response.close();
    });

    AiTestException? failure;
    try {
      await fetchAiTestReply(
        provider: AiProvider.ollama,
        baseUrl: 'http://${server.address.address}:${server.port}/v1',
        modelId: 'model',
        timeout: const Duration(milliseconds: 40),
      );
    } on AiTestException catch (error) {
      failure = error;
    }
    await server.close(force: true);
    await serving;
    expect(failure?.kind, AiFailureKind.timeout);
    expect(failure?.message, AiFailureKind.timeout.hint);
  });

  test(
    'unreachable endpoint reports a safe network or timeout category',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int port = server.port;
      await server.close(force: true);

      AiTestException? failure;
      try {
        await fetchAiTestReply(
          provider: AiProvider.ollama,
          baseUrl: 'http://127.0.0.1:$port/v1',
          modelId: 'model',
          timeout: const Duration(seconds: 2),
        );
      } on AiTestException catch (error) {
        failure = error;
      }
      expect(<AiFailureKind>{
        AiFailureKind.network,
        AiFailureKind.timeout,
      }, contains(failure?.kind));
      expect(failure?.message, isNot(contains('127.0.0.1')));
    },
  );
}
