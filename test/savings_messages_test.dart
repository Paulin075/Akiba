import 'dart:math' as math;

import 'package:akiba/core/ai/ai_client.dart';
import 'package:akiba/core/ai/ai_remote.dart';
import 'package:akiba/core/savings/savings_messages.dart';
import 'package:akiba/core/savings/savings_projection.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/data/akiba_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('un cauri représente strictement 100 FCFA', () {
    expect(SavingsProjection.cauriCountForAmount(0), 0);
    expect(SavingsProjection.cauriCountForAmount(-1), 0);
    expect(SavingsProjection.cauriCountForAmount(1), 1);
    expect(SavingsProjection.cauriCountForAmount(99), 1);
    expect(SavingsProjection.cauriCountForAmount(100), 1);
    expect(SavingsProjection.cauriCountForAmount(199), 1);
    expect(SavingsProjection.cauriCountForAmount(200), 2);
    expect(SavingsProjection.cauriCountForAmount(123456789), 1234567);
  });

  group('Catalogue local d’épargne', () {
    test('FR et EN proposent les deux familles, sans montant', () {
      for (final SavingsMessageKind kind in SavingsMessageKind.values) {
        for (final String language in <String>['fr', 'en']) {
          final List<String> messages = SavingsMessages.catalog(
            kind,
            language: language,
          );
          expect(messages.length, greaterThanOrEqualTo(10));
          for (final String message in messages) {
            expect(message.trim(), isNotEmpty);
            // Des chiffres peuvent apparaître (« dans 5 ans »), mais jamais un
            // montant en devise ni un masque : ces messages restent sûrs.
            expect(message.contains('FCFA'), isFalse);
            expect(message.contains('••••'), isFalse);
          }
        }
      }
    });

    test('le nom du coffre remplace {pot} sans jamais afficher de chiffre', () {
      final SavingsMessages messages = SavingsMessages(
        language: 'fr',
        random: math.Random(1),
      );
      for (int i = 0; i < 40; i++) {
        final String text = messages.next(
          SavingsMessageKind.encouragement,
          potName: 'Voyage',
        );
        expect(text.contains('{pot}'), isFalse);
        expect(RegExp(r'\d').hasMatch(text), isFalse);
      }
    });

    test('aucune répétition immédiate sur 300 tirages', () {
      for (final String language in <String>['fr', 'en']) {
        for (final SavingsMessageKind kind in SavingsMessageKind.values) {
          final SavingsMessages picker = SavingsMessages(
            language: language,
            random: math.Random(42),
          );
          String? previous;
          for (int i = 0; i < 300; i++) {
            final String current = picker.next(kind, potName: 'Coffre');
            expect(current, isNot(previous), reason: '$language/$kind i=$i');
            previous = current;
          }
        }
      }
    });

    test('les taquineries de retrait existent aussi, en anglais', () {
      final SavingsMessages english = SavingsMessages(
        language: 'en',
        random: math.Random(3),
      );
      final String taunt = english.next(
        SavingsMessageKind.withdrawal,
        potName: 'Rent',
      );
      expect(taunt.trim(), isNotEmpty);
      expect(taunt.contains('FCFA'), isFalse);
      expect(
        SavingsMessages.catalog(SavingsMessageKind.withdrawal, language: 'en'),
        isNot(equals(SavingsMessages.catalog(SavingsMessageKind.withdrawal))),
      );
    });
  });

  group('Coach IA optionnel', () {
    late AkibaSettings settings;

    setUp(() async {
      settings = AkibaSettings(const EmptyAkibaStore());
      await settings.load();
    });

    test(
      'sans IA configurée, le message local revient instantanément',
      () async {
        final SavingsCoachResult result = await const SavingsCoach().enrich(
          settings: settings,
          kind: SavingsMessageKind.encouragement,
          localMessage: 'Message local',
          potName: 'Coffre',
        );
        expect(result.message, 'Message local');
        expect(result.fromAi, isFalse);
        expect(result.engine, 'local');
      },
    );

    test('avec IA, la phrase du modèle remplace le local', () async {
      await settings.setFlag('ai_remote_enabled', true);
      await settings.set('ai_provider', 'ollama');
      final AiRemoteResolution resolution = await resolveAiRemote(
        settings,
        masked: false,
      );
      expect(resolution.setup, isNotNull, reason: resolution.note);
      final SavingsCoachResult result =
          await SavingsCoach(
            transportOverride:
                ({
                  required String modelId,
                  required String prompt,
                  required Duration timeout,
                }) async {
                  // Aucun montant ne part vers l'IA pour ce message.
                  expect(prompt.contains('FCFA'), isFalse);
                  return '« Le cauri est fier de vous. »';
                },
          ).enrich(
            settings: settings,
            kind: SavingsMessageKind.encouragement,
            localMessage: 'Message local',
            potName: 'Coffre',
          );
      expect(result.message, 'Le cauri est fier de vous.');
      expect(result.fromAi, isTrue);
    });

    test('une erreur réseau garde le message local', () async {
      await settings.setFlag('ai_remote_enabled', true);
      await settings.set('ai_provider', 'ollama');
      final SavingsCoachResult result =
          await SavingsCoach(
            transportOverride:
                ({
                  required String modelId,
                  required String prompt,
                  required Duration timeout,
                }) async => throw const AiHttpException(503),
          ).enrich(
            settings: settings,
            kind: SavingsMessageKind.withdrawal,
            localMessage: 'Taquinerie locale',
            potName: 'Coffre',
          );
      expect(result.message, 'Taquinerie locale');
      expect(result.fromAi, isFalse);
    });
  });
}
