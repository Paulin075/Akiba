import 'package:akiba/core/audio/cauri_sound.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Équilibre sonore des cauris', () {
    test('une chute plus grosse produit plus de notes', () {
      final CauriSoundPlan one = CauriSoundPlan.forCount(1);
      final CauriSoundPlan eight = CauriSoundPlan.forCount(8);
      final CauriSoundPlan twenty = CauriSoundPlan.forCount(20);
      final CauriSoundPlan huge = CauriSoundPlan.forCount(5000);

      expect(one.density, 1);
      expect(eight.density, greaterThan(one.density));
      expect(twenty.density, greaterThan(eight.density));
      // L'oreille ne distingue plus les impacts au-delà du plafond.
      expect(huge.density, CauriSoundPlan.maxNotes);
      expect(huge.count, CauriSoundPlan.maxVisible);
    });

    test('la cadence se resserre quand le nombre augmente', () {
      expect(CauriSoundPlan.staggerFor(1), 0);
      expect(
        CauriSoundPlan.staggerFor(60),
        lessThan(CauriSoundPlan.staggerFor(20)),
      );
      expect(
        CauriSoundPlan.staggerFor(20),
        lessThan(CauriSoundPlan.staggerFor(4)),
      );
      expect(CauriSoundPlan.staggerFor(60), greaterThan(0));
    });

    test('la nuance progresse sans jamais saturer', () {
      final CauriSoundPlan one = CauriSoundPlan.forCount(1);
      final CauriSoundPlan twenty = CauriSoundPlan.forCount(20);
      final CauriSoundPlan huge = CauriSoundPlan.forCount(5000);

      expect(twenty.peakVolume, greaterThan(one.peakVolume));
      expect(huge.peakVolume, greaterThanOrEqualTo(twenty.peakVolume));
      for (final CauriSoundPlan plan in <CauriSoundPlan>[one, twenty, huge]) {
        for (final CauriNote note in plan.notes) {
          expect(note.volume, inInclusiveRange(0.0, 1.0));
        }
        expect(plan.peakVolume, lessThanOrEqualTo(1.0));
      }
    });

    test('les impacts restent dans la timeline de l’animation', () {
      for (final int count in <int>[1, 5, 20, 60, 900]) {
        final CauriSoundPlan plan = CauriSoundPlan.forCount(count);
        for (final CauriNote note in plan.notes) {
          expect(note.at, greaterThanOrEqualTo(plan.firstImpact));
          expect(note.at, lessThanOrEqualTo(1.0));
        }
        expect(plan.lastImpact, lessThanOrEqualTo(1.0));
        expect(plan.firstImpact, CauriSoundPlan.firstImpactAt);
      }
    });

    test('la chute n’est pas une répétition mécanique', () {
      final CauriSoundPlan plan = CauriSoundPlan.forCount(20);
      final Set<double> volumes = plan.notes
          .map((CauriNote note) => note.volume)
          .toSet();
      // Plusieurs nuances alternent au lieu d'un unique volume répété.
      expect(volumes.length, greaterThan(2));
      // La dernière note est accentuée : la chute se termine sur un temps fort.
      expect(plan.notes.last.volume, plan.peakVolume);
      // Les positions ne tombent pas toutes sur une grille parfaite.
      final Set<double> positions = plan.notes
          .map((CauriNote note) => note.at)
          .toSet();
      expect(positions.length, plan.notes.length);
    });

    test('un nombre nul reste une chute minimale', () {
      final CauriSoundPlan plan = CauriSoundPlan.forCount(0);
      expect(plan.count, 1);
      expect(plan.density, 1);
      expect(plan.reachedAt(0), 0);
      expect(plan.reachedAt(1), 1);
    });
  });
}
