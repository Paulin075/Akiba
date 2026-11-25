/// Identité Google canonique utilisée pour dériver la clé de sauvegarde.
///
/// Une sauvegarde portable est chiffrée avec une clé dérivée (PBKDF2) d'une
/// identité Google : sans cette identité exacte, le déchiffrement est
/// impossible. Pour qu'une reconnexion avec **le même compte** aboutisse
/// toujours, l'identité est normalisée avant d'être utilisée :
///
/// - e-mail en minuscules, sans aucun espace (`  Paul.X@Gmail.COM ` →
///   `paul.x@gmail.com`) ;
/// - identifiant Google stable (`sub`) sans espace.
///
/// Les valeurs brutes (`rawId`, `rawEmail`) sont conservées en mémoire afin de
/// retrouver les sauvegardes créées avant la normalisation, sans jamais écrire
/// l'identifiant de dérivation dans l'enveloppe.
class GoogleAccount {
  const GoogleAccount({
    this.id = '',
    this.email = '',
    this.rawId = '',
    this.rawEmail = '',
  });

  /// Aucun compte : la sauvegarde utilise la clé de l'appareil.
  static const GoogleAccount none = GoogleAccount();

  /// Construit une identité normalisée à partir d'une session Google.
  factory GoogleAccount.normalized({String? id, String? email}) {
    final String rawId = (id ?? '').trim();
    final String rawEmail = (email ?? '').trim();
    return GoogleAccount(
      id: normalize(rawId),
      email: normalize(rawEmail).toLowerCase(),
      rawId: rawId,
      rawEmail: rawEmail,
    );
  }

  /// Identité déjà normalisée (identifiant stable seul).
  factory GoogleAccount.fromId(String id) => GoogleAccount.normalized(id: id);

  /// Relit les métadonnées `account` d'une enveloppe (e-mail d'affichage).
  factory GoogleAccount.fromJson(Object? json) {
    if (json is! Map) return GoogleAccount.none;
    return GoogleAccount.normalized(
      id: json['id'] is String ? json['id'] as String : '',
      email: json['email'] is String ? json['email'] as String : '',
    );
  }

  /// Identifiant Google stable (`sub`), normalisé.
  final String id;

  /// E-mail du compte, en minuscules et sans espace.
  final String email;

  /// Identifiant tel que fourni par la session (avant normalisation).
  final String rawId;

  /// E-mail tel que fourni par la session (avant normalisation).
  final String rawEmail;

  /// Supprime tous les espaces (y compris internes) d'un identifiant saisi.
  static String normalize(String? raw) =>
      (raw ?? '').replaceAll(RegExp(r'\s+'), '');

  bool get isEmpty => id.isEmpty && email.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Libellé affichable : l'e-mail quand il est connu, jamais un identifiant.
  String get label => email.isNotEmpty
      ? email
      : (id.isNotEmpty ? 'compte Google lié' : 'aucun compte Google');

  /// Identités candidates pour la dérivation, de la plus récente à la plus
  /// ancienne : normalisée d'abord, puis brute (compatibilité), puis l'e-mail.
  /// Les doublons et les valeurs vides sont écartés.
  List<String> get keyCandidates {
    final List<String> out = <String>[];
    void add(String value) {
      final String candidate = value.trim();
      if (candidate.isEmpty) return;
      if (out.contains(candidate)) return;
      out.add(candidate);
    }

    add(id);
    add(rawId);
    add(email);
    add(rawEmail);
    return out;
  }

  /// Métadonnées non sensibles écrites dans l'enveloppe : elles servent
  /// uniquement à nommer le compte attendu en cas de vraie différence.
  Map<String, Object?> toJson() => <String, Object?>{
    if (id.isNotEmpty) 'id': id,
    if (email.isNotEmpty) 'email': email,
  };

  @override
  String toString() => label;
}
