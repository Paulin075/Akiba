import 'dart:convert';

/// Nature d'un bloc de texte lisible.
enum AiTextKind { paragraph, bullet }

/// Un bloc prêt à l'affichage : paragraphe ou puce.
class AiTextBlock {
  const AiTextBlock(this.kind, this.text);

  final AiTextKind kind;
  final String text;

  bool get isBullet => kind == AiTextKind.bullet;

  /// Représentation texte, utilisée dans le rapport et le PDF.
  String get prefixed => isBullet ? '- $text' : text;
}

/// Nettoie une réponse de modèle.
///
/// Les fournisseurs renvoient parfois un objet JSON
/// (`{"conseil_financier": "..."}`), parfois du Markdown, souvent les deux
/// entourés de ```. Le résultat est toujours du texte simple : jamais de JSON
/// brut à l'écran, ni dans le PDF.
class AiText {
  const AiText._();

  /// Blocs ordonnés (paragraphes et puces) extraits de [raw].
  static List<AiTextBlock> blocks(String raw) {
    final List<AiTextBlock> out = <AiTextBlock>[];
    final String body = _unwrap(raw);
    final Object? decoded = _json(body);
    if (decoded != null) {
      _collect(decoded, out);
    } else {
      // Objet JSON noyé dans une phrase : on isole le bloc.
      final int start = body.indexOf('{');
      final int end = body.lastIndexOf('}');
      final Object? inner = start >= 0 && end > start
          ? _json(body.substring(start, end + 1))
          : null;
      if (inner != null) {
        _collect(inner, out);
      } else {
        _addPlain(body, out);
      }
    }
    return out;
  }

  /// Version texte : blocs séparés par un saut de ligne, puces en « - ».
  static String plain(String raw) =>
      blocks(raw).map((AiTextBlock block) => block.prefixed).join('\n').trim();

  /// Lignes utiles du texte lisible (sans puce, sans ligne vide).
  static List<String> lines(String raw) => blocks(raw)
      .map((AiTextBlock block) => block.text.trim())
      .where((String line) => line.isNotEmpty)
      .toList(growable: false);

  static String _unwrap(String raw) {
    String text = raw.trim();
    text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
    return text.trim();
  }

  /// Ne décode que les valeurs structurées : un nombre ou une phrase restent
  /// du texte.
  static Object? _json(String text) {
    final String value = text.trim();
    final bool object = value.startsWith('{') && value.endsWith('}');
    final bool list = value.startsWith('[') && value.endsWith(']');
    if (!object && !list) return null;
    try {
      final Object? decoded = jsonDecode(value);
      return decoded is Map || decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static void _collect(Object? value, List<AiTextBlock> out) {
    if (value is String) {
      _addPlain(value, out);
      return;
    }
    if (value is List) {
      for (final Object? item in value) {
        if (item is String) {
          final String text = _clean(item);
          if (text.isEmpty) continue;
          final bool short = text.length <= 240 && !item.contains('\n');
          out.add(
            AiTextBlock(short ? AiTextKind.bullet : AiTextKind.paragraph, text),
          );
        } else {
          _collect(item, out);
        }
      }
      return;
    }
    if (value is Map) {
      // Les clés techniques (confiance, score, nombre) n'apportent rien.
      for (final Object? item in value.values) {
        _collect(item, out);
      }
    }
  }

  static void _addPlain(String value, List<AiTextBlock> out) {
    for (final String raw in value.split(RegExp(r'\r?\n'))) {
      final bool bullet = RegExp(r'^\s*([-*•–]|\d{1,2}[.)])\s+').hasMatch(raw);
      final String text = _clean(raw);
      if (text.isEmpty) continue;
      out.add(
        AiTextBlock(bullet ? AiTextKind.bullet : AiTextKind.paragraph, text),
      );
    }
  }

  /// Retire Markdown, puces, titres et guillemets parasites.
  static String _clean(String value) {
    String text = value.replaceAll('\u00A0', ' ').trim();
    text = text.replaceAll(RegExp(r'^#{1,6}\s*'), '');
    text = text.replaceAll('**', '').replaceAll('__', '');
    text = text.replaceAll(RegExp(r'^[-*•–]\s+'), '');
    text = text.replaceAll(RegExp(r'^\d{1,2}[.)]\s+'), '');
    text = text.replaceAll(RegExp(r'^["“”]+|["“”]+$'), '');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
