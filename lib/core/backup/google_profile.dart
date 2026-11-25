import 'dart:convert';

/// Prénom et nom tels que Google les expose, pour pré-remplir l'onboarding.
///
/// Aucune donnée n'est inventée : si le profil ne fournit qu'un nom complet,
/// il est coupé au premier espace (prénom = premier mot, nom = le reste).
class GoogleProfile {
  const GoogleProfile({this.givenName = '', this.familyName = ''});

  final String givenName;
  final String familyName;

  static const GoogleProfile empty = GoogleProfile();

  bool get isEmpty => givenName.isEmpty && familyName.isEmpty;

  /// Profil issu du champ `displayName` de `google_sign_in`.
  factory GoogleProfile.fromDisplayName(String displayName) {
    final List<String> words = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((String word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return empty;
    if (words.length == 1) return GoogleProfile(givenName: words.first);
    return GoogleProfile(
      givenName: words.first,
      familyName: words.skip(1).join(' '),
    );
  }

  /// Profil lu dans la charge utile d'un `id_token` Google.
  ///
  /// Google n'y met `given_name`/`family_name` que si la portée `profile` a
  /// été accordée : sinon on retombe sur `name`, puis sur un profil vide.
  factory GoogleProfile.fromIdToken(Object? idToken) {
    final Map<String, dynamic>? claims = _claims(idToken);
    if (claims == null) return empty;
    String text(Object? value) => value is String ? value.trim() : '';
    final String given = text(claims['given_name']);
    final String family = text(claims['family_name']);
    if (given.isNotEmpty || family.isNotEmpty) {
      return GoogleProfile(givenName: given, familyName: family);
    }
    return GoogleProfile.fromDisplayName(text(claims['name']));
  }

  /// Complète ce profil avec les champs manquants de [other].
  GoogleProfile mergedWith(GoogleProfile other) {
    return GoogleProfile(
      givenName: givenName.isEmpty ? other.givenName : givenName,
      familyName: familyName.isEmpty ? other.familyName : familyName,
    );
  }

  static Map<String, dynamic>? _claims(Object? idToken) {
    if (idToken is! String) return null;
    final List<String> parts = idToken.split('.');
    if (parts.length < 2) return null;
    try {
      final String padded = parts[1].padRight(
        (parts[1].length + 3) ~/ 4 * 4,
        '=',
      );
      final Object? decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Un jeton illisible ne bloque pas la connexion.
    }
    return null;
  }
}
