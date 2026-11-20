/// Supports financiers gérés par AKIBA et leur logo officiel.
///
/// Le libellé et l'asset vivent dans la couche données ; la présentation
/// (icône de repli) est ajoutée par `core/widgets/brand_logo.dart`.
enum AccountBrand {
  liquide('Liquide', null),
  flooz('Flooz', 'assets/logos/flooz.jpg'),
  mixxByYas('Mixx by Yas', 'assets/logos/mixx.png'),
  orabank('Orabank', 'assets/logos/orabank.png');

  const AccountBrand(this.label, this.asset);

  /// Nom affiché du support.
  final String label;

  /// Logo officiel (`null` : emblème dessiné, cas du liquide).
  final String? asset;

  /// Relit un support depuis la base (repli liquide si valeur inconnue).
  static AccountBrand fromStorage(String value) {
    for (final AccountBrand brand in values) {
      if (brand.name == value) return brand;
    }
    return liquide;
  }
}
