import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:akiba/core/database/akiba_database.dart';
import 'package:akiba/core/database/akiba_secure_key.dart';
import 'package:akiba/core/state/akiba_settings.dart';
import 'package:akiba/core/theme/akiba_colors.dart';
import 'package:akiba/core/theme/akiba_theme.dart';
import 'package:akiba/data/sqlite_akiba_store.dart';

/// Rapport de contraste WCAG 2.1 (1 → 21).
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double light = la > lb ? la : lb;
  final double dark = la > lb ? lb : la;
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  group('Thèmes AKIBA', () {
    test('cinq thèmes, Blanc par défaut et repli sûr', () {
      expect(AkibaThemeId.values.length, 5);
      expect(AkibaThemeId.values.first, AkibaThemeId.blanc);
      expect(AkibaThemeId.blanc.label, 'Blanc');
      expect(AkibaThemeId.sombre.label, 'Sombre');
      expect(AkibaThemeId.bleu.label, 'Bleu');
      expect(AkibaThemeId.vert.label, 'Vert');
      expect(AkibaThemeId.or.label, 'Jaune Or');
      expect(AkibaThemeId.fromStorage(null), AkibaThemeId.blanc);
      expect(AkibaThemeId.fromStorage('inconnu'), AkibaThemeId.blanc);
      expect(AkibaThemeId.fromStorage('or'), AkibaThemeId.or);
      expect(AkibaThemeId.sombre.brightness, Brightness.dark);
      expect(AkibaThemeId.or.brightness, Brightness.light);
    });

    test('chaque thème garde un contraste élevé', () {
      for (final AkibaThemeId id in AkibaThemeId.values) {
        final AkibaColors c = id.palette;
        expect(
          _contrast(c.textPrimary, c.background),
          greaterThanOrEqualTo(10),
          reason: '${id.label} : titres sur le fond',
        );
        expect(
          _contrast(c.textPrimary, c.surface),
          greaterThanOrEqualTo(10),
          reason: '${id.label} : titres sur les cartes',
        );
        expect(
          _contrast(c.textMuted, c.surface),
          greaterThanOrEqualTo(4.5),
          reason: '${id.label} : textes secondaires sur les cartes',
        );
        expect(
          _contrast(c.textMuted, c.background),
          greaterThanOrEqualTo(4.5),
          reason: '${id.label} : textes secondaires sur le fond',
        );
        // Montant héros (36 pt) et libellés de la carte de solde : seuil
        // « grand texte » de la norme.
        expect(
          _contrast(c.onTerracotta, c.terracotta),
          greaterThanOrEqualTo(3),
          reason: '${id.label} : texte clair sur la couleur d’action',
        );
        // La carte de solde est un dégradé jusqu'à `terracottaDeep`.
        expect(
          _contrast(c.onTerracotta, c.terracottaDeep),
          greaterThanOrEqualTo(3),
          reason: '${id.label} : texte clair sur le bas du dégradé',
        );
      }
    });

    test('le thème choisi est réellement persisté', () async {
      final Directory directory = Directory.systemTemp.createTempSync(
        'akiba_theme',
      );
      final Database db = AkibaDatabase.openEncrypted(
        p.join(directory.path, 'akiba.db'),
        keyHex: AkibaSecureKey.generateHexKey(),
      );
      final SqliteAkibaStore store = SqliteAkibaStore(db);

      final AkibaSettings settings = AkibaSettings(store);
      await settings.load();
      expect(settings.themeId, AkibaThemeId.blanc);

      await settings.setThemeId(AkibaThemeId.vert);
      expect(settings.themeId, AkibaThemeId.vert);

      // Relecture depuis la base : le choix survit au redémarrage.
      final AkibaSettings reopened = AkibaSettings(store);
      await reopened.load();
      expect(reopened.themeId, AkibaThemeId.vert);

      db.close();
      directory.deleteSync(recursive: true);
    });
  });
}
