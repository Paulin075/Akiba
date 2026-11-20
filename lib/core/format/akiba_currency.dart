/// Devises d'affichage proposées par AKIBA.
///
/// **Aucun taux de change n'est appliqué** : le choix ne change que le libellé
/// collé aux montants, jamais leur valeur. Les montants restent stockés en
/// entiers, comme aujourd'hui, pour ne pas modifier la base des Étapes 1 à 9.
///
/// Chaque devise porte l'URL d'un logo récupéré sur un CDN public (drapeau),
/// mis en cache localement par `CurrencyLogoCache` ; hors ligne, l'interface
/// affiche un jeton typographique aux couleurs de la charte.
enum AkibaCurrency {
  fcfa(
    storageKey: 'FCFA',
    code: 'XOF',
    name: 'FCFA',
    symbol: 'FCFA',
    region: 'tg',
  ),
  euro(storageKey: 'EUR', code: 'EUR', name: 'Euro', symbol: '€', region: 'eu'),
  dollar(
    storageKey: 'USD',
    code: 'USD',
    name: 'Dollar',
    symbol: r'$',
    region: 'us',
  ),
  yuan(storageKey: 'CNY', code: 'CNY', name: 'Yuan', symbol: '¥', region: 'cn');

  const AkibaCurrency({
    required this.storageKey,
    required this.code,
    required this.name,
    required this.symbol,
    required this.region,
  });

  /// Valeur écrite dans `settings.currency`.
  final String storageKey;

  /// Code ISO 4217.
  final String code;

  /// Nom lisible (« FCFA », « Euro »…).
  final String name;

  /// Suffixe collé au montant (`15 000 FCFA`, `15 000 €`).
  final String symbol;

  /// Région utilisée par le CDN de drapeaux (logo de la devise).
  final String region;

  /// Libellé complet pour les listes : « Euro (EUR) ».
  String get label => this == fcfa ? 'FCFA (XOF)' : '$name ($code)';

  /// URL du logo, servie par un CDN public ; le cache local évite de la
  /// solliciter à chaque affichage.
  String get logoUrl => 'https://flagcdn.com/w160/$region.png';

  /// Relit une valeur enregistrée à n'importe quelle étape précédente
  /// (`FCFA`, `XOF`, `fcfa`, `EUR`…). Repli : FCFA.
  static AkibaCurrency fromStorage(String value) {
    final String normalized = value.trim().toLowerCase();
    for (final AkibaCurrency currency in values) {
      if (normalized == currency.storageKey.toLowerCase() ||
          normalized == currency.code.toLowerCase() ||
          normalized == currency.name.toLowerCase() ||
          normalized == currency.name) {
        return currency;
      }
    }
    return fcfa;
  }
}
