import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Une note du son des cauris : instant d'impact et nuance.
///
/// [at] est une position dans la timeline de l'animation (0 → 1), pas un
/// temps absolu : le plan reste juste quelle que soit la durée choisie.
class CauriNote {
  const CauriNote({required this.at, required this.volume});

  final double at;
  final double volume;
}

/// Équilibre sonore d'une chute de [count] cauris.
///
/// Le son suit le **nombre** de cauris au lieu de répéter mécaniquement six
/// lectures : plus il en tombe, plus la densité augmente (une note tous les
/// quatre cauris environ, plafonnée à dix), plus la cadence se resserre et plus
/// le corps sonore gagne en présence. Les nuances alternent et la dernière
/// note est accentuée, ce qui évite la crécelle monotone ; le volume maximal
/// reste borné à 1.0 pour ne jamais saturer.
///
/// Le calcul est **pur** (aucun greffon audio) : il est vérifiable en test et
/// ne dépend ni de la durée de l'animation ni du réseau.
class CauriSoundPlan {
  const CauriSoundPlan({
    required this.count,
    required this.stagger,
    required this.firstImpact,
    required this.lastImpact,
    required this.notes,
  });

  /// Nombre de cauris réellement audibles (plafonné à [maxVisible]).
  final int count;

  /// Espacement des départs dans la timeline.
  final double stagger;

  /// Premier impact (fraction de la timeline).
  final double firstImpact;

  /// Dernier impact (fraction de la timeline).
  final double lastImpact;

  /// Notes à jouer, dans l'ordre chronologique.
  final List<CauriNote> notes;

  /// Nombre maximal de cauris dessinés et sonorisés.
  static const int maxVisible = 60;

  /// Nombre maximal de notes pour une chute : au-delà, l'oreille n'entend
  /// plus des impacts distincts, seulement une bouillie.
  static const int maxNotes = 10;

  /// Début de la chute, en fraction de la timeline.
  static const double start = 0.05;

  /// Durée d'une chute, en fraction de la timeline.
  static const double fallSpan = 0.20;

  /// Instant du premier impact (identique au dessin de la tirelire).
  static const double firstImpactAt = start + fallSpan;

  /// Espacement des départs : serré quand le nombre grandit, jamais négatif.
  static double staggerFor(int visible) =>
      visible <= 1 ? 0 : math.min(0.030, 0.55 / (visible - 1));

  /// Nuances successives : alternance douce, jamais deux fois le même coup.
  static const List<double> _accents = <double>[
    1.0,
    0.66,
    0.80,
    0.60,
    0.84,
    0.68,
    0.76,
    0.62,
    0.82,
    0.70,
  ];

  /// Construit le plan sonore d'une chute de [requested] cauris.
  static CauriSoundPlan forCount(int requested) {
    final int count = requested < 1 ? 1 : math.min(requested, maxVisible);
    final double stagger = staggerFor(count);
    final double lastImpact = firstImpactAt + (count - 1) * stagger;

    // Corps sonore : un seul cauri reste net et présent, une grosse chute
    // gagne en ampleur sans dépasser 1.0.
    final double body = 0.72 + 0.28 * (count / 40).clamp(0.0, 1.0);

    // Densité : une note de plus tous les quatre cauris.
    final int density = math.min(maxNotes, 1 + (count - 1) ~/ 4);
    final List<CauriNote> notes = <CauriNote>[];
    for (int i = 0; i < density; i++) {
      final double position = density == 1
          ? firstImpactAt
          : firstImpactAt + (lastImpact - firstImpactAt) * i / (density - 1);
      // Micro-décalage déterministe : les impacts ne tombent jamais sur une
      // grille parfaite, ce qui casse la répétition mécanique.
      final double jitter = density == 1 ? 0 : ((i * 37) % 7 - 3) * 0.0015;
      final bool accent = i == density - 1 && density > 1;
      final double accentGain = accent ? 1.0 : _accents[i % _accents.length];
      notes.add(
        CauriNote(
          at: (position + jitter).clamp(firstImpactAt, 1.0),
          volume: (body * accentGain).clamp(0.0, 1.0),
        ),
      );
    }

    return CauriSoundPlan(
      count: count,
      stagger: stagger,
      firstImpact: firstImpactAt,
      lastImpact: lastImpact,
      notes: List<CauriNote>.unmodifiable(notes),
    );
  }

  /// Nombre de lectures pour cette chute.
  int get density => notes.length;

  /// Nuance la plus forte de la chute (≤ 1.0, donc jamais saturée).
  double get peakVolume => notes.fold<double>(
    0,
    (double max, CauriNote n) => math.max(max, n.volume),
  );

  /// Notes déjà atteintes à la position [t] de la timeline.
  int reachedAt(double t) =>
      notes.where((CauriNote note) => note.at <= t).length;
}

/// Son du cauri qui tombe dans la tirelire.
///
/// Un seul lecteur partagé, préchargé une fois. Le fichier est embarqué
/// (`assets/audio/cauri_drop.wav`) : aucun réseau, aucune attente avant
/// l'impact. Le volume est au maximum (1.0) et toute erreur de plateforme est
/// journalisée puis ignorée : un appareil sans audio ne casse jamais
/// l'animation.
abstract final class CauriSound {
  /// Chemin relatif à `assets/`, comme l'attend `AssetSource`.
  static const String asset = 'audio/cauri_drop.wav';

  static AudioPlayer? _player;
  static Future<void>? _preparing;

  static AudioPlayer get _instance {
    final AudioPlayer? current = _player;
    if (current != null) return current;
    final AudioPlayer created = AudioPlayer(playerId: 'akiba-cauri');
    unawaited(created.setReleaseMode(ReleaseMode.stop));
    _player = created;
    return created;
  }

  /// Charge le son à l'avance (appelé hors du chemin critique).
  static Future<void> preload() => _preparing ??= _prepare();

  static Future<void> _prepare() async {
    try {
      final AudioPlayer player = _instance;
      await player.setSource(AssetSource(asset));
      await player.setVolume(1);
    } catch (error) {
      debugPrint('AKIBA : son des cauris indisponible (${error.runtimeType}).');
    }
  }

  /// Joue l'impact, sans bloquer l'appelant.
  ///
  /// Aucun `await` bloquant : l'animation continue même si le moteur audio
  /// tarde. L'éventuelle erreur est journalisée (type seulement) au lieu
  /// d'être avalée en silence.
  static void play({double volume = 1.0}) {
    unawaited(preload());
    unawaited(
      _instance
          .play(AssetSource(asset), volume: volume.clamp(0.0, 1.0).toDouble())
          .catchError((Object error) {
            debugPrint(
              'AKIBA : lecture du son des cauris impossible '
              '(${error.runtimeType}).',
            );
          }),
    );
  }

  /// Libère le lecteur (tests et fin de vie de l'application).
  static Future<void> dispose() async {
    final AudioPlayer? player = _player;
    _player = null;
    _preparing = null;
    await player?.dispose();
  }
}
