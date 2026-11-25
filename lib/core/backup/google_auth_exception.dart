/// Erreur lisible de la connexion Google (jamais un jeton).
///
/// Partagée par le flux de bureau (boucle locale + PKCE) et par la connexion
/// Android native (`google_sign_in`).
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
