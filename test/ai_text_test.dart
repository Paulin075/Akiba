import 'package:akiba/core/ai/ai_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiText', () {
    test('déballer un JSON simple', () {
      final String text = AiText.plain(
        '{"conseil_financier": "Bonjour. Votre solde est de 68 700 FCFA."}',
      );
      expect(text, 'Bonjour. Votre solde est de 68 700 FCFA.');
      expect(text, isNot(contains('{')));
    });

    test('un verdict et une liste de conseils deviennent des puces', () {
      final List<AiTextBlock> blocks = AiText.blocks(
        '```json\n{"avis": "Un mois dans le vert", "conseils": '
        '["Plafonnez le transport", "Versez au coffre"]}\n```',
      );
      expect(blocks, hasLength(3));
      expect(blocks.first.text, 'Un mois dans le vert');
      expect(blocks[1].isBullet, isTrue);
      expect(blocks[1].text, 'Plafonnez le transport');
      expect(
        AiText.plain(
          '{"avis": "Un mois dans le vert", "conseils": ["Plafonnez"]}',
        ),
        'Un mois dans le vert\n- Plafonnez',
      );
    });

    test('retire le Markdown et la numérotation', () {
      final List<AiTextBlock> blocks = AiText.blocks(
        '**Verdict :** mois calme\n1. Plafonnez le transport\n2. Épargnez',
      );
      expect(blocks.first.text, 'Verdict : mois calme');
      expect(blocks.where((AiTextBlock b) => b.isBullet), hasLength(2));
      expect(blocks.last.text, 'Épargnez');
    });

    test('une réponse déjà en texte reste inchangée', () {
      expect(
        AiText.plain('Un mois calme\nCap transport\nÉpargner'),
        'Un mois calme\nCap transport\nÉpargner',
      );
    });
  });
}
