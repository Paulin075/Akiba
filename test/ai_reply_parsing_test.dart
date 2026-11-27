import 'dart:convert';
import 'dart:io';

import 'package:akiba/core/ai/ai_client.dart';
import 'package:akiba/core/ai/ai_provider.dart';
import 'package:akiba/core/ai/ai_quota.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
    'extractAiText — aucune réponse texte valide n’est « hors format »',
    () {
      test('Gemini : ignore le raisonnement et lit le texte', () {
        final String body = jsonEncode(<String, Object>{
          'candidates': <Object>[
            <String, Object>{
              'content': <String, Object>{
                'parts': <Object>[
                  <String, Object>{'text': 'réflexion', 'thought': true},
                  <String, Object>{'text': 'AKIBA OK'},
                ],
              },
            },
          ],
        });
        expect(extractAiText(AiProvider.gemini, body), 'AKIBA OK');
      });

      test('Gemini : plusieurs candidats sont concaténés', () {
        final String body = jsonEncode(<String, Object>{
          'candidates': <Object>[
            <String, Object>{
              'content': <String, Object>{
                'parts': <Object>[
                  <String, Object>{'text': 'AKIBA '},
                ],
              },
            },
            <String, Object>{
              'content': <String, Object>{
                'parts': <Object>[
                  <String, Object>{'text': 'OK'},
                ],
              },
            },
          ],
        });
        expect(extractAiText(AiProvider.gemini, body), 'AKIBA OK');
      });

      test('OpenAI : texte sous reasoning_content quand content est vide', () {
        final String body = jsonEncode(<String, Object>{
          'choices': <Object>[
            <String, Object>{
              'message': <String, String>{
                'content': '',
                'reasoning_content': 'AKIBA OK',
              },
            },
          ],
        });
        expect(extractAiText(AiProvider.deepseek, body), 'AKIBA OK');
      });

      test('OpenAI : parties de contenu en liste', () {
        final String body = jsonEncode(<String, Object>{
          'choices': <Object>[
            <String, Object>{
              'message': <String, Object>{
                'content': <Object>[
                  <String, String>{'type': 'text', 'text': 'AKIBA OK'},
                ],
              },
            },
          ],
        });
        expect(extractAiText(AiProvider.ollama, body), 'AKIBA OK');
      });

      test('un corps texte non JSON n’est accepté que pour le diagnostic', () {
        expect(
          extractAiText(AiProvider.ollama, 'AKIBA OK', allowPlainText: true),
          'AKIBA OK',
        );
        expect(
          () => extractAiText(AiProvider.ollama, 'AKIBA OK'),
          throwsA(isA<FormatException>()),
        );
      });

      test('une réponse réellement vide reste une erreur', () {
        expect(
          () => extractAiText(AiProvider.gemini, '{"candidates":[]}'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => extractAiText(
            AiProvider.deepseek,
            '{"choices":[{"message":{"content":"   "}}]}',
          ),
          throwsA(isA<FormatException>()),
        );
      });
    },
  );

  test('Gemini : le test de connexion affiche la réponse sans quota', () async {
    final AkibaSettings settings = AkibaSettings(const EmptyAkibaStore());
    await settings.load();
    final AiQuota quota = AiQuota(settings);
    final int usedBefore = quota.used;

    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    Map<String, dynamic>? received;
    server.listen((HttpRequest request) async {
      received =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object>{
            'candidates': <Object>[
              <String, Object>{
                'content': <String, Object>{
                  'parts': <Object>[
                    <String, Object>{'text': 'AKIBA OK'},
                  ],
                },
              },
            ],
          }),
        );
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final String reply = await fetchAiTestReply(
      provider: AiProvider.gemini,
      baseUrl: 'http://127.0.0.1:${server.port}/v1beta',
      apiKey: 'cle-test-secrete',
      modelId: 'gemini-2.5-flash',
      timeout: const Duration(seconds: 2),
    );

    expect(reply, 'AKIBA OK');
    // Le diagnostic ne touche jamais le compteur du quota quotidien.
    expect(quota.used, usedBefore);
    expect(settings.raw(AiQuota.daySetting), isEmpty);

    final Map<String, dynamic> generation =
        received!['generationConfig'] as Map<String, dynamic>;
    expect(generation['maxOutputTokens'], greaterThanOrEqualTo(512));
    expect(generation['responseMimeType'], isNull);
    expect(received!['contents'], isNotEmpty);
  });
}
