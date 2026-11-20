# DEJA_FAIT — Journal AKIBA

Dernière mise à jour : **20/11/2026** · Étapes **1.1 → 1.3** de la Phase 1, puis
**Étapes 4 → 11** (saisie rapide, portefeuille, analyses, profil, assistant IA /
SMS / sauvegardes, onboarding E1→E11, animations, revue complète et
configuration release, gestion de la clé IA et cascade de modèles, règles
complètes des créances et dettes) terminées.

Ce fichier est l'historique de ce qui est réellement codé et vérifié. Il est mis à
jour après chaque modification, comme demandé dans
`akiba_spec/akiba_animations_notifications_regles..txt` (§1, « Suivi obligatoire »).

---

## Phase 0 — Cadrage (terminée)

| Élément | État |
| --- | --- |
| Cahier des charges v2.0 (`akiba_spec/Cahier des charges AKIBA.md`, 313 lignes) | Lu et intégré : identité, devises, design system, navigation, onboarding E1→E11, modules M01→M23 |
| Règles UI/UX en dur (`akiba_animations_notifications_regles..txt`) | Intégrées : barre basse pleine largeur, cochon à droite, IA au-dessus, logos obligatoires, suivi documentaire |
| `akiba_spec/a_savoir.txt` | **Fichier vide (0 octet)** : aucun contenu à intégrer. À compléter par le porteur du projet. |
| `akiba_spec/maquette.jpg` + `akiba_spec/bar_navigation.jpg` | Analysés : carte de solde terre cuite dégradée, tuiles arrondies, histogrammes, ventilation, transactions, barre basse pleine largeur type WhatsApp |
| Logos (`mixx.png`, `moov_money.jpg`, `orabank_dark.png`, `Logo/`) | Copiés dans `assets/` et branchés dans les composants |
| `akiba_spec/maquette_complet/` | Inventaire repéré (36 captures + maquettes HTML) : servira de référence écran par écran aux phases suivantes |

---

## Phase 1 — Socle : design system, données locales et accueil

### Étape 1.1 — Design system clair/sombre, FCFA, barre basse non flottante, boutons latéraux, logos ✅

**Objectif** : poser les fondations visuelles de toute l'application sans coder
de logique métier.

#### Livrables

| Fichier | Rôle |
| --- | --- |
| `lib/core/theme/akiba_tokens.dart` | Espacements (4→32), rayons (28/24/16/14/pilule), tailles (tactile 48, cochon 56, barre 64) et durées d'animation (150/250/300/400 ms) |
| `lib/core/theme/akiba_colors.dart` | Palette complète en `ThemeExtension` : thème clair `#FAF4E6 / #FFFFFF / #F3E9D6 / #F1DFC8 / #C7673D / #9E4B27 / #C69F47 / #E8D5A8 / #1A1816 / #6F685B`, thème sombre `#0E0D0C / #1A1816 / #24211E / #F3EEE2 / #A59E90`, sémantique `#5E9E6E / #E0963A / #C94B3F`. Dégradé 135° de la carte de solde, ombres douces en clair, aucune ombre en sombre, `lerp` pour les transitions de thème |
| `lib/core/theme/akiba_typography.dart` | Échelle Poppins (titres, corps, légendes) + style montant Inter avec `FontFeature.tabularFigures()` |
| `lib/core/theme/akiba_theme.dart` | `AkibaTheme.light()` / `AkibaTheme.dark()` : fond crème, surfaces, zéro bordure, appBar plate, Card 24 dp, Divider invisible |
| `lib/core/format/akiba_money.dart` | FCFA sans décimale, espace insécable comme séparateur de milliers, mode masqué `•••••• FCFA`, montants signés, pourcentages |
| `lib/core/widgets/akiba_bottom_bar.dart` | Barre ancrée en bas, **pleine largeur, non flottante, sans bords arrondis**, 4 onglets (Accueil, Analyses, Portefeuille, Profil), onglet actif terre cuite, zones ≥ 48 dp, sémantique lecteur d'écran |
| `lib/core/widgets/akiba_side_actions.dart` | Colonne de droite : **icône Assistant IA (44 dp) juste au-dessus du bouton cochon (56 dp)**, jamais au centre de la barre ; appui long sur le cochon = assistant vocal |
| `lib/core/widgets/brand_logo.dart` | `BrandLogo` (logos officiels Flooz, Mixx by Yas, Orabank + emblème liquide) aux tailles 28/36/48 dp, et `AccountBadge` = logo + nom + sous-titre + montant, sémantique complète |
| `lib/core/widgets/akiba_surface_card.dart` | Carte de surface arrondie sans bordure, ombre douce uniquement en thème clair |
| `lib/features/shell/akiba_shell.dart` | Coquille : barre basse + boutons latéraux + onglets (vitrine, placeholders pour Analyses / Portefeuille / Profil) |
| `lib/features/design_system/design_system_preview.dart` | Vitrine de contrôle : carte de solde, liste des 4 supports, formats FCFA, palette, typographie, bascule masquage et Clair/Sombre/Système |
| `lib/main.dart` | `AkibaApp` : thème clair par défaut, `darkTheme` prêt, `ThemeMode` piloté |
| `pubspec.yaml` | Déclaration de `assets/brand/` et `assets/logos/` |
| `assets/brand/`, `assets/logos/` | `akiba_mark_light.png`, `akiba_mark_dark.png`, `flooz.jpg`, `mixx.png`, `orabank.png` |
| `test/widget_test.dart` | Tests du format FCFA (normal, masqué, signé) + fumée de la barre basse |

#### Décisions et écarts assumés

1. **Barre basse à 4 onglets** : le cahier des charges §3.1 décrit 5 emplacements
   avec un bouton central, mais les règles UI/UX en dur (corrigeant les maquettes)
   imposent une barre pleine largeur épurée et le cochon sur le côté. La règle en
   dur a été retenue : Accueil, Analyses, Portefeuille, Profil.
2. **Bouton cochon** : cercle de surface blanche (sombre en thème sombre) portant
   l'emblème officiel `Logo/akiba_mark_light.png` (ou `akiba_mark.png` en sombre),
   afin que le cochon reste lisible sur la terre cuite. Taille 56 dp, zone tactile
   conforme, appui long réservé à l'assistant vocal.
3. **Logos** : `akiba_spec/mixx.png` est le logo **Yas** → utilisé pour Mixx by Yas ;
   `akiba_spec/moov_money.jpg` (Moov Money) → utilisé pour **Flooz** ;
   `orabank_dark.png` → **Orabank**. Les logos officiels sont posés dans une tuile
   blanche dans les deux thèmes pour ne pas être dénaturés ; le liquide utilise un
   pictogramme (aucun logo officiel fourni).
4. **Polices non embarquées** : aucun fichier `.ttf` Poppins/Inter n'est présent dans
   le dépôt. Les familles sont déclarées avec repli système
   (`Inter`, `Segoe UI`, `Roboto`, `Arial`) pour ne pas bloquer le socle.
   L'embarquement des polices est planifié en **Étape 1.5**.
5. **Espace insécable** : `15 000 FCFA` est produit avec `U+00A0`, visuellement
   identique au cahier des charges mais insécable (un montant ne se coupe pas).
6. **`a_savoir.txt` vide** : signalé ci-dessus, aucune consigne perdue.

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 13 fichiers formatés, 0 erreur |
| `flutter analyze` | 0 problème après correction des 4 avertissements de style |
| `flutter test` | 4 tests, tous passés (formats FCFA + fumée navigation) |

#### Ce qui n'est **pas** fait (volontairement)

- Aucune logique métier : pas de base de données, pas de PIN, pas de saisie,
  pas d'onboarding, pas d'IA, pas de notifications, pas de sauvegarde.
- À cette date, pas de carte de solde à frise de triangles, pas de `ActionPill`,
  `AIInsightCard`, `QuickActionTile`, `TransactionRow`. **Depuis réalisés à
  l'Étape 1.3** ; `BarChart`, `BreakdownRow`, `SegmentedControl` et
  `MosaicTile` restent à faire en Étape 1.4.
- Pas de rail latéral Windows ni de raccourcis clavier : Étape 1.7.
- Le code n'a pas été lancé en exécution graphique (aucun build Windows/Android
  effectué) : seul l'analyseur et les tests widgets ont été exécutés.

---

### Étape 1.2 — Base SQLite locale chiffrée, modèles et solde disponible ✅

**Objectif** : poser la couche de données locale, chiffrée, sans écran métier
supplémentaire.

#### Livrables

| Fichier | Rôle |
| --- | --- |
| `lib/core/database/akiba_schema.dart` | Schéma versionné par `PRAGMA user_version` (v1) : `accounts`, `transactions`, `savings_pots`, `third_parties`, `debts`, `settings`, index (date, compte, catégorie, neutre, épargne, sens de dette) et vue `v_account_balances` qui **recalcule** chaque solde |
| `lib/core/database/akiba_secure_key.dart` | Clé AES-256 générée avec `Random.secure()` (64 caractères hexadécimaux) et conservée dans `flutter_secure_storage` (Keystore Android, DPAPI / Credential Manager Windows) |
| `lib/core/database/akiba_database.dart` | Ouverture chiffrée : `PRAGMA key = "x'…'"`, `cipher_memory_security`, clés étrangères, WAL, lecture de contrôle qui échoue si le fichier n'est pas déchiffrable, puis migrations |
| `lib/data/models/account_brand.dart` | `AccountBrand` déplacé dans la couche données (libellé + logo officiel), la présentation restant dans `brand_logo.dart` |
| `lib/data/models/account.dart` | `Account` (jamais de champ solde) et `AccountBalance` (solde calculé) |
| `lib/data/models/transaction_record.dart` | `TransactionKind` (entrée, sortie, transfert, ouverture, épargne) et `TransactionRecord` signé en FCFA entiers, avec `isNeutral`, tiers, compte de transfert, coffre et `countsForBudget` |
| `lib/data/models/savings_pot.dart` | `SavingsPot` + `SavingsKind` (urgence, objectif, libre) ; le montant épargné reste dérivé des transactions |
| `lib/data/models/third_party.dart` | `ThirdParty` (personne dont l'argent transite) |
| `lib/data/models/debt.dart` | `Debt` + `DebtDirection` (on me doit / je dois), `remaining` borné à 0 et `isSettled` |
| `lib/data/balance_summary.dart` | Règle unique : `disponible = comptes + épargne − argent de tiers`, plus entrées/sorties du mois hors neutre |
| `lib/data/akiba_store.dart` | Interface `AkibaStore`, `DashboardSnapshot`, `TransactionLine` et `EmptyAkibaStore` (repli sans base) |
| `lib/data/sqlite_akiba_store.dart` | Implémentation SQL : lecture du tableau de bord (soldes dérivés, mois courant, 5 derniers mouvements hors ouverture), CRUD comptes / transactions / coffres / tiers / dettes / réglages, requêtes **toutes paramétrées** |
| `pubspec.yaml` | Dépendances `sqlite3`, `flutter_secure_storage`, `path_provider`, `path` et section `hooks: user_defines: sqlite3: source: sqlcipher` (AES-256 compilé, aucune dépendance obsolète) |
| `test/data_test.dart` | 8 tests : règle du solde, épargne neutre pour le disponible, reversements, aller-retour des modèles, reste dû, clé 256 bits |
| `test/database_test.dart` | 7 tests : fichier illisible sans clé, migration idempotente, clé invalide refusée, soldes dérivés, tiers isolés du mois, versement sans effet sur le disponible, dettes et réglages persistés |

#### Décisions et écarts assumés

1. **Chiffrement** : `sqlite3` 3.x compile lui-même SQLCipher via son hook
   (`source: sqlcipher`), ce qui couvre Android **et** Windows. Le paquet
   `sqlcipher_flutter_libs` a été retiré : sa version 0.7.0 est un paquet vide
   (EOL) qui n'apporte plus rien.
2. **Clé brute** : la clé est passée à SQLCipher sous forme hexadécimale
   (`x'…'`), sans dérivation supplémentaire, car elle est déjà 256 bits
   aléatoires. Le PIN n'existe pas encore : sa dérivation (PBKDF2/Argon2) est
   l'Étape 2.1.
3. **Soldes** : aucun champ « solde » n'existe en base ; la vue
   `v_account_balances` et les sommes de transactions produisent tous les
   totaux. Les soldes d'ouverture sont des transactions (`kind = 'opening'`),
   exclues de la liste des derniers mouvements.
4. **Épargne** : un versement est une transaction `savings` négative sur le
   compte. Elle sort du total des comptes mais entre dans `savingsHeld`, donc
   **le solde disponible ne bouge pas** (test dédié). La formule du cahier des
   charges reste vraie quand l'épargne est vide.
5. **Repli de démarrage** : si le stockage sécurisé ou la base est
   indisponible, `main` journalise **uniquement le type d'erreur** et démarre
   avec `EmptyAkibaStore` (totaux à zéro). Aucun montant, aucune donnée
   personnelle dans les journaux.
6. **Catégories** : elles restent un texte libre sur la transaction. La table
   paramétrable (M06) appartient à la Phase 4.

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| Test de chiffrement isolé (avant intégration) | SQLCipher présent (`cipher_version` non vide) et base refusée sans clé |
| `flutter analyze` | 0 problème |
| `flutter test` | 19 tests, tous passés (dont 15 sur la couche données) |

---

### Étape 1.3 — Écran Accueil / Dashboard ✅

**Objectif** : remplacer la vitrine technique par le véritable écran d'accueil,
en thème clair par défaut, alimenté par la base locale.

#### Livrables

| Fichier | Rôle |
| --- | --- |
| `lib/core/widgets/triangle_fringe.dart` | Peintre de la frise de triangles, réutilisable (haut ou bas, hauteur et couleur paramétrables) |
| `lib/core/widgets/balance_card.dart` | Carte héroïne : dégradé 135°, frise sable à 35 % en haut et en bas (jamais derrière le texte), montant héros 36 pt, composition du solde, pilules Transférer / Ajouter |
| `lib/core/widgets/action_pill.dart` | `ActionPill` 48 dp, variantes ocre / blanche / terre cuite |
| `lib/core/widgets/ai_insight_card.dart` | `AIInsightCard` : tuile 40 dp, titre 15 pt/600, texte 13 pt, chiffre clé coloré, maximum 5 lignes |
| `lib/core/widgets/quick_action_tile.dart` | `QuickActionTile` 24 dp d'icône, libellé 12 pt |
| `lib/core/widgets/transaction_row.dart` | `TransactionRow` : avatar 44 dp, titre, sous-titre (catégorie · jour · heure), montant aligné, pastille « Tiers » |
| `lib/core/widgets/icon_circle_button.dart` | Bouton rond 48 dp partagé (œil de masquage, apparence) |
| `lib/core/format/akiba_date.dart` | Dates françaises `jj/mm/aaaa`, heures `HH h mm`, « Aujourd'hui / Hier » |
| `lib/features/dashboard/dashboard_screen.dart` | Accueil complet : en-tête daté, solde disponible, carte Argent de tiers avec Total des comptes / Épargne / Solde disponible, Aperçu IA à coquille, 4 actions rapides, dernières transactions, état vide à frise, états chargement et erreur, masquage, bascule d'apparence |
| `lib/features/shell/akiba_shell.dart` | Le premier onglet devient l'Accueil ; la coquille porte l'état de masquage et le transmet |
| `lib/main.dart` | Démarrage asynchrone : ouverture de la base chiffrée avant l'interface, repli vide documenté |
| `lib/core/widgets/brand_logo.dart` | Importe `AccountBrand` depuis la couche données et n'ajoute plus qu'une icône de repli de présentation |
| `test/widget_test.dart` | Fumée mise à jour : « Mon argent », solde, argent de tiers, aperçu IA, actions rapides, transactions, 4 onglets |

#### Décisions et écarts assumés

1. **Thème clair strict par défaut** : `ThemeMode.light` au démarrage ; le
   bouton d'apparence reste disponible pour contrôler aussi le thème sombre.
   Le réglage persistant et la tuile Apparence restent en Phase 2.
2. **Responsivité** : une seule colonne sous 900 px, deux colonnes au-delà
   (solde + IA + actions à gauche, tiers + transactions à droite), contenu
   limité à 1 180 px et centré, marge basse de 160 px pour ne jamais passer
   sous le cochon ni sous la barre. La barre basse reste ancrée sur toute la
   largeur, y compris sur grand écran, conformément aux règles en dur.
3. **Masquage** : l'œil de l'en-tête masque **tous** les montants de l'accueil
   (solde, composition, tiers, total des comptes, épargne, mouvements) et
   l'aperçu IA bascule sur un texte sans chiffre. La persistance du réglage,
   les graphiques et les notifications restent à faire (Étape 1.4).
4. **Aperçu IA** : coquille locale, sans réseau ni clé. Elle affiche un texte
   d'accueil si la base est vide, un texte sans chiffre si le masquage est
   actif, sinon les dépenses du mois. Le module M12 (Gemini) reste en Phase 6.

5. **Actions** : Transférer, Ajouter, Entrée, Sortie, Transfert, Épargne,
   « Voir tout » et les lignes de mouvement affichent un message renvoyant à
   leur phase. Aucune feuille de saisie n'est codée : c'est le périmètre des
   Phases 4 et 5.
6. **Pas de pastille de variation** sur la carte de solde : elle exigerait un
   historique comparatif qui n'existe pas encore ; mieux vaut pas de chiffre
   qu'un chiffre inventé.
7. **Vitrine conservée** : `lib/features/design_system/design_system_preview.dart`
   n'est plus montée dans la navigation, mais reste la référence visuelle du
   socle (palette, formats, typographie).

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 36 fichiers formatés |
| `flutter analyze` | **No issues found!** (0 problème) |
| `flutter test` | **19 tests, tous passés** |

#### Ce qui n'est **pas** fait (volontairement)

- Aucune exécution graphique : pas de `flutter run`, pas de build Windows ou
  Android. Le rendu visuel (carte, frise, deux colonnes) et l'ouverture réelle
  de la base via le stockage sécurisé **n'ont pas été vus à l'écran**.
- Pas de saisie, pas de PIN, pas de biométrie, pas d'onboarding, pas de budget,
  pas d'épargne opérationnelle, pas d'IA distante, pas de notifications, pas de
  sauvegarde.
- Le rail Windows, les raccourcis clavier et les polices embarquées restent les
  Étapes 1.6 et 1.7 du plan mis à jour.
---

### Étape 4 — Saisie rapide entrée / sortie / transfert / argent de tiers ✅

**Objectif** : enregistrer un mouvement en moins de 10 secondes depuis le
bouton cochon, sans construire les écrans des phases suivantes.

#### Livrables

| Fichier | Rôle |
| --- | --- |
| `lib/data/models/budget.dart` | `Budget`, `BudgetStatus` et `BudgetLevel` (seuils 80 % / 100 %) ; la dépense du mois est calculée, jamais stockée |
| `lib/core/database/akiba_schema.dart` | Migration **v2** : table `budgets` (une ligne par catégorie, plafond > 0), les bases v1 existantes migrent sans perte |
| `lib/data/akiba_store.dart` | Interface étendue : soldes par compte, budgets du mois, écriture/suppression de budget, suppression de mouvement, création des comptes par défaut |
| `lib/data/sqlite_akiba_store.dart` | Requêtes paramétrées correspondantes ; suppression d'un transfert = suppression de ses **deux** écritures ; `ensureDefaultAccounts` idempotent |
| `lib/core/state/masked_amounts.dart` | Masquage global (`InheritedNotifier`) : un seul état pour l'œil, les cartes, les listes et les aperçus |
| `lib/core/state/akiba_data_revision.dart` | Signal de rafraîchissement : après chaque écriture, les écrans abonnés relisent la base |
| `lib/core/widgets/segmented_control.dart` | `SegmentedControl` pilule (surface élevée, segment actif terre cuite) |
| `lib/features/quick_entry/quick_entry.dart` | Feuille de saisie : 4 modes, montant FCFA, comptes avec logo + nom, catégories, note, validation, avertissements non bloquants, écriture et bandeau « Annuler » 5 s |
| `lib/features/dashboard/dashboard_screen.dart` | Le cochon, les pilules de la carte et les actions rapides ouvrent la saisie ; glissement droite = modifier, gauche = supprimer avec annulation ; masquage partagé |
| `lib/features/shell/akiba_shell.dart` | Ouvre la saisie depuis le bouton cochon, porte le masquage et le signal de données, « Voir tout » bascule sur Portefeuille |
| `lib/main.dart` | Création des quatre comptes (Liquide, Flooz, Mixx by Yas, Orabank) au premier lancement, en attendant l'onboarding |
| `test/database_test.dart` | +3 tests : comptes par défaut uniques, budget ignorant l'argent de tiers, suppression d'un transfert complet |
| `test/data_test.dart` | +2 tests : seuils du budget et bornes de jauge |

#### Décisions et écarts assumés

1. **Mobile / desktop** : feuille modale en bas sous 720 px, boîte de dialogue
   centrée de 560 px au-delà. Le clavier ne masque jamais le bouton
   d'enregistrement (`viewInsets`).
2. **Quatre modes** : Entrée, Sortie, Transfert, Tiers. Un transfert s'écrit en
   deux lignes symétriques (sortie + entrée) ; le modifier ou le supprimer
   traite les deux, sinon le total des comptes dériverait (test dédié).
3. **Validation FCFA** : entier strictement positif, 9 chiffres maximum
   (999 999 999), deux comptes distincts pour un transfert. Les messages
   d'erreur bloquent l'enregistrement.
4. **Avertissements non bloquants** : solde insuffisant sur le compte débité et
   budget de catégorie dépassé s'affichent en orange, mais l'écriture reste
   possible (règle du cahier des charges : AKIBA conseille, ne bloque pas).
5. **Budgets en avance de phase** : la table `budgets` (v2) est ajoutée ici car
   l'avertissement « budget dépassé » en dépend. **L'écran Budget complet
   (jauges, édition) reste l'Étape 6.**
6. **Bandeau sans montant** : « Enregistré · Sortie enregistrée » puis
   « Annuler » pendant 5 s. Aucun FCFA dans le texte, pour respecter le
   masquage même dans les aperçus de notification du système.
7. **Annulation** : elle supprime réellement les écritures créées
   (`deleteTransaction`), ou restaure la ligne supprimée par glissement.
8. **Catégories** : listes prédéfinies (Alimentation, Transport, Loyer, Santé,
   École, Tontine, Autre / Salaire, Vente, Don, Autre). La table de catégories
   paramétrable (M06) reste à faire.
9. **Comptes par défaut** : les quatre supports sont créés au premier lancement
   pour que la saisie soit utilisable sans onboarding. La gestion (renommage,
   ajout) arrive à l'Étape 5.
10. **Aperçu IA** : le texte a été ajusté pour renvoyer vers le cochon et les
    Analyses, sans inventer de chiffre.

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | OK |
| `flutter analyze` | **No issues found!** (0 problème) |
| `flutter test` | **24 tests, tous passés** (dont 5 nouveaux sur budgets, comptes par défaut et transferts) |

#### Ce qui n'est **pas** fait (volontairement)

- Pas de saisie vocale ni d'IA (M12, Phase 6), pas de lecture SMS (M13).
- Pas d'écran Budget ni de tuile de catégories paramétrables.
- Pas de suppression par confirmation : le glissement supprime puis propose
  « Annuler » 5 s (à réévaluer en Phase 2).
- Aucune exécution graphique : le rendu de la feuille (mobile et desktop) n'a
  pas été vu à l'écran.
---

### Étape 5 — Écran Portefeuille (comptes, mouvements, épargne, tiers et dettes) ✅

**Objectif** : structurer le portefeuille en sous-vues claires, en réutilisant la
saisie rapide existante et sans ouvrir les modules d'analyse.

#### Livrables

| Fichier | Rôle |
| --- | --- |
| `lib/data/models/savings_pot.dart` | `SavingsPotBalance` : montant épargné dérivé des transactions, part consommée, objectif atteint |
| `lib/data/models/third_party.dart` | `ThirdPartyBalance` : argent détenu pour chaque tiers (entrées neutres − reversements) |
| `lib/data/akiba_store.dart` | `savingsBalances`, `thirdPartyBalances`, `movements(from, to, limit)` |
| `lib/data/sqlite_akiba_store.dart` | Requêtes agrégées (coffres, tiers) et filtre de période paramétré ; `_recent` réutilise désormais `movements` (une seule requête de mouvements) |
| `lib/core/widgets/account_pill.dart` | Pilule de compte partagée (logo officiel + nom), utilisée par la saisie rapide et les dialogues du portefeuille |
| `lib/core/format/transaction_display.dart` | Icône, titre, sous-titre et couleur d'un mouvement, partagés par l'accueil et le portefeuille |
| `lib/features/portfolio/portfolio_screen.dart` | Écran complet : en-tête masquable, `SegmentedControl` 4 sous-vues, comptes, calendrier + mouvements du mois, coffres à jauges animées, tiers, créances et dettes |
| `lib/features/shell/akiba_shell.dart` | L'onglet Portefeuille monte le véritable écran |
| `test/database_test.dart` | +2 tests : montants des coffres et des tiers, filtre de période des mouvements |

#### Détail des sous-vues

1. **Comptes** : total des comptes, un bloc par support (logo + nom + support +
   solde), ajout et renommage d'un compte avec choix du support. Les soldes
   restent dérivés : aucune saisie de solde.
2. **Mouvements** : navigation mois par mois, calendrier maison (aucune
   dépendance) avec pastille sur les jours mouvementés, sélection d'un jour
   pour filtrer, regroupement par jour et liste sans filet.
3. **Épargne** : total épargné, un coffre par objectif (fonds d'urgence,
   objectif daté ou libre), jauge animée (600 ms, `easeOutCubic`), montant /
   objectif, pourcentage, versement et retrait avec choix du compte.
4. **Tiers et dettes** : total de l'argent de tiers détenu, un bloc par tiers
   avec « Reverser » (plafonné au montant détenu), totaux « On me doit » /
   « Je dois », liste des créances et dettes avec échéance et « Régler »
   (plafonné au reste dû).

#### Décisions et écarts assumés

1. **Argent de tiers** : le reversement crée une sortie **neutre** ; il ne
   touche donc ni le budget, ni les statistiques, et réduit uniquement
   l'argent de tiers (testé en base depuis l'Étape 1.2).
2. **Créances et dettes** : suivies séparément, jamais ajoutées au solde
   disponible (règle du cahier des charges et texte explicite à l'écran).
3. **Versement d'épargne** : transfert compte → coffre, sans effet sur le solde
   disponible ; le retrait est plafonné au montant réellement épargné.
4. **Garde-fous bloquants** : retrait > épargne, reversement > détention,
   règlement > reste dû. Les saisies rapides, elles, gardent des
   avertissements non bloquants.
5. **Jauges** : animation de 600 ms désactivée par la préférence système
   (`MediaQuery.disableAnimations` non branchée à ce stade ; le réglage
   « Réduire les animations » reste en Phase 2/7).
6. **Édition** : un mouvement se modifie via la saisie rapide (même feuille,
   préremplie) ; un mouvement d'épargne renvoie vers l'onglet Épargne.
7. **Masquage** : l'œil du portefeuille pilote le même état global que
   l'accueil ; tous les montants, pourcentages et totaux masqués suivent.
8. **Mise en page** : colonne unique centrée (max 1 040 px), calendrier
   pleine largeur, marge basse de 160 px pour le cochon et la barre.
9. **Proposition de versement (0→30 %)** et **simulation de coup dur** ne sont
   pas codées : elles dépendent des réglages d'onboarding (Phase 3) et de M11.

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | OK |
| `flutter analyze` | **No issues found!** (0 problème) |
| `flutter test` | **26 tests, tous passés** (dont 2 nouveaux sur coffres, tiers et périodes) |

#### Ce qui n'est **pas** fait (volontairement)

- Pas de graphiques de statistiques, pas de budget éditable, pas de besoins
  priorisés : Étape 6.
- Pas d'objectif daté calculé (date d'atteinte dynamique), pas de fonds
  d'urgence avec paliers 25/50/75/100 %, pas de simulation de coup dur.
- Pas de recherche, pas de pagination, pas de reclassement de catégorie.
- Aucune exécution graphique : le calendrier, les jauges et les dialogues n'ont
  pas été vus à l'écran.
---

### Étape 6 — Écran Analyses (statistiques, budgets, besoins, bilans) ✅

**Objectif** : lire les chiffres sans jamais mélanger l'argent de tiers ni
l'épargne, avec des jauges de budget et un seuil de « payable » explicite.

#### Livrables

| Fichier | Rôle |
| --- | --- |
| `lib/data/models/analysis.dart` | `CategoryTotal`, `AccountPeriodTotal` (revenus/sorties par compte), `MonthTotal` (revenus, dépenses, neutre entrant/sortant) |
| `lib/data/models/need.dart` | `Need` + `NeedPriority` (haute/moyenne/basse) et la règle `isAffordable(capacité)` |
| `lib/core/database/akiba_schema.dart` | Migration **v3** : table `needs` (montant > 0, priorité 1→3, échéance, soldé) |
| `lib/data/akiba_store.dart` / `sqlite_akiba_store.dart` | `categoryTotals` (dépenses ou revenus, hors neutre et épargne), `accountTotals`, `monthlyTotals`, `needs` + écriture/suppression, `settingInt` pour la réserve |
| `lib/features/analysis/analysis_screen.dart` | Écran complet : en-tête masquable, `SegmentedControl` 4 sous-vues, période, histogramme, ventilations, budgets à jauges animées, besoins priorisés, bilans comparés |
| `lib/features/shell/akiba_shell.dart` | L'onglet Analyses monte le véritable écran |
| `test/database_test.dart` | +3 tests : statistiques sans tiers ni épargne, bilans avec neutre isolé, besoins et réserve |

#### Détail des sous-vues

1. **Statistiques** : période Semaine (7 jours) / Mois / Année / Tout, total
   des dépenses et des revenus, net, histogramme à double tonalité (sable =
   plafond, terre cuite = dépensé), ventilation par catégorie (montant,
   pourcentage, barre arrondie) et tableau par compte avec logo, sorties et
   entrées en FCFA.
2. **Budget** : plafonds mensuels par catégorie, jauge animée (600 ms),
   couleur verte < 80 %, orange de 80 % à 100 %, rouge au-delà, reste à
   dépenser, ajout, modification et suppression.
3. **Besoins** : réserve de sécurité modifiable, capacité d'achat
   (`disponible − réserve`), liste priorisée avec statut « Payable bientôt » /
   « Hors de portée » / « Soldé », échéance, ajout, règlement, suppression.
4. **Bilans** : six derniers mois (douze pour Année/Tout), revenus, dépenses,
   net, comparaison en pourcentage avec le mois précédent, et ligne isolée
   « argent de tiers exclu : reçus / reversés ».

#### Décisions et écarts assumés

1. **Périmètre des calculs** : toutes les agrégations filtrent
   `is_neutral = 0` et excluent `savings` et `opening`. Un test vérifie qu'une
   dépense neutre et un versement d'épargne ne modifient ni les catégories ni
   les totaux de compte.
2. **Argent de tiers** : présenté uniquement comme information isolée dans les
   bilans (reçu / reversé), jamais additionné aux revenus ou aux dépenses.
3. **Plafond de l'histogramme** : si des budgets existent, le repère sable vaut
   la part quotidienne des plafonds ; sinon il sert d'échelle relative. Aucun
   budget quotidien fictif n'est inventé.
4. **Besoins** : le seuil est calculé, jamais saisi ; la réserve est un réglage
   (`reserve_securite`) modifiable depuis l'écran.
5. **Budgets** : le mois budgétaire commence le 1er (paramétrage prévu mais non
   codé, cf. Étape 4.5 restante). La jauge est bornée à 100 % mais le
   pourcentage affiché peut dépasser 100 %.
6. **Pourcentages** : masqués (`••• %`) quand le masquage est actif ; les
   formes des jauges restent visibles, sans révéler de montant.
7. **Édition** : un plafond existant est remplacé via `saveBudget` (même
   catégorie) ; la suppression est immédiate.
8. **Réserve et besoins** ne touchent pas au solde disponible : ils n'en
   changent que la lecture « payable / hors de portée ».

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | OK |
| `flutter analyze` | **No issues found!** (0 problème) |
| `flutter test` | **29 tests, tous passés** (dont 3 nouveaux sur les agrégats, les bilans et les besoins) |

#### Ce qui n'est **pas** fait (volontairement)

- Pas de conseils IA ni de bilan exporté (M17), pas de saisie libre IA (M12),
  pas d'extraction SMS (M13), pas de clé Gemini.
- Pas de détail de transaction ni de reclassement depuis le calendrier.
- Pas de mois budgétaire paramétrable, pas de budget spécial fête.
- Pas d'export CSV/PDF.
- Aucune exécution graphique : histogramme, jauges et dialogues n'ont pas été
  vus à l'écran.
### Étape 7 — Écran Profil & tableau Bento ✅

**Objectif** : un seul endroit pour l'accès (PIN, biométrie, masquage),
l'apparence, les préférences locales, les rappels et les accès optionnels
(IA, SMS, sauvegardes), sans jamais flotter au-dessus de la barre basse.

#### Livrables

| Fichier | Rôle |
| --- | --- |
| `lib/features/profile/profile_screen.dart` | Bento 1 → 3 colonnes (≥ 640 px, ≥ 980 px), tuiles Identité, Accès & PIN, Apparence, Préférences, Rappels, Google Drive / serveur maître / Home Lab, Assistant IA, SMS, Données & démonstration, Confidentialité |
| `lib/core/state/akiba_settings.dart` | Tous les réglages persistés (thème, réduction des animations, PIN, biométrie, verrouillage au retour, devise, dates, fuseau, rappels, DND, fêtes, URLs et jetons, simulation), `AkibaSettingsScope` pour la lecture partagée |
| `lib/core/security/pin_vault.dart` | `PinVault` : empreinte **SHA-256 salée et itérée** (20 000 tours), sel aléatoire 128 bits, refus des PIN triviaux, `isConfigured` / `setPin` / `verify` / `clear` |
| `lib/core/notifications/reminder_planner.dart` | Planification pure : trois créneaux, heures personnalisables, plage « Ne pas déranger » (y compris à cheval sur minuit), périodes de fête, rotation des messages, `sanitize` |
| `lib/core/notifications/local_notifications.dart` | Enrobage `flutter_local_notifications` (Android, iOS, macOS, Linux), `zonedSchedule`, canal unique, message clair si Windows ou l'autorisation n'est pas disponible |
| `lib/features/splash/splash_screen.dart` | `SplashScreen` (emblème + cauri), `SplashGate` (1,25 s), `LockGate` (PIN, biométrie, verrouillage sur pause si `lock_on_resume`) |
| `lib/features/shell/akiba_shell.dart` | L'onglet Profil monte le véritable écran ; barre basse **non flottante**, cochon latéral, IA juste au-dessus, bandeau simulation permanent |
| `lib/main.dart` | Réglages chargés avant l'arbre, formats FCFA/dates branchés sur les préférences, `MediaQuery.disableAnimations` forcé par « Réduire les animations », callback « Rejouer l'accueil » |

#### Détail des tuiles

1. **Identité** : prénom + nom, devise, fuseau, style de dates, version et
   mention « base chiffrée SQLCipher · AES-256 · aucune télémétrie ».
2. **Accès** : activation / changement / retrait du PIN (dialogues privés),
   biométrie conditionnée à un PIN existant (repli obligatoire), verrouillage
   au retour d'arrière-plan, bascule « Afficher / Masquer les montants ».
3. **Apparence** : Clair / Sombre / Système, « Réduire les animations »
   (fondu 150 ms, jauges sans rebond).
4. **Rappels** : matin / midi / soir avec heures, plage « Ne pas déranger »,
   période de fête et libellé, texte explicite « aucune notification ne contient
   de montant ».
5. **Sauvegardes** : Google Drive (dossier synchronisé), serveur maître (URL +
   jeton Bearer), Home Lab (URL + jeton), dernière sauvegarde, accès au centre de
   sauvegarde.
6. **IA / SMS** : état de l'assistant local et du collage de SMS, rappel que la
   micro n'enregistre rien sans action.
7. **Données & démonstration** : mode simulation, rejouer l'accueil.

#### Décisions et écarts assumés

1. **PIN** : le PIN n'est jamais stocké ; seule l'empreinte salée l'est, dans la
   base chiffrée. La clé de base n'est **pas** encore dérivée du PIN (ligne 2.1
   de `RESTE_A_FAIRE.md`).
2. **Biométrie** : `local_auth` v3, aucun capteur en test ; toute erreur renvoie
   faux et laisse le PIN faire foi.
3. **Notifications** : la planification tourne sur Android / iOS / macOS / Linux.
   Windows n'est pas pris en charge par le greffon : l'UI l'annonce au lieu de
   promettre une alerte.
4. **Période de fête** : fin d'année 15/12 → 05/01 par défaut, plus une plage
   personnalisée ; le rappel du soir est remplacé, jamais doublé.
5. **Masquage** : les messages n'ont jamais été écrits avec un montant ; un
   filtre `sanitize` retire en plus tout « … FCFA » résiduel.
6. **Bento** : 1 colonne < 640 px, 2 colonnes ≥ 640 px, 3 colonnes ≥ 980 px ;
   aucune largeur fixe, aucune tuile ne déborde de la barre basse (marge basse
   de 160 px dans le défilement).
7. **Sécurité de la biométrie** : elle ne remplace pas le PIN (choix assumé), et
   le PIN reste demandé après redémarrage.

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | OK |
| `flutter analyze` | **No issues found!** (0 problème) |
| `flutter test` | couvert par les 55 tests de l'Étape 9 (dont empreinte PIN, refus des PIN triviaux, réglages persistés, DND, fêtes, masquage) |

#### Ce qui n'est pas fait (volontairement)

- Pas de dérivation de la clé de base depuis le PIN, pas de limitation du nombre
  d'essais (lignes 2.1 / 2.2).
- Pas de Windows Hello testé, pas de rappels visibles sur Windows.
- Aucune exécution graphique : la grille Bento n'a pas été vue à l'écran.

---

### Étape 8 — Assistant IA, revue SMS et sauvegardes chiffrées ✅

**Objectif** : proposer sans jamais écrire, relire les SMS mobile money et
banque sans mélanger l'argent des autres, et sauvegarder de façon chiffrée vers
trois cibles avec contrôle de conflit.

#### Livrables

| Fichier | Rôle |
| --- | --- |
| `lib/core/ai/ai_command_parser.dart` | `AiCommandParser` local (aucun réseau) : montant en chiffres, « 5k », catégorie parmi 8 familles, entrée / sortie / transfert, opérateur source et destination, « hier » / « avant-hier », argent de tiers, indice de confiance |
| `lib/features/assistant/assistant_sheet.dart` | Feuille « Assistant IA » : phrase libre, micro (halo + message honnête, sans greffon STT), carte de compréhension **éditable** (type, montant, catégorie, compte, note, tiers), bouton « Confirmer » seul à écrire |
| `lib/core/sms/sms_parser.dart` | `SmsParser` : découpage multi-SMS, montants « 5 000 FCFA » / « 5 000,00 », sens entrée / sortie, opérateur (Flooz, Mixx by Yas, Orabank), référence, frais, date, tiers détecté |
| `lib/features/sms/sms_review_sheet.dart` | Feuille de revue : collage de texte, une ligne par SMS, classement manuel entrée / sortie, compte de destination, case « argent de tiers », rien n'est écrit avant validation |
| `lib/core/backup/backup_service.dart` | Enveloppe JSON **AES-256-GCM**, clé **PBKDF2-HMAC-SHA256** (120 000 tours, sel 128 bits), empreinte SHA-256 du clair, métadonnées non sensibles, restauration additive, `putRemote` / `fetchRemote` (Bearer), `saveToFolder` / `readFolder`, `BackupMetadata.isNewerThan` |
| `lib/features/backup/backup_center.dart` | Centre de sauvegarde : cible Google Drive / serveur maître / Home Lab, phrase secrète, création, lecture, contrôle de conflit, restauration confirmée, dernière sauvegarde |
| `lib/features/shell/akiba_shell.dart` | Accès IA depuis le bouton latéral, accès SMS et sauvegarde depuis le Profil |

#### Détail des garde-fous

1. **Aucune exécution automatique** : `AiCommandParser` ne renvoie qu'un
   `AiDraft` ; l'écriture n'a lieu qu'après « Confirmer », avec les valeurs
   éventuellement corrigées.
2. **Carte éditable** : chaque champ de la proposition est modifiable ; la note
   garde la phrase d'origine pour la traçabilité.
3. **Argent de tiers** : détecté par « pour un client », « argent de tiers »,
   « cotisation », « au nom de » ; la ligne est enregistrée `is_neutral = 1` et
   reste hors budget, hors statistiques et hors solde disponible.
4. **SMS** : aucun accès à la boîte de réception (pas de permission `READ_SMS`) ;
   le texte est collé par la personne, puis relu ligne par ligne.
5. **Chiffrement** : le fichier ou la requête ne contient que du base64
   chiffré ; un test vérifie qu'aucun libellé en clair (« Salaire », « flooz »)
   n'apparaît dans l'enveloppe.
6. **Phrase secrète** : minimum 8 caractères, jamais enregistrée ; une mauvaise
   phrase lève `BackupException` sans rien révéler.
7. **Restauration** : additive uniquement (les identifiants déjà présents sont
   ignorés), aucune suppression ; les réglages sensibles (`pin_hash`,
   `pin_salt`, jetons, sauvegarde en attente) ne sont ni exportés ni restaurés.
8. **Conflit** : `lastMutationAt` de la sauvegarde est comparé au dernier
   mouvement local ; l'UI annonce le conflit avant toute restauration.
9. **Réseau** : Google Drive passe par un dossier synchronisé (aucun OAuth),
   serveur maître et Home Lab par HTTP PUT/GET explicites avec jeton.

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | OK |
| `flutter analyze` | **No issues found!** (0 problème) |
| `flutter test` | **55 tests, tous passés** — dont : sortie Flooz, entrée Mixx by Yas, SMS de tiers, découpage multiple, dépense catégorisée, montant « 25k », transfert Flooz → Mixx, phrase sans montant, aller-retour AES-GCM, mauvaise phrase refusée, format inconnu refusé, restauration sans doublon |

#### Ce qui n'est pas fait (volontairement)

- Pas de reconnaissance vocale réelle (aucun greffon STT) : le micro affiche un
  message honnête au lieu de faire semblant.
- Pas de lecture directe des SMS (collage manuel), pas d'expéditeurs
  configurables.
- Pas d'OAuth Google Drive, pas de clé Gemini (lignes 3.5 / 6.6 restantes).
- Les greffons natifs (`local_auth`, `flutter_local_notifications`) n'ont pas été
  compilés : le mode développeur Windows (liens symboliques) est absent sur le
  poste.
- Aucune sauvegarde n'a été envoyée à un vrai serveur ni déposée dans un vrai
  dossier Google Drive.

---

### Étape 9 — Onboarding E1 → E11, animations signature et vérification globale ✅

**Objectif** : un premier lancement guidé de bout en bout, des animations
signature désactivables, et une passe de cohérence sur l'ensemble.

#### Livrables

| Fichier | Rôle |
| --- | --- |
| `lib/features/onboarding/onboarding_flow.dart` | 11 étapes E1 → E11, barre de progression, « Étape n sur 11 », reprise via `onboarding_step`, retour possible sauf à E1, validations, soldes d'ouverture en transactions, récapitulatif final |
| `lib/main.dart` | `SplashGate` → onboarding au premier lancement, sinon `LockGate` + `AkibaShell` ; les formats FCFA / dates suivent les réglages |
| `lib/features/splash/splash_screen.dart` | Splash cauri 1,25 s, fondu, respect de « Réduire les animations » |
| `lib/features/dashboard/dashboard_screen.dart` | `_Cascade` : apparition des blocs à 40 ms d'intervalle, désactivée quand les animations sont réduites |
| `lib/features/portfolio/portfolio_screen.dart` | `_SavingsGauge` : paliers 25 / 50 / 75 %, haptique douce au franchissement, montants masqués respectés |
| `test/core_test.dart` | 26 nouveaux tests (PIN, réglages, rappels, SMS, assistant, sauvegarde) |
| `test/widget_test.dart` | Le premier démarrage ouvre bien l'onboarding (et non le dashboard) |

#### Parcours E1 → E11

1. **E1 Lancement** — emblème + cauri, « Bienvenue dans AKIBA », pas de retour.
2. **E2 Valeur perçue** — trois promesses (argent de tiers isolé, hors ligne,
   notifications sans montant).
3. **E3 Identité** — prénom (2 à 40 caractères) et nom obligatoires ; le
   dashboard n'est atteint qu'après cette étape.
4. **E4 Devise et fuseau** — FCFA (XOF), fuseau parmi Lomé, Cotonou, Abidjan,
   Dakar, Paris, style de dates.
5. **E5 Comptes de départ** — quatre tuiles avec logos, total en direct, soldes
   d'ouverture écrits en transactions `opening` (rien n'est inventé si vide).
6. **E6 PIN et biométrie** — 4 à 6 chiffres, confirmation, refus des PIN
   triviaux, biométrie proposée, « Plus tard » possible.
7. **E7 Google optionnel** — liaison d'un dossier Drive, entièrement
   contournable.
8. **E8 Permissions pédagogiques** — notifications, SMS, micro, Wi-Fi local :
   chacune expliquée et révocable depuis le Profil.
9. **E9 Habitudes** — objectif d'épargne en pourcentage, réserve de sécurité.
10. **E10 Données** — base réelle ou mode simulation (bandeau permanent).
11. **E11 Prêt** — récapitulatif personnalisé, cauri, entrée dans l'application.

#### Décisions et écarts assumés

1. **Reprise** : `onboarding_step` est écrit à chaque passage ; fermer
   l'application au milieu reprend à la bonne étape.
2. **Animations** : toutes passent par `MediaQuery.disableAnimations`, lui-même
   piloté par le réglage « Réduire les animations » ou par le réglage système.
3. **Masquage** : jauges et soldes du parcours suivent `MaskedAmounts` ; les
   notifications n'ont jamais de montant, même masquage inactif.
4. **Mode simulation** : réglage persistant, bandeau visible sur tous les
   onglets ; la base réelle n'est pas touchée.
5. **Test d'accueil** : le test historique du dashboard a été remplacé par un
   test du premier démarrage (l'application n'ouvre plus le dashboard sans
   onboarding), et non supprimé sans remplacement.

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | OK |
| `flutter analyze` | **No issues found!** (0 problème) |
| `flutter test` | **55 tests, tous passés** (29 → 55) |

Cohérence vérifiée par lecture du code : barre basse pleine largeur (jamais
flottante), cochon latéral avec l'IA juste au-dessus, aucune écriture comptable
sans confirmation, aucun montant dans les messages, `EmptyAkibaStore` en repli
si la base chiffrée ne s'ouvre pas.

#### Ce qui n'est pas fait (volontairement)

- Aucune exécution graphique (`flutter run` impossible ici) : splash, cascade,
  paliers, transitions et les 11 écrans n'ont **pas** été vus.
- Pas de visite guidée en 4 bulles après E11 (ligne 3.7 restante).
- Pas de test d'écran par taille (360 px / 1 280 px) ni de test d'accessibilité.
- Pas de 30 scénarios de recette (ligne 8.5).
### Étape 10 — Revue complète, durcissement release et règles transverses ✅

**Objectif** : relire l'ensemble (code et sécurité), figer les garanties
demandées, préparer les builds release Android et Windows, puis intégrer deux
règles nouvelles — le sens exact « On me doit » / « Je dois » et la liste de
devises avec logos mis en cache — sans casser les étapes suivantes.

#### 1. Revue de code et de sécurité

| Point demandé | Vérification | Résultat |
| --- | --- | --- |
| Analyse statique sans erreurs | `flutter analyze` | **No issues found!** (0) |
| Isolation stricte de l'argent de tiers | Tests de l'Étape 5 + bilan : une entrée neutre n'entre ni dans le solde disponible, ni dans le budget, ni dans les statistiques ; `SnapshotBalance.available = comptes − tiers` | ✅ |
| Masquage jusque dans les notifications | Les quatre banques de messages ne contiennent ni `FCFA` ni `XOF` (test) ; `ReminderPlanner.sanitize` retire tout montant résiduel ; `plan()` applique le masquage | ✅ |
| Logos Flooz / Mixx by Yas / Orabank | `assets/logos/flooz.jpg` (474×474), `mixx.png` (353×319), `orabank.png` (255×79) déclarés dans `pubspec.yaml`, résolus par `AccountBrand.asset` et rendus par `BrandLogo` (tuile blanche, repli icône, `errorBuilder`) | ✅ |
| Barre basse non flottante | `AkibaBottomBar` : `Container` + `Material` pleine largeur, `SafeArea(top: false)`, hauteur fixe, **aucun** `margin`, `borderRadius` ni `floatingActionButtonLocation` | ✅ |
| Cochon latéral + icône IA au-dessus | `AkibaSideActions` : colonne `[IA, espace, cochon]`, cochon = emblème AKIBA dans un cercle, IA juste au-dessus ; la barre basse ne contient ni l'un ni l'autre | ✅ |
| PIN / biométrie | Empreinte salée, PIN triviaux refusés, `FlutterFragmentActivity` pour `local_auth` | ✅ (non testé sur appareil) |

Aucun correctif de sécurité n'a été nécessaire sur ces points ; les seules
modifications sont le durcissement release (§2) et les règles nouvelles (§3, §4).

#### 2. Configuration release

**Android**

| Élément | État |
| --- | --- |
| `applicationId` | `com.akiba.app` (namespace `com.example.akiba` conservé pour ne pas déplacer les sources Kotlin) |
| Libellé | `AKIBA` |
| Permissions | `INTERNET` (logos de devises + sauvegardes serveur), `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `USE_BIOMETRIC`, `USE_FINGERPRINT`. **`READ_SMS` reste volontairement absent** |
| Sauvegarde système | `allowBackup="false"` et `fullBackupContent="false"` : la base chiffrée n'est pas copiée dans un cloud dont la clé ne suivrait pas |
| Notifications planifiées | `isCoreLibraryDesugaringEnabled = true` + `desugar_jdk_libs:2.1.4` (exigé par `flutter_local_notifications`) |
| Biométrie | `MainActivity` étend `FlutterFragmentActivity` |
| Signature | `android/key.properties` optionnel : s'il existe, la build release est signée avec la clé du porteur ; sinon repli debug explicite (à remplacer avant publication) |
| Icône | `mipmap-*/ic_launcher.png` régénérées (48 → 192 px) depuis l'emblème, fond sable de la charte |

**Windows**

| Élément | État |
| --- | --- |
| Icône | `windows/runner/resources/app_icon.ico` régénéré (16, 24, 32, 48, 64, 128, 256) |
| Titre de fenêtre | `AKIBA` (`windows/runner/main.cpp`) |
| Métadonnées | `Runner.rc` : `ProductName`, `FileDescription`, `InternalName`, `CompanyName` = AKIBA |
| Signature | Aucune (certificat à fournir par le porteur) |

Les icônes sont reproductibles : `python tool/generate_icons.py` régénère
`assets/brand/app_icon.png` (1024²), les mipmaps Android et le `.ico` Windows à
partir de `assets/brand/akiba_mark_light.png` (composition sur fond `#FAF4E6`,
emblème à 62 % pour survivre aux masques ronds).

#### 3. Règle nouvelle — sens exact « On me doit » / « Je dois »

- `_DebtDialog` utilise un `SegmentedControl` dont l'index est **exactement**
  `DebtDirection.values[index]` (`owedToMe` / `iOwe`) ; aucune conversion
  implicite, et `DebtDirection.fromStorage` relit la valeur enregistrée.
- Le texte sous le sélecteur explique l'isolation :
  « On vous doit : cette somme n'entre pas dans votre solde disponible tant
  qu'elle n'est pas encaissée. » / « Vous devez : cette somme ne retire rien de
  votre solde disponible ; elle reste suivie séparément. »
- Le règlement affiche « Reste dû : … » **masqué** quand le masquage est actif.
- Le champ montant suit la devise choisie (`Montant en ${AkibaMoney.currency}`).
- Deux tests ajoutés : aller-retour du sens dans la base, et solde disponible
  inchangé en présence d'une créance **et** d'une dette.

#### 4. Règle nouvelle — liste de devises et logos

- `lib/core/format/akiba_currency.dart` : `FCFA (XOF)`, `Euro (EUR)`,
  `Dollar (USD)`, `Yuan (CNY)` avec code ISO, symbole et URL de logo.
- `CurrencyLogoCache` télécharge le logo **une fois** (`https://flagcdn.com`),
  l'écrit dans `<support>/currency_logos/<devise>.png` (écriture atomique,
  plafond 512 Ko, délai 6 s) et le relit ensuite hors ligne.
- `CurrencyLogo` / `CurrencyBadge` : tuile blanche de la charte, repli
  typographique (`FCFA`, `€`, `$`, `¥`) si le réseau ou le fichier manque —
  jamais d'image cassée ni d'erreur visible.
- Sélection dans **Profil → Préférences** et dans **E4** de l'onboarding ;
  `AkibaMoney.currency` (suffixe) suit le réglage, donc tous les écrans déjà
  livrés (accueil, analyses, portefeuille, saisie, dettes, épargne) affichent la
  devise choisie sans modification.
- **Aucun taux de change** : la valeur stockée ne change pas, seul le libellé.
  C'est écrit dans l'UI (« Seul l'affichage change… ») et répété ici.
- Les anciennes valeurs (`FCFA`, `XOF`) restent lisibles : `fromStorage` fait le
  repli sur FCFA.

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | OK |
| `flutter analyze` | **No issues found!** (0 problème) |
| `flutter test` | **61 tests, tous passés** (55 → 61 : 3 devises, 2 créances/dettes, 1 sauvegarde dossier) |
| `python tool/generate_icons.py` | Icônes générées (PNG 1024, 5 mipmaps, ICO 7 tailles) |

#### Ce qui n'est pas fait (volontairement ou faute d'environnement)

- **Aucune build release n'a été produite** : `flutter build apk|windows` exige
  le mode développeur Windows (liens symboliques des greffons), absent du poste.
  La configuration est prête mais non compilée.
- Aucun test sur appareil : permissions Android réelles, notifications,
  biométrie, icône sur le lanceur.
- Le logo de devise dépend d'un CDN public (disponibilité, et l'appel révèle la
  devise choisie) ; hors ligne, le repli typographique s'applique.
- Toujours ouverts : OAuth Drive, STT, lecture SMS, dérivation de la clé depuis
  le PIN, reprogrammation auto des rappels, visite guidée.

### Étape 11 — Module IA (clé, modèles, cascade) et règles des créances et dettes ✅

**Objectif** : formaliser puis appliquer la gestion de la clé API, la liste des
modèles et la bascule automatique, ainsi que les règles complètes du module
Créances et dettes, sans toucher aux étapes suivantes.

Les règles détaillées sont dans `akiba_spec/regles_modules_ia_et_dettes.md`.

#### 1. Clé API : saisie, chiffrement, test, remplacement

| Point | Réalisation |
| --- | --- |
| Saisie | `Profil → Assistant IA → « Clé et modèles »` (`ai_settings_sheet.dart`) ; champ masqué, jamais réaffiché |
| Chiffrement | `AiKeyVault` : AES-256-GCM, nonce aléatoire, format `nonce.mac.chiffré` en base64 ; clé maîtresse 32 octets dans `flutter_secure_storage` (Keystore / DPAPI) |
| Stockage | réglage `ai_api_key_sealed` dans la table `settings` de la base SQLCipher (double couche) |
| Affichage | `••••••••` + date de dernier remplacement, jamais la valeur |
| Test | « Tester » appelle `models.list` ; un échec ne supprime pas la clé |
| Remplacement | le champ vide écrase l'ancienne valeur ; « Effacer » supprime valeur chiffrée + clé maîtresse et coupe le distant |
| Contrôles | vide / < 20 caractères / > 400 / espace → refus explicite ; coffre indisponible → message, aucun repli en clair |
| Sauvegardes | `ai_api_key_sealed` et `ai_api_key_updated_at` exclus de `BackupService` |

#### 2. Liste des modèles, cache et priorité

- `AiModelCatalog.parseList` lit `models.list`, garde les modèles qui savent
  `generateContent`, retire le préfixe `models/` et dédoublonne.
- Cache dans `ai_models_cache` + date ; hors ligne, le cache (ou les quatre
  modèles de départ) reste utilisé : l'assistant ne devient jamais inutilisable.
- Ordre **configurable** : cases à cocher et flèches monter/descendre
  (`ai_model_priority`) ; un identifiant inconnu est ignoré.
- Interrupteur `ai_remote_enabled` : désactivé par défaut, l'assistant reste
  100 % local.

#### 3. Délais, cascade et repli

| Tâche | Délai |
| --- | --- |
| Saisie rapide | 5 s |
| Revue SMS | 6 s |
| Analyse | 10 s |
| Coaching | 12 s |

- `AkibaAiClient` : un essai par modèle, plafond de 3 essais (réglable 1 à 5),
  bascule sur délai dépassé / 429 / 5xx / réseau / réponse illisible, arrêt
  immédiat sur clé refusée (401/403).
- Un modèle qui échoue **deux fois de suite** est mis en veille **10 minutes**,
  puis revient automatiquement.
- Échec total → analyse locale, mention discrète `Analyse locale · <raison>` ;
  succès → `Modèle : <identifiant>`. Aucun code HTTP affiché.
- **Aucune écriture** déclenchée par un appel IA : la carte reste éditable et
  seule « Confirmer » écrit.
- **Mode masqué** : aucun appel distant (la phrase peut contenir un montant) ;
  seule la phrase saisie serait envoyée, jamais les soldes ou transactions.

#### 4. Créances et dettes

- Sélecteur exact « On me doit » / « Je dois » (index = `DebtDirection.values`)
  et texte d'isolation sous le sélecteur.
- **Mouvement de trésorerie** optionnel : prêt accordé → sortie normale ;
  emprunt reçu → entrée **neutre** (exclue du solde disponible, du budget et
  des statistiques) ; crédit ou service → aucune écriture.
- États calculés : **En cours**, **Partiellement remboursé**, **Soldé**,
  **En retard** (échéance comparée au jour, le jour même n'est pas un retard),
  avec pourcentage réglé.
- Règlements partiels ou totaux plafonnés au reste dû.
- **Regroupement par contact** avec total par contact, synthèse globale conservée.
- **Bandeau « Annuler » de 5 s** à l'ajout (supprime la dette et son mouvement)
  et au règlement (restaure l'état précédent) ; `AkibaStore.deleteDebt` ajouté.
- Montants masqués partout, y compris le reste dû ; les rappels d'échéance ne
  contiennent aucun montant.

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | OK |
| `flutter analyze` | **No issues found!** (0) |
| `flutter test` | **73 tests, tous passés** (61 → 73 : 4 clé/modèles, 5 cascade/délais, 3 dettes) |

#### Ce qui n'est pas fait

- Aucun appel réel au fournisseur n'a été exécuté (clé absente du poste) : le
  chiffrement, la cascade et le repli sont couverts par des transports factices,
  pas par un test réseau.
- Aucun test sur appareil du coffre système (Keystore / DPAPI).
- `ai_quota_per_day` n'était pas branché à cette étape (fait à l'Étape 12).
- Pas de rappel dédié par échéance de dette (Phase 7) ; les messages existants
  ne portent jamais de montant.

---

### Étape 12 — Relecture, quota IA daté, photo de profil, Google Drive et Home Lab ✅

**Objectif** : relire d'un œil neuf la clé IA, la cascade et les dettes, en
simplifier le code, brancher `ai_quota_per_day`, puis livrer exactement trois
ajouts — photo de profil locale, « Se connecter avec Google » (sauvegarde Drive
chiffrée), sauvegarde/restauration Home Lab — sans toucher aux autres règles.

Les règles détaillées sont dans
`akiba_spec/regles_profil_ia_et_sauvegardes.md`.

#### 1. Relecture et simplifications

| Code | Simplification |
| --- | --- |
| `lib/core/security/aes_box.dart` (nouveau) | `AesBox` + `SecureMasterKey` : une seule implémentation AES-256-GCM et une seule gestion de clé maîtresse, partagées par la clé API et la photo |
| `ai_key_vault.dart` | ne réimplémente plus le déchiffrement ni l'hexadécimal ; mêmes API et mêmes messages d'erreur |
| `ai_model_catalog.dart` | suppression de `priority`, `defaultPriority`, `encodePriority` et `move` (aucun appel en production) ; `selected` reste la seule règle d'ordre |
| `ai_client.dart` | suppression de `AiFailureKind.noKey` (redondant) et du getter `sleeping` (non utilisé) |
| Dettes | relues : aucun doublon à supprimer sans changer le comportement ; les états, le regroupement et l'annulation restent inchangés |

#### 2. Quota IA journalier

- `lib/core/ai/ai_quota.dart` : compteur `ai_quota_date` + `ai_quota_used`,
  plafond `ai_quota_per_day` (0 à 200, 20 par défaut).
- Une analyse distante = **une** unité, cascade comprise ; un échec compte.
- Remise à zéro implicite au changement de jour civil, sans tâche de fond.
- Quota atteint → `Analyse locale · quota du jour atteint`, aucune erreur.
- Réglage et compteur affichés dans « Clé et modèles » (− / +).

#### 3. Photo de profil locale

| Élément | Réalisation |
| --- | --- |
| Stockage | `ProfilePhotoStore` : image en base64, chiffrée AES-256-GCM, fichier `profile/avatar.sealed`, clé maîtresse `akiba_profile_photo_key` |
| Import | `image_picker` (sélecteur système), réduction 1 024 px, qualité 88, refus au-delà de 4 Mo |
| Partage d'état | `ProfilePhotoController` + `ProfilePhotoScope`, chargé avant la première image |
| En-tête | avatar 46 px à gauche du titre de l'accueil |
| Profil | avatar 62 px, « Ajouter / Changer la photo », « Retirer » |
| Verrouillage | avatar 84 px + « Bonjour <prénom> » quand le PIN est actif |
| Défaut | initiale du prénom sur tuile terre cuite, silhouette sinon |
| Sauvegarde | photo et date exclues des enveloppes |

#### 4. Google Drive

- `lib/core/config/google_oauth_config.dart` : **seul** fichier à remplir
  (`clientIdPlaceholder`, secret facultatif, ou `--dart-define`).
- `lib/core/backup/google_drive_backup.dart` : flux code + PKCE S256, redirection
  boucle locale sur port éphémère, délai 3 min, annulation gérée.
- Portée `drive.appdata` uniquement ; enveloppe **déjà chiffrée** déposée telle
  quelle, cinq sauvegardes conservées, restauration additive et confirmée.
- Jeton d'accès en mémoire, jeton de rafraîchissement dans le coffre système,
  déconnexion et révocation (`invalid_grant`) gérées.
- Sans identifiants ou sans réseau : repli sur le dossier Drive synchronisé,
  application pleinement utilisable.

#### 5. Home Lab

- Onglet dédié du centre de sauvegarde : URL complète + jeton masqué.
- Jeton en `Authorization: Bearer`, jamais dans l'URL ; `PUT`/`GET` de
  l'enveloppe chiffrée, `X-Akiba-Backup: AES-256-GCM`.
- « Vérifier » teste la connexion et lit les métadonnées sans rien écrire ni
  demander la phrase secrète.
- Messages distincts : serveur injoignable, jeton refusé, format illisible,
  délai dépassé ; rappel que Android refuse le HTTP en clair.

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | OK |
| `flutter analyze` | **No issues found!** (0) |
| `flutter test` | **76 tests, tous passés** (73 → 76 : quota journalier, aller-retour Home Lab sur un serveur HTTP local) |
| `flutter pub add image_picker url_launcher` | dépendances ajoutées ; compilation native toujours bloquée par l'absence du mode développeur Windows |

#### Ce qui n'est pas fait / non vérifié

- Aucune connexion Google réelle, aucun envoi Drive, aucun serveur Home Lab
  joint : le code réseau n'a pas été exercé.
- Photo non importée ni affichée sur appareil : aucune vérification visuelle de
  l'en-tête, du Profil ni de l'écran de verrouillage.
- Le sélecteur d'images et l'ouverture du navigateur (`image_picker`,
  `url_launcher`) ne sont pas compilés faute de mode développeur Windows.
- Veille des modèles toujours en mémoire ; quota local en place, plafond
  fournisseur inchangé.

---

### Étape 13 — Identifiant OAuth Google branché, cinq thèmes persistants, exécution sur appareil ✅

**Objectif** : brancher l'identifiant OAuth fourni par le porteur sans exposer
le moindre secret dans le code suivi, puis livrer les cinq thèmes persistants
demandés et lancer l'application sur le téléphone connecté en ADB sans fil.

#### 1. Identifiant OAuth Google

| Élément | État |
| --- | --- |
| Fichier fourni | `android/app/client_secret_954317884015-201kborqhiii7lpca93i1gfctll30s3d.apps.googleusercontent.com.json`, type **`installed`** (application de bureau), **sans `client_secret`** |
| Identifiant exploité | `954317884015-201kborqhiii7lpca93i1gfctll30s3d.apps.googleusercontent.com`, lu dans le JSON puis recopié **uniquement** dans `secrets/google_oauth.json` |
| Transmission au build | `flutter run --dart-define-from-file=secrets/google_oauth.json` → `String.fromEnvironment('AKIBA_GOOGLE_CLIENT_ID')` |
| Code suivi | Aucune constante d'identifiant : `GoogleOAuthConfig.clientIdPlaceholder` reste vide, le commentaire d'en-tête documente la commande |
| `.gitignore` | `/secrets/`, `client_secret_*.json`, `**/client_secret_*.json` ajoutés |
| Sauvegarde Drive | Enveloppe **AES-256-GCM** (PBKDF2-HMAC-SHA256 120 000 tours, sel 128 bits), portée `drive.appdata`, cinq dernières versions conservées : inchangé, désormais réellement configurable |
| Repli | Sans fichier de définitions : `isConfigured` faux, application 100 % hors ligne, dossier Drive synchronisé proposé |

Le flux PKCE S256, la boucle locale `127.0.0.1` et le coffre du jeton de
rafraîchissement ne changent pas : seul l'identifiant manquait.

#### 2. Cinq thèmes persistants

| Fichier | Rôle |
| --- | --- |
| `lib/core/theme/akiba_colors.dart` | `blanc`, `sombre` (conservé), `bleu`, `vert`, `or` complets (fond, surfaces, tuiles, action, accent, sable, textes, sémantique, `isDark`) |
| `lib/core/theme/akiba_theme.dart` | Énumération `AkibaThemeId` (stockage, libellé, palette, luminosité) + `AkibaTheme.forId(...)` ; un seul constructeur de `ThemeData` |
| `lib/core/state/akiba_settings.dart` | Réglage `akiba_theme` (`blanc` par défaut), `themeId`, `setThemeId`, `nextThemeId` ; `theme_mode` retiré |
| `lib/core/widgets/theme_swatch.dart` | Pastille d'aperçu (fond + couleur d'action + coche), sémantique et état sélectionné |
| `lib/features/profile/profile_screen.dart` | Tuile Apparence : les cinq pastilles, aperçu immédiat, texte sur le contraste et les invariants |
| `lib/features/dashboard/dashboard_screen.dart` | Bouton d'apparence : cycle Blanc → Sombre → Bleu → Vert → Or → Blanc, icône palette |
| `lib/main.dart` | `theme: AkibaTheme.forId(_settings.themeId)` ; `darkTheme`/`themeMode` supprimés pour qu'aucun mode système n'écrase le choix |
| `test/theme_test.dart` | 3 tests : cinq thèmes et repli sûr, contraste de chaque palette, persistance du choix après rechargement |

Invariants tenus dans les cinq thèmes : **barre basse pleine largeur non
flottante** (`AkibaBottomBar`, aucun `margin` ni `borderRadius`), **cochon
latéral avec l'icône IA juste au-dessus** (`AkibaSideActions`), logos officiels
dans leur tuile blanche.

#### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 76 fichiers, 0 erreur |
| `flutter analyze` | **No issues found!** (0) |
| `flutter test` | **79 tests, tous passés** (76 → 79) |
| `adb devices -l` | `192.168.1.80:38353  device  model:SM_G781V` (ADB sans fil) |
| `flutter run -d 192.168.1.80:38353 --dart-define-from-file=secrets/google_oauth.json` | **APK construit**, installé et **application lancée** sur le SM-G781V (VM service attaché, hot reload actif) |
| `flutter pub get` | `flutter_local_notifications` ramené de 23.0.3 à **22.3.3** (voir ci-dessous) |

**Ajustement de dépendance.** Le premier `flutter run` a échoué :
`flutter_local_notifications` 23.0.3 compile contre **Android SDK 37**, absent
des plateformes stables installées (`android-37.0` n'est pas reconnu sous le
hash `android-37`). La contrainte est fixée à `^22.3.3`, qui utilise la même
API Dart (paramètres nommés) et compile contre SDK 36. Aucun code applicatif
n'a changé pour cela.

#### Ce qui n'est pas fait / non vérifié

- Aucune connexion Google réelle : le consentement dans le navigateur du
téléphone et le dépôt Drive restent à exercer par la personne.
- Aucune capture d'écran : le rendu des cinq thèmes sur l'appareil n'a pas été
contrôlé visuellement par mes soins.
- `flutter build apk --release` toujours non exécuté.

