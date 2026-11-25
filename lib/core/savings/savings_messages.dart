import 'dart:math' as math;

import '../ai/ai_client.dart';
import '../ai/ai_quota.dart';
import '../ai/ai_remote.dart';
import '../state/akiba_settings.dart';

/// Nature du message local lié à l'épargne.
enum SavingsMessageKind {
  /// Après un versement : encouragement, jamais de montant.
  encouragement,

  /// Après un retrait : taquinerie locale, jamais de montant.
  withdrawal,
}

/// Catalogue local de messages d'épargne (français et anglais).
///
/// Deux familles :
/// - **encouragement** après un versement ;
/// - **taquinerie** après un retrait, dans l'esprit demandé (« même dans 5 ans
///   tu es encore loin de ton objectif ! »), sans jamais humilier ni chiffrer.
///
/// Les messages ne contiennent **aucun montant** : ils restent donc sûrs quand
/// le masquage global est actif. La sélection évite la répétition immédiate
/// pour une même famille et une même langue. Aucun réseau, aucune écriture.
class SavingsMessages {
  SavingsMessages({String? language, math.Random? random})
    : _language = (language ?? 'fr') == 'en' ? 'en' : 'fr',
      _random = random ?? math.Random();

  final String _language;
  final math.Random _random;

  /// Dernier index servi, par famille (pour ne pas répéter le précédent).
  final Map<SavingsMessageKind, int> _lastIndex = <SavingsMessageKind, int>{};

  String get language => _language;

  void setLanguage(String value) {
    // Le catalogue est relu à chaque tirage : changer de langue ne demande
    // qu'à oublier la position précédente dans l'autre table.
    _lastIndex.clear();
  }

  static const Map<SavingsMessageKind, Map<String, List<String>>> _catalog =
      <SavingsMessageKind, Map<String, List<String>>>{
        SavingsMessageKind.encouragement: <String, List<String>>{
          'fr': <String>[
            'Le cauri est tombé dans {pot} : votre discipline parle plus fort '
                'que la tentation.',
            'Chaque versement rapproche {pot} du but. Continuez, même petit.',
            'Bravo ! {pot} grossit pendant que le reste du monde dépense.',
            'Vous venez d’acheter une part de votre tranquillité future.',
            'Le cochon est content : {pot} vient de prendre un peu de poids.',
            'Un versement de plus, et votre futur vous dit merci.',
            'C’est exactement comme ça qu’on construit une réserve : un cauri '
                'après l’autre.',
            'Votre objectif ne recule plus, il avance. Belle journée pour '
                '{pot}.',
            'Petit montant, grand geste : la régularité bat la chance.',
            'Le meilleur moment pour épargner, c’était hier. Le deuxième '
                'meilleur, c’est maintenant — et vous l’avez fait.',
          ],
          'en': <String>[
            'The cauri landed in {pot}: your discipline speaks louder than '
                'temptation.',
            'Every deposit brings {pot} closer to the goal. Keep going, even '
                'small.',
            'Well done! {pot} grows while the rest of the world spends.',
            'You just bought a share of your future peace of mind.',
            'The piggy is happy: {pot} just gained a little weight.',
            'One more deposit, and your future self says thank you.',
            'This is exactly how a reserve is built: one cauri at a time.',
            'Your goal is no longer stepping back, it is moving forward. Good '
                'day for {pot}.',
            'Small amount, big move: consistency beats luck.',
            'The best time to save was yesterday. The second best is now — '
                'and you just did it.',
          ],
        },
        SavingsMessageKind.withdrawal: <String, List<String>>{
          'fr': <String>[
            'Continue comme ça, même dans 5 ans tu es encore loin de ton '
                'objectif !',
            'Ah, {pot} vient de maigrir. Le cochon vous regarde, déçu mais '
                'solidaire.',
            'Retrait effectué : votre objectif a reculé de quelques pas. Il '
                'paraît qu’il court vite.',
            'Vous avez pris un cauri dans la tirelire. Le cochon note ça dans '
                'son petit carnet.',
            'C’est un retrait stratégique, hein ? On dit toujours ça.',
            'Le cochon a fait grève de la sieste pour digérer ce retrait.',
            'Votre épargne a fait un aller-retour. Elle vous remercie de '
                'l’avoir laissée voyager.',
            'Objectif : toujours là. Patience : à recharger. Cauri : parti '
                'trop tôt.',
            'Un retrait aujourd’hui, un petit regret demain ? Le cochon ne '
                'juge pas… beaucoup.',
            'Vous venez de goûter à {pot}. Il espère que c’était bon.',
            'Le cochon demande : c’était vraiment nécessaire, ou juste '
                'tentant ?',
            'Votre futur vous envoie un message : « remets-le, s’il te '
                'plaît ».',
          ],
          'en': <String>[
            'Keep it up — even in 5 years you will still be far from your '
                'goal!',
            'Oh, {pot} just lost weight. The piggy is watching, disappointed '
                'but supportive.',
            'Withdrawal done: your goal stepped back a few paces. Apparently '
                'it runs fast.',
            'You took a cauri out of the piggy. The piggy is writing this '
                'down.',
            'A strategic withdrawal, right? That is what everyone says.',
            'The piggy skipped its nap to digest this withdrawal.',
            'Your savings took a round trip. It thanks you for the journey.',
            'Goal: still here. Patience: recharging. Cauri: left too soon.',
            'A withdrawal today, a tiny regret tomorrow? The piggy does not '
                'judge… much.',
            'You just tasted {pot}. It hopes it was worth it.',
            'The piggy asks: was it really necessary, or just tempting?',
            'Your future self sends a message: “put it back, please”.',
          ],
        },
      };

  /// Catalogue complet d'une famille, pour les tests et la documentation.
  static List<String> catalog(
    SavingsMessageKind kind, {
    String language = 'fr',
  }) {
    final Map<String, List<String>> byLanguage = _catalog[kind]!;
    return List<String>.unmodifiable(
      byLanguage[language == 'en' ? 'en' : 'fr']!,
    );
  }

  /// Message suivant, sans jamais répéter immédiatement le précédent.
  String next(SavingsMessageKind kind, {String? potName}) {
    final List<String> pool = _catalog[kind]![_language]!;
    final int previous = _lastIndex[kind] ?? -1;
    int index = _random.nextInt(pool.length);
    if (pool.length > 1 && index == previous) {
      // Décalage déterministe : aucune boucle possible, aucune répétition
      // consécutive même quand le hasard retombe sur le même index.
      index = (index + 1 + _random.nextInt(pool.length - 1)) % pool.length;
      if (index == previous) index = (index + 1) % pool.length;
    }
    _lastIndex[kind] = index;
    final String pot = (potName == null || potName.trim().isEmpty)
        ? (_language == 'en' ? 'your vault' : 'votre coffre')
        : potName.trim();
    return pool[index].replaceAll('{pot}', pot);
  }
}

/// Réponse du coach IA, ou repli local.
class SavingsCoachResult {
  const SavingsCoachResult({required this.message, required this.engine});

  final String message;
  final String engine;

  bool get fromAi => engine != 'local';
}

/// Enrichissement **optionnel** du message par l'IA configurée.
///
/// Le prompt ne contient **aucun montant** ni nom de compte : même si le
/// masquage est actif, rien de chiffré ne part. Sans clé, sans réseau, sans
/// quota ou en cas de réponse illisible, le message local est renvoyé
/// immédiatement ([SavingsCoachResult.engine] = `local`).
class SavingsCoach {
  const SavingsCoach({this.transportOverride, this.now});

  /// Transport de test : remplace l'appel réseau.
  final AiTransport? transportOverride;
  final DateTime Function()? now;

  Future<SavingsCoachResult> enrich({
    required AkibaSettings settings,
    required SavingsMessageKind kind,
    required String localMessage,
    String? potName,
  }) async {
    if (!settings.aiRemoteEnabled) {
      return SavingsCoachResult(message: localMessage, engine: 'local');
    }
    final AiRemoteResolution resolution = await resolveAiRemote(
      settings,
      // Aucun montant dans le prompt : le masquage n'interdit pas ce message.
      masked: false,
    );
    final AiRemoteSetup? setup = resolution.setup;
    if (setup == null) {
      return SavingsCoachResult(message: localMessage, engine: 'local');
    }
    final AiQuota quota = AiQuota(settings, now: now);
    if (!await quota.consume()) {
      return SavingsCoachResult(message: localMessage, engine: 'local');
    }
    final AkibaAiClient client = AkibaAiClient(
      models: setup.models,
      transport: transportOverride ?? setup.transport,
      maxAttempts: settings.aiMaxAttempts,
    );
    final String language = settings.language == 'en' ? 'English' : 'French';
    final String intent = kind == SavingsMessageKind.encouragement
        ? 'encourage the person after a savings deposit'
        : 'gently tease the person after a savings withdrawal, funny but kind';
    final AiCallResult result = await client.generate(
      task: AiTask.coaching,
      prompt:
          'You write one short AKIBA app message in $language. $intent. '
          'Maximum 18 words, no amount, no account number, no emoji, no '
          'quotation marks. Vault name: ${potName ?? 'vault'}. '
          'Reply with the sentence only.',
    );
    if (!result.ok || result.text == null) {
      return SavingsCoachResult(message: localMessage, engine: 'local');
    }
    final String cleaned = _clean(result.text!);
    if (cleaned.isEmpty) {
      return SavingsCoachResult(message: localMessage, engine: 'local');
    }
    return SavingsCoachResult(message: cleaned, engine: setup.provider.label);
  }

  /// Retire les artefacts habituels d'un modèle et borne la longueur.
  static String _clean(String raw) {
    String text = raw.trim().replaceAll(RegExp(r'^["“”«»\s]+|["“”«»\s]+$'), '');
    text = text.replaceAll(RegExp(r'^\d+[\).\s-]+'), '');
    if (text.length > 140) text = '${text.substring(0, 137)}…';
    return text;
  }
}
