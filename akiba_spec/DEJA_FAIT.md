# DEJA_FAIT — Journal AKIBA

Dernière mise à jour : **25/11/2026** · Étapes **1.1 → 1.3** de la Phase 1, puis
**Étapes 4 → 11** (saisie rapide, portefeuille, analyses, profil, assistant IA /
SMS / sauvegardes, onboarding E1→E11, animations, revue complète et
configuration release, gestion de la clé IA et cascade de modèles, règles
complètes des créances et dettes) terminées. Les **Étapes 12 → 32** sont
également livrées et documentées : profil, IA multi-fournisseurs, rapports PDF,
sauvegardes Google / Home Lab, notifications complètes, cauris, onboarding
Google, son de cauri, assistant qui discute et exécute, zoom PDF.

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

### Étape 14 — Revue et correctifs ciblés (20/11/2026)

- Avatar : `avatar_default.jpg` correspond à `akiba_spec/argent.jpg`; recadrage avec déplacement/zoom avant validation et aperçu au toucher.
- Marque et thèmes : icône générée sur blanc pur avec empreinte augmentée à 90 %; splash blanc avec cauri animé; logos locaux haute qualité, Flooz/Mixx agrandis et Orabank élargi; champs liés au texte primaire des cinq thèmes.
- Onboarding : choix thème/langue en première page, langue persistée au choix; Google avant les comptes, détection Drive si compte lié; permissions OS à activation. OAuth PKCE complété par vérification `state`. Le refus Google Cloud `access_denied` reste externe au code.
- Analyses : « Tout » évite le chargement inutile des mouvements; dashboard, portefeuille et analyses rechargent lors du changement de magasin réel/simulation.
- Sauvegarde : AES-256-GCM sans phrase secrète, étapes animées, Google Drive/Home Lab seulement. Les clés maître historiques restent exclues des exports.
- Voix/simulation/rappels : dictée `onDevice`, parsing local des créances/dettes, icônes par libellé, célébration après épargne vocale; simulation mémoire isolée FCFA avec revenu Vente corrigé positif; Workmanager repas et dépenses toutes les 30 minutes, sans montant.
- Performance : préchauffage des images de marque/avatar et réduction du chargement dans « Tout ».

`dart format` terminé; `flutter analyze` : **No issues found**; `flutter test --reporter compact` : **81 tests passés** (dont le test de construction OAuth). OAuth réel, permissions natives et rendu sur appareil restent à vérifier.

### Correctif OAuth Android — requête installée minimale

La requête Google utilise maintenant `http://127.0.0.1:<port>` à la racine (sans `/oauth2callback`), les scopes nécessaires dont `drive.appdata`, `response_type=code`, PKCE S256 et `state`. `include_granted_scopes`, `access_type` et `prompt` ont été retirés : l’autorisation incrémentale n’est pas prise en charge dans le flux des apps installées et les clients installés renvoient un jeton durable sans `access_type=offline`. Test unitaire ajouté sur l’URL et ses paramètres.

### Ajustements UI — bouton Google et splash

Le bouton « Se connecter avec Google » reste visible dans le centre de sauvegarde et l’onboarding même sans identifiants OAuth; le message de configuration et le repli Drive synchronisé / hors ligne sont conservés. Le splash natif Android et Flutter est blanc; l’animation du cauri et l’accent terre cuite sont conservés.

---

## Étape 15 — Vitesse, animations, PIN, assistant vocal et sauvegardes (22/11/2026)

### 1. Démarrage plus rapide et animation cochon + cauri (3 s)

| Fichier | Rôle |
| --- | --- |
| `lib/core/widgets/cauri_drop.dart` | `CauriDropAnimation` : tirelire **sans cauri** + cauri officiel qui tombe dans la fente, **3 s**, halo et étincelles à l'impact, image finale si les animations sont réduites |
| `tool/prepare_visual_assets.py` | Détoure le cauri de `akiba_spec/cauris.png` (`assets/brand/cauri.png`, 249×360) et la tirelire seule de l'emblème (`assets/brand/cochon.png`, 377×253), fonds transparents |
| `lib/features/splash/splash_screen.dart` | Splash unique : `CauriDropAnimation` 3 s ; `SplashGate` passe à 3 s |
| `lib/core/widgets/savings_celebration.dart` | Versement d'épargne : **exactement** la même animation, 3 s |
| `lib/main.dart` | Première image immédiate : intégrité, photo chiffrée, Workmanager et préchauffage des logos passent **après** `runApp` |

1. Le démarrage ne bloque plus sur l'initialisation : `runApp` est appelé dès l'ouverture de la base et la lecture des réglages. Les anciens `await` (rappels Workmanager, photo AES par coffre système) sont hors du chemin critique ; le splash de 3 s couvre leur chargement.
2. Un seul widget d'animation : le geste du démarrage et celui du versement d'épargne sont identiques (cohérence demandée).
3. Les deux images sont transparentes : lisibles sur le splash blanc comme sur la surface crème de la célébration.

### 2. Transition fin d'onboarding → Dashboard

- Sur E11, le logo passe de 1× à **12×** en 800 ms (`easeInCubic`) et son opacité tombe à **0** : il couvre l'écran puis s'effond ; la coquille arrive ensuite par l'`AnimatedSwitcher` de 450 ms déjà en place.
- « Réduire les animations » supprime la temporisation avant la bascule.

### 3. Module PIN réellement activé

Trois causes réelles identifiées et corrigées :

1. **Magasin incohérent** : `PinVault` écrivait dans le magasin actif (parfois la simulation) alors que `AkibaSettings.load()` relisait la **base réelle** ; `pinEnabled` restait donc faux. `AkibaSettings.store` expose désormais le magasin des réglages, et le Profil comme l'onboarding y écrivent.
2. **Onboarding** : après `setPin`, les réglages n'étaient pas relus ; un PIN saisi pendant le parcours d'accueil n'activait jamais le verrou.
3. **`LockGate`** : `_locked` n'était calculé qu'à `initState`. Il suit maintenant `didUpdateWidget` (PIN activé → verrou immédiat, PIN retiré → accès direct) et verrouille aussi sur `hidden` (Android moderne) en plus de `paused`.

La biométrie reste **optionnelle** : si elle échoue ou si aucun capteur n'existe, le champ PIN et le bouton « Utiliser la biométrie » restent affichés — le PIN fait toujours foi.

### 4. Assistant IA : vocal direct et créances / dettes

- Après la dictée, le **résultat final** déclenche `_analyse()` automatiquement (`unawaited`) : plus de bouton « Analyser » à cliquer.
- `AiCommandParser` reconnaît désormais :
  - « Koffi me doit 5 000 », « on me doit 12 000 », « il me doit 3 000 » → **créance** (`owedToMe`), contact extrait ;
  - « je dois 5 000 à Ama », « je dois rembourser… », « j'ai emprunté… » → **dette** (`iOwe`), contact après « à » ;
  - si les deux formes coexistent, la **première citée** gagne.
- Ces phrases ne sont **plus neutres** ni classées en sortie : la carte affiche « Créance · on me doit » ou « Dette · je dois », et « Confirmer » écrit une ligne `debts` **sans mouvement de trésorerie** — donc hors solde disponible, hors budget et hors statistiques (règle AKIBA).
- L'analyse distante est court-circuitée pour ces phrases : leur sens est local et ne peut pas être contredit par un modèle.

### 5. Google et Home Lab

- **Google** : identifiant nettoyé (espaces/sauts de ligne), URI construite avec `Uri.https` (encodage déterministe), réintroduction de `access_type=offline` + `prompt=consent` pour garantir le **jeton de rafraîchissement** (sans eux, une deuxième connexion n'en renvoie aucun et la sauvegarde échoue juste après une connexion réussie) ; messages dédiés pour `invalid_request`, `unauthorized_client`, `invalid_scope`, `disallowed_useragent`, et message de délai qui nomme le « 400 invalid_request ». Toute erreur affiche le **repli dossier Drive synchronisé** sans bloquer l'application.
- **Home Lab** : nouveau `BackupService.probeRemote` et bouton « Tester la connexion » (actif dès qu'une URL est saisie) : GET en lecture seule, jeton en en-tête Bearer. Réponses distinctes : joignable + jeton accepté (200/204), joignable sans sauvegarde (404), jeton refusé (401/403), autre code HTTP, certificat refusé, serveur injoignable, délai dépassé.

### 6. Portefeuille > Épargne et Analyses > Budget

- `_SavingsCard` : montants dans un `FittedBox`, actions en `Wrap` (fin du `Spacer` + date sur la même ligne), pastilles raccourcies (`Urgence`, `Objectif`, `Libre`).
- Correctifs de robustesse induits par les tests 320 px : `AccountBadge` et `_AccountRow` réduisent leurs montants, légende de l'histogramme en `Wrap`, en-tête de `_BudgetCard` en colonne nom + pastille avec un menu unique (Modifier / Supprimer).
- `LabelIcons.forCategory` : une icône dédiée par catégorie (alimentation, transport, logement, santé, école, loisirs, épargne, factures/services, tontine, salaire, vente, don, autre), insensible aux accents, utilisée dans les plafonds **et** la ventilation.

### Vérifications réellement exécutées (22/11/2026)

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 85 fichiers, 0 changement |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **94 tests, tous passés** (dont 14 nouveaux : 5 analyse vocale créances/dettes, 3 PIN, 3 `LockGate`, 2 robustesse 320 px ; 1 test OAuth mis à jour) |

### Ce qui n'est **pas** fait / non vérifié

- Aucune exécution graphique : le splash de 3 s, le zoom de fin d'onboarding et la célébration d'épargne n'ont pas été vus à l'écran.
- Connexion Google réelle non exercée (identifiants du porteur absents) ; le correctif `invalid_request` repose sur la revue de la requête, pas sur un essai réseau.
- Serveur Home Lab réel non joint : le bouton de test est vérifié par le code et l'analyse statique seulement.
- La dictée dépend du moteur de reconnaissance **hors ligne** du téléphone.

## Étape 16 — Visuels, ouverture, verrou et IA multi-fournisseurs (22/11/2026)

### 1. Visuels réparés

| Constat | Correction |
| --- | --- |
| `assets/brand/cochon.png` était coupé : la découpe à la ligne 148 de l'emblème tranchait le dos de la tirelire au niveau de la fente | Le cochon vient désormais de `akiba_spec/Logo/preview.png` (tirelire seule, entière, fente comprise), détourée et recadrée : **389×260** |
| Le retrait du fond se faisait « à la couleur » : tout blanc devenait transparent, y compris l'œil du cochon et les stries internes du cauri | `tool/prepare_visual_assets.py` fait une **diffusion depuis les bords** : seul le blanc relié au bord disparaît, les blancs internes restent blancs. Cauri **252×360** |
| Le cauri paraissait lourd sur son fond | Même détourage propre ; le cauri reste noir et lisible sur blanc (ouverture) comme sur crème (versement) |

Les deux PNG ont été **ouverts et regardés** après régénération : cochon complet (oreille, dos, fente, œil), cauri entier avec ses stries.

### 2. Ouverture raccourcie : l'animation seule

- `SplashScreen` ne montre plus que `CauriDropAnimation` : plus de titre « AKIBA », plus de phrase d'accroche, plus de barre de progression.
- `AkibaDurations.splash` passe de **3 s à 1 s** (animation + accès à l'app) ; `SplashGate` suit la même constante. Le versement d'épargne garde ses **3 s** (`AkibaDurations.cauriDrop`).
- Taille adaptative : `0,52 × plus petit côté`, bornée entre 120 et 200 px, pour ne jamais déborder sur 320 px.
- L'accès au verrou PIN n'est plus retardé de 3 s.

### 3. Écran rouge à la première saisie du code PIN

L'assertion Flutter (`InheritedElement.notifyClients` : « check that it really is our descendant ») venait du croisement de deux sous-arbres qui gardaient chacun leur champ de saisie et leur focus :

1. l'`AnimatedSwitcher` de la racine faisait coexister `OnboardingFlow` et `LockGate` pendant 450 ms ;
2. l'`AnimatedSwitcher` du parcours faisait coexister l'étape PIN et l'étape suivante pendant 250 ms.

Les deux croisements sont supprimés : la racine bascule directement (le zoom du logo assure la transition) et le corps d'étape est rendu d'un bloc. Plus de sous-arbre de focus fantôme pendant une notification d'héritage.

### 4. Assistant IA : Gemini, DeepSeek, OpenRouter et Home Lab / Ollama

| Élément | Rôle |
| --- | --- |
| `lib/core/ai/ai_provider.dart` | `AiProvider` (identifiant, libellé, adresse et modèle par défaut, clé requise ou non) + `AiProviderSettings` (une URL et un modèle **par fournisseur**, normalisation `http(s)://`, repli sur le défaut) |
| `lib/core/ai/ai_key_vault.dart` | Coffre **par fournisseur** : `ai_api_key_sealed` pour Gemini (nom historique conservé), `ai_api_key_sealed_<id>` pour les autres ; toujours AES-256-GCM avec clé maîtresse du coffre système |
| `lib/core/ai/ai_client.dart` | `buildAiProviderCall` (pure) : Gemini natif `:generateContent`, ou `/chat/completions` avec `Authorization: Bearer` **seulement si un jeton existe** ; `extractAiText` lit les deux formats ; `OpenAiCompatibleTransport` ; `fetchAiModels` par fournisseur (Gemini `{models}`, OpenAI `{data}`) |
| `lib/core/ai/ai_remote.dart` | `resolveAiRemote` : masquage → aucun appel, appels coupés → aucun, adresse invalide ou clé absente (hors Home Lab) → aucun ; sinon configuration prête |
| `lib/features/assistant/ai_settings_sheet.dart` | Choix explicite du fournisseur, adresse, modèle, clé (facultative pour Ollama), test de connexion, quota et plafond d'essais ; la liste de modèles et la priorité restent propres à Gemini |
| `lib/features/assistant/assistant_sheet.dart` | Utilise la configuration résolue ; l'indication devient « DeepSeek · deepseek-chat », etc. ; repli local inchangé et silencieux |

Invariants tenus : aucune écriture en base sans confirmation, quota journalier conservé (une unité par analyse, quel que soit le nombre de modèles), **aucun appel réseau quand le masquage est actif**, créances/dettes toujours traitées localement, montants masqués, chiffrement et thèmes inchangés, barre basse non flottante.

### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 88 fichiers, 0 changement après formatage |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **105 tests, tous passés** (11 nouveaux : 5 routage fournisseurs/requêtes/réponses, 5 masquage-adresse-clés, 1 ouverture 320 px) |

### Ce qui n'est pas vérifié

- Aucun appel réel vers DeepSeek, OpenRouter ou une instance Ollama : le poste n'a ni clé ni serveur. Le routage, les en-têtes, les corps de requête et la lecture des deux formats sont testés hors réseau.
- L'ouverture a été contrôlée par test widget en 320×640 (aucune exception de débordement) et les PNG ont été regardés, mais l'animation n'a pas été vue sur un téléphone.
- Aucune recette graphique de l'écran de réglages IA sur appareil.
## Étape 17 — Saisie vocale, PIN et épargne (23/11/2026)

### 1. Saisie vocale : créances et dettes

| Constat | Correction |
| --- | --- |
| La dictée française rend souvent les nombres **en lettres** (« trois mille francs ») : `_extractAmount` ne lisait que les chiffres et répondait « je n'ai pas trouvé de montant » | `AiCommandParser` lit désormais les nombres écrits : unités, dizaines, `cent`, `mille`, `million`, pluriels, et le cas `quatre-vingt` (80 et non 24). Garde-fou : le résultat n'est retenu que si la phrase contient un multiplicateur, donc « un café » ne devient jamais 1 FCFA |
| `_save` exigeait un compte **avant** de traiter une créance ou une dette | Le sens créance/dette est traité en premier : aucune configuration de tiers ni de compte n'est nécessaire |
| « On me doit 12 000 » enregistrait toute la phrase comme nom de contact | Le champ devient le contact extrait ; à défaut, le texte saisi est nettoyé (chiffres retirés) et une phrase entière retombe sur « Contact », modifiable |

Le sens reste strictement local, quel que soit le fournisseur IA configuré :
« [Personne] me doit [montant] » produit une créance **On me doit**, « Je dois
[montant] à [Personne] » une dette **Je dois**, sans sortie d'argent, sans ligne
neutre et hors solde disponible. L'analyse part automatiquement à la fin de la
dictée (aucun bouton « Analyser »).

### 2. Limitation des essais de PIN (Étape 2.2)

| Fichier | Rôle |
| --- | --- |
| `lib/core/security/pin_attempts.dart` | `PinAttempts` : compteur et échéance dans la table `settings` (base chiffrée), 3 essais libres puis 30 s / 1 min / 2 min / 5 min, `delayFor`, `remainingSeconds`, `registerFailure`, `reset` |
| `lib/features/splash/splash_screen.dart` | `LockGate` applique le délai : champ et bouton désactivés, compte à rebours à la seconde, message neutre « Trop de tentatives. Nouvel essai dans N s. » (aucun nombre d'essais restants), délai relu au redémarrage |
| `lib/core/state/akiba_settings.dart` | Clés `pin_failures` et `pin_locked_until` dans les valeurs par défaut |

Aucune donnée n'est effacée et le PIN reste le seul secret vérifié (empreinte
salée) : la limitation ne fait que ralentir les essais.

### 3. Épargne : proposition de versement et date d'atteinte

| Fichier | Rôle |
| --- | --- |
| `lib/core/savings/savings_projection.dart` | `suggestedDeposit` (part 0→30 % du solde, bornée) et `estimateTargetDate` (rythme observé depuis la création du coffre) |
| `lib/features/portfolio/portfolio_screen.dart` | Carte « Proposition de versement » avec `SegmentedControl` 0/10/20/30 % (réglage `savings_goal_percent`) ; bouton « Proposer X % · montant » dans le dialogue, recalculé sur le compte choisi ; « À ce rythme : jj/mm/aaaa » sur un objectif sans date cible |

Aucun versement automatique : la proposition est un montant pré-rempli, relu et
modifiable.

### 4. Rappels : reprogrammation au démarrage

`lib/core/notifications/reminder_scheduler.dart` recompose les rappels des sept
prochains jours à partir des réglages, sans redemander l'autorisation
(`permission_notifications`, désormais écrit par le Profil) et sans planifier sur
Windows. `main` l'appelle hors du chemin critique. Aucun message ne contient de
montant (`sanitize`, `masked: true`).

### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 93 fichiers, 0 changement après formatage |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **119 tests, tous passés** (dont 13 nouveaux dans `test/pin_savings_test.dart`) |

Nouveaux tests : « Guy me doit 3000 fr » → créance `owedToMe` 3 000, contact
« Guy », jamais une sortie ; « Je dois 3000 fr à Guy » → dette `iOwe` ; dictée en
lettres (3 000, 12 500, 80 000) ; « un café » sans montant ; délais progressifs
et persistance du compteur PIN ; proposition bornée 0→30 % ; date d'atteinte.

### Ce qui n'est pas vérifié

- Aucun essai sur téléphone : la dictée dépend du moteur hors ligne de l'appareil
  et le compte à rebours du PIN n'a pas été vu à l'écran.
- Aucun build natif (AGP 9 préexistant) : les ressources et le code sont validés
  par l'analyseur et les tests seulement.
---

## Étape 18 — Rappels fiables, échéances de dettes, détail des mouvements (23/11/2026)

### 1. Reprogrammation des rappels fiabilisée

| Constat | Correction |
| --- | --- |
| `requestPermission` et `cancelAll` pouvaient être appelés **avant** `initialize` : la demande système échoue ou l'annulation ne fait rien, laissant d'anciens rappels programmés | `LocalNotifications.requestPermission` et `cancelAll` appellent désormais `ensureReady()` avant toute action sur le greffon |
| `ReminderScheduler` planifiait sans garantir l'initialisation | `ensureReady(timezone: settings.timezone)` est appelé **avant** `schedule` et avant la demande d'autorisation |
| Deux appels dans le même lancement (`main` + `ReminderScheduler`) inscrivaient deux fois la tâche Workmanager (annulation puis réinscription) | `main` ne passe plus que par `ReminderScheduler.reprogram(settings, store: store)` ; `BackgroundReminders` mémorise l'empreinte des réglages déjà inscrits et ne réinscrit que si elle change |
| Le Profil dupliquait la logique de planification | `ProfileScreen._reschedule` appelle `ReminderScheduler.reprogram(..., requestPermission: true)` ; `_reminderConfig` est supprimé |

### 2. Rappel d'échéance de créance et de dette (Étape 5.6)

| Élément | Détail |
| --- | --- |
| `ReminderPlanner.planDebts` | Un rappel par créance/dette **non soldée** à 9 h le jour de l'échéance, dans un horizon de 30 jours ; échéances passées, soldées ou trop lointaines ignorées |
| Message | Titre « AKIBA · Créance à échéance » / « AKIBA · Dette à échéance », corps neutre sans montant ni nom de contact, `sanitize` appliqué d'office |
| Réglage | `notif_debt` (activé par défaut) ; sans lui, aucun rappel de dette n'est planifié |
| Câblage | `ReminderScheduler` charge les dettes du magasin réel et fusionne les rappels par ordre chronologique |

### 3. Détail et reclassement d'un mouvement (Étape 6.2)

| Fichier | Rôle |
| --- | --- |
| `lib/data/transaction_reclassifier.dart` | `canReclassify` (seules les entrées/sorties réelles), `categoriesFor` (dépenses ou revenus), `withCategory` (copie qui ne change **que** la catégorie, identifiant conservé) |
| `lib/features/portfolio/movement_detail_sheet.dart` | Fiche de détail : montant (masqué si besoin), type, compte, date, catégorie, note, nature « argent de tiers », appartenance au budget ; puces de reclassement, « Aucune », explication pour les lignes hors budget ; bouton « Modifier » vers la saisie complète |
| `lib/features/portfolio/portfolio_screen.dart` | Un appui sur un mouvement ouvre la fiche (au lieu de la saisie directe) ; le reclassement recharge les écrans via `AkibaDataRevision` |

Invariants tenus : aucun montant modifié (écriture remplacée, pas dupliquée), argent de tiers / transferts / épargne / soldes d'ouverture non reclassables et expliqués, masquage respecté, aucune écriture sans action explicite.

### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 96 fichiers, 0 changement après formatage |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **125 tests, tous passés** (6 nouveaux : 2 sur les échéances, 3 sur le reclassement, 1 widget sur la fiche) |

### Ce qui n'est pas vérifié

- Aucune notification réellement livrée : le greffon n'est pas initialisé hors appareil.
- La fiche n'a pas été vue à l'écran (test widget seulement, 360 px implicite).
- Aucun build natif (configuration AGP 9 préexistante).

---

## Étape 19 — Configuration Google OAuth chargée automatiquement (23/11/2026)

### 1. Le problème réel

`--dart-define-from-file=secrets/google_oauth.json` n'a pas d'équivalent « par
défaut » dans Flutter : chaque `flutter run`, chaque `flutter build` et chaque
lancement depuis un IDE devait le répéter. Oublié, l'application démarrait avec
un `clientId` vide, donc sans connexion Google — et un `client_id=` vide dans la
requête d'autorisation est une cause directe de « 400 invalid_request ».

### 2. Mécanisme livré

| Fichier | Rôle |
| --- | --- |
| `tool/sync_oauth_secrets.dart` | Copie `secrets/google_oauth.json` (jamais versionné) vers `assets/config/google_oauth.json` ; refuse un identifiant vide ou qui ne finit pas par `.apps.googleusercontent.com` (et supprime alors la copie), n'affiche jamais l'identifiant en entier, ne réécrit rien si la cible est déjà à jour |
| `assets/config/` | Dossier suivi grâce à `.gitkeep`, fichier ignoré : la copie est **embarquée au build**, donc disponible sur Android et iOS où `secrets/` n'existe pas |
| `lib/core/config/google_oauth_config.dart` | `load()` idempotent et jamais bloquant : `--dart-define`, puis `secrets/google_oauth.json` (développement sur ordinateur, dossier courant), puis la copie embarquée ; identifiant toujours nettoyé (`trim`) |
| `lib/main.dart` | `await GoogleOAuthConfig.load()` après `ensureInitialized()`, avant la base et l'interface |
| `lib/core/backup/google_drive_backup.dart` | `signIn()` recharge la configuration si nécessaire : un écran monté seul ne dépend plus de l'ordre de démarrage |
| `pubspec.yaml`, `.gitignore` | `assets/config/` déclaré dans les assets ; `/assets/config/google_oauth.json` ignoré par Git |

Un simple `flutter run` (Android, Windows, iOS) charge donc la configuration.
`--dart-define` reste prioritaire pour un essai ponctuel ou une CI. Après
rotation de l'identifiant, une seule commande rafraîchit la copie :
`dart run tool/sync_oauth_secrets.dart`. Sans fichier source, le script supprime
la copie embarquée : jamais d'identifiant périmé livré par erreur.

### 3. Relecture des deux fichiers OAuth (cause du « 400 invalid_request »)

| Point | Constat | Correction |
| --- | --- | --- |
| Encodage du `scope` | `Uri.https(..., queryParameters:)` encode l'espace en `+`, forme ambiguë pour Google | Chaîne de requête construite avec `Uri.encodeComponent` : espaces en `%20`, la forme documentée |
| `client_id` vide | Il était émis tel quel (`client_id=`) quand aucun identifiant n'était chargé → `invalid_request` « Missing required parameter » | Les valeurs vides ne sont plus émises ; `signIn()` refuse proprement avant d'ouvrir le navigateur, avec la marche à suivre |
| Paramètres | `access_type=offline` + `prompt=consent` conservés (sans eux, aucun jeton de rafraîchissement) ; `include_granted_scopes` toujours absent | Inchangé |
| `redirect_uri` | `http://127.0.0.1:<port>`, sans chemin : forme documentée pour les applications installées, réutilisée à l'identique pour l'échange du code | Inchangé, désormais testé valeur par valeur |
| Android | Google **déprécie la redirection de boucle locale pour les applications mobiles** (clients Android/iOS) ; AKIBA utilise un client « Application de bureau », la seule forme qui la conserve. Le message d'erreur nomme maintenant cette cause | `_explain('invalid_request')` réécrit |
| Ouverture du navigateur | `url_launcher` exige `<queries><intent VIEW/></queries>` sur Android 11+ ; sans elle la page d'autorisation ne s'ouvre jamais | Déclaration ajoutée au manifeste |
| Repli conservé | Sans identifiant, la connexion est refusée avec un message explicite ; le dossier Drive synchronisé et le mode hors ligne restent le chemin normal | Inchangé, textes mis à jour (`GoogleOAuthConfig.setupHint`) |

Aucun secret n'entre dans le code suivi : l'identifiant ne vit que dans
`secrets/` et dans la copie `assets/`, toutes deux ignorées par Git. La copie est
en revanche embarquée dans l'APK — normal pour un identifiant OAuth, mais elle ne
doit jamais contenir un vrai secret (le client AKIBA n'en a pas ; le script le
rappelle à chaque exécution).

### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart run tool/sync_oauth_secrets.dart` | Copie écrite (`9543178840…rcontent.com`), code retour 0, fichier confirmé ignoré par `git check-ignore` |
| `dart format lib test tool` | 97 fichiers, 3 reformatés, relance sans changement |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **128 tests, tous passés** (3 nouveaux : `%20` et aucun `+`, redirection exacte, chargement puis nettoyage des identifiants, y compris fichier absent) |

### Ce qui n'est pas vérifié

- Aucune connexion Google réelle : ni le consentement, ni le retour du
  navigateur, ni l'échange du code n'ont été exercés depuis un téléphone.
- Rien dans le code ne peut garantir le comportement de Google vis-à-vis de la
  boucle locale depuis Android : la dépréciation est côté Google, d'où le repli.
- Aucun build natif (configuration AGP 9 préexistante) : la copie embarquée est
  prouvée par les tests (asset déclaré et lisible) mais pas par un APK installé.

---

## Étape 20 — Relecture de l'Étape 19, copie OAuth automatique et connexion Android `google_sign_in` (23/11/2026)

### 1. Ce qui a été simplifié dans l'Étape 19

| Avant | Après |
| --- | --- |
| `clientIdPlaceholder` / `clientSecretPlaceholder` toujours vides, jamais utiles | Supprimés : l'identifiant ne vient que de `--dart-define`, de `secrets/` ou de la copie embarquée |
| `isLoaded` + relecture conditionnelle (état statique à maintenir) | `load()` relit simplement la configuration ; c'est `GoogleDriveService.signIn()` qui ne relit le disque que si rien n'est chargé |
| Constante `redirectPath` recopiée dans les tests | Chemin `/` écrit une fois, dans l'écouteur |
| `GoogleAuthException` dans `google_drive_backup.dart` | Déplacée dans `google_auth_exception.dart` (partagée par les deux flux) et ré-exportée : aucun import à changer ailleurs |
| `FlutterSecureStorage` exposé par le service | `GoogleTokenVault` (3 opérations) : `SecureGoogleTokenVault` en production, coffre mémoire dans les tests |
| Script `tool/sync_oauth_secrets.dart` limité à deux clés | Il transporte aussi `AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID` et rappelle qu'il n'a plus à être lancé à la main |

### 2. Génération de `assets/config/google_oauth.json` réellement automatique

| Mécanisme | Quand | Effet |
| --- | --- | --- |
| Tâche Gradle `syncOAuthSecrets` (`android/app/build.gradle.kts`) | Avant chaque `flutter run` / `flutter build` Android (`preBuild`, donc avant `compileFlutterBuildDebug`) | Exécute le script ; `isIgnoreExitValue` et `cmd /c … & exit 0` / `sh -c … || true` garantissent qu'un échec ne bloque jamais la build |
| `dart run tool/sync_oauth_secrets.dart` | Ponctuel | Reste disponible pour forcer une copie ou diagnostiquer un identifiant refusé |

**Une seule voie** : sur ordinateur l'application lit directement
`secrets/google_oauth.json` et n'a jamais besoin de la copie ; seul le build
Android peut l'embarquer. La copie au démarrage de la première version de
l'Étape 20 a été retirée (voir §5). Aucun secret n'entre dans Git :
`git check-ignore` confirme `/secrets/` et `/assets/config/google_oauth.json`,
tandis que `assets/config/.gitkeep` garde le dossier suivi.

### 3. Connexion Google Android via `google_sign_in`

| Fichier | Rôle |
| --- | --- |
| `lib/core/backup/google_android_auth.dart` | `GoogleAndroidAuth` (contrat testable) + `GoogleSignInAndroidAuth` : `initialize(serverClientId:)`, `authenticate(scopeHint: driveScopes)`, `authorizationForScopes` puis `authorizeScopes` pour obtenir le jeton Drive, `attemptLightweightAuthentication` pour la reconnexion silencieuse, `disconnect` pour la révocation |
| `lib/core/backup/google_drive_backup.dart` | `signIn()` choisit la branche (`Platform.isAndroid`, injectable) : Android → `google_sign_in` sans navigateur, sans `client_secret`, sans boucle locale ; ailleurs → flux PKCE inchangé. Le renouvellement se déduit du coffre : jeton de rafraîchissement présent = flux de bureau, absent = session Android renouvelée par Play services |
| `lib/core/config/google_oauth_config.dart` | `androidServerClientId` (client « Application Web »), `isAndroidReady`, `canSignIn` (voie de la plateforme courante), `driveScopes`, `androidHint` (package `com.akiba.app`, empreinte SHA-1, utilisateurs test) |
| `lib/features/backup/backup_center.dart` | Le bouton « Se connecter avec Google » apparaît dès que la voie de la plateforme est configurée (`canSignIn`) |
| `lib/features/onboarding/onboarding_flow.dart` | E7 accepte aussi la configuration Android |
| `pubspec.yaml` | `google_sign_in: ^7.2.0` |

Points de conception :

1. **Le jeton Drive vient du périmètre `drive.appdata`** demandé à
   `authorizationClient` : l'authentification seule ne donne aucun accès aux
   fichiers. Le flux de bureau continue d'utiliser `openid`, `email` et la même
   portée Drive.
2. **Aucun jeton durable sur Android** : Play services renouvelle le jeton
   d'accès ; seule l'adresse du compte est écrite dans le coffre système. Le
   jeton d'accès reste en mémoire, avec une validité de 50 min (Google en accorde
   une heure).
3. **Cohérence du package** : le client OAuth Android doit être créé pour
   `applicationId` = **`com.akiba.app`** (le `namespace` Gradle reste
   `com.example.akiba`, il ne conditionne pas l'enregistrement) avec l'empreinte
   SHA-1 de la clé de signature. Le `serverClientId` transmis est celui du client
   « Application Web » — un client de bureau ne peut pas servir de
   `serverClientId`.
4. **Erreurs nommées** : `canceled` (repli dossier synchronisé), `uiUnavailable`,
   `client/providerConfigurationError` et `unknownError` renvoient vers la
   configuration Cloud Console (package, SHA-1, compte testeur, portée
   `drive.appdata`) ; aucun message ne contient de jeton.
5. **Repli intact** : échec ou annulation → `GoogleAuthException`, l'application
   n'est jamais bloquée et la sauvegarde AES-256-GCM vers le dossier Drive
   synchronisé reste le chemin normal. Aucune écriture comptable, aucun montant
   dans les messages.

### 4. Tests

| Fichier | Nouveaux tests |
| --- | --- |
| `test/google_android_auth_test.dart` | 5 tests — jeton Drive obtenu sans jeton de rafraîchissement ; refus sans `serverClientId` (message avec package + SHA-1) ; refus du greffon propagé sans session ni coffre ; déconnexion qui révoque et vide le coffre ; branche ordinateur qui n'appelle jamais `google_sign_in` |
| `test/core_test.dart` | Mise à jour : les assertions sur `isLoaded` et `redirectPath` (supprimés) disparaissent, le reste de la requête OAuth est inchangé |

### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test tool` | 101 fichiers, 0 changement à la relance |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **133 tests, tous passés** |
| `dart run tool/sync_oauth_secrets.dart` | « déjà à jour », code retour 0 |
| `./gradlew :app:assembleDebug` | **BUILD SUCCESSFUL in 7m 22s** (premier build), APK produite ; `syncOAuthSecrets` exécutée avant `compileFlutterBuildDebug`, `assets/flutter_assets/assets/config/google_oauth.json` présent dans l'APK |
| `git check-ignore -v` | `/secrets/` et `/assets/config/google_oauth.json` ignorés |

### 5. Relecture de l'Étape 20 (23/11/2026)

| Simplification | Raison |
| --- | --- |
| Copie au démarrage (`load()` → `syncCopy`) et `copyNotice` supprimés | Doublon du hook Gradle : sur ordinateur la copie n'est jamais relue (le fichier `secrets/` gagne), et sur Android seul le build peut l'embarquer. Le hook s'exécute **avant** `compileFlutterBuildDebug`. `GoogleOAuthConfig` ne fait plus que lire |
| Clé de coffre `akiba_google_auth_mode` supprimée | Information déjà portée par le jeton de rafraîchissement : présent = flux de bureau, absent = session Android |
| Champ `GoogleSession.refreshToken` supprimé | Jamais lu après construction |
| `_signInAndroid()` n'ajoute plus `setupHint` | Message utile sur ordinateur seulement ; `androidHint` dit déjà quoi faire |
| Message `clientConfigurationError` raccourci | Il répétait mot pour mot `androidHint` |
| `GoogleOAuthConfig.canSignIn` ajouté | Le centre de sauvegarde et l'onboarding annonçaient « identifiants prêts » sur Android avec un client de bureau, qui ne peut pas servir de `serverClientId` |

Build Android : l'échec observé venait d'une **interruption manuelle** pendant la
première compilation (7 min de greffons natifs), pas du code. Une fois menée à
terme, `assembleDebug` réussit et l'APK contient la copie embarquée.

### Ce qui n'est pas vérifié

- **Aucune connexion Google réelle** : ni `google_sign_in` sur appareil, ni le
  consentement, ni le jeton Drive. Aucun compte testeur, aucune empreinte SHA-1
  enregistrée.
- **Application non lancée sur appareil** : l'APK est produite, mais ni
  l'installation sur le téléphone (`adb`) ni le parcours de connexion Google
  n'ont été exercés.
- **SHA-1 du poste non enregistré** : l'empreinte doit être ajoutée côté Google
  Cloud Console par le porteur, avec le client « Application Web ».

---

## Étape 21 — Relève de l'empreinte SHA-1 et procédure Android (24/11/2026)

### 1. Outil `tool/debug_sha1.dart`

L'empreinte SHA-1 était le seul élément de la configuration Google à exiger une
commande `keytool` tapée à la main (chemin du magasin, mot de passe, alias,
libellé parfois traduit). L'outil la relève en une commande.

| Aspect | Détail |
| --- | --- |
| Commande | `dart run tool/debug_sha1.dart` |
| Source | `~/.android/debug.keystore`, alias `androiddebugkey`, mot de passe `android` (défauts de Gradle) |
| Sortie | source, `SHA-1` avec deux-points, package `com.akiba.app`, puis le rappel du client OAuth « Android » |
| Options | `--keystore`, `--alias`, `--storepass`, `--keytool`, `-h` |
| Dépendances | aucune : `keytool` du JDK (JAVA_HOME, PATH, ou JDK d'Android Studio) |
| Langue | forcée en anglais (`-J-Duser.language=en`) pour que le libellé `SHA1:` ne dépende pas du poste ; les deux formes `SHA1:` / `SHA-1 :` sont lues |
| Sécurité | lecture seule ; l'empreinte d'un certificat n'est pas un secret, aucun mot de passe n'est affiché |
| Erreurs nommées | magasin absent (build debug à lancer), mot de passe différent, `keytool` introuvable, alias vide |

Un mode `--apk` a été écrit puis **retiré** : `keytool -printcert -jarfile` ne
lit que les signatures JAR v1, absentes des APK Flutter signés en v2/v3 ; il
répondait « Aucune empreinte trouvée » sur un APK valide. La commande correcte
pour un APK signé par une autre clé (`apksigner verify --print-certs`) est
documentée dans la procédure.

### 2. Procédure `akiba_spec/activer_connexion_google_android.md`

Sept étapes et un dépannage, avec les libellés actuels de la console (Google
Auth Platform → Clients / Audience / Data Access) :

| Étape | Contenu |
| --- | --- |
| 1 | Relever l'empreinte (`dart run tool/debug_sha1.dart`), cas `apksigner`, empreinte propre à chaque poste |
| 2 | Projet Google Cloud et activation de l'API Google Drive |
| 3 | Écran de consentement : Audience **Externe / Testing**, **utilisateurs test** (sans eux : `access_denied`), portée `drive.appdata` uniquement |
| 4 | Client **Android** : package `com.akiba.app` (jamais le `namespace` `com.example.akiba`) + SHA-1 ; aucun fichier à télécharger |
| 5 | Client **Application Web** sans origine ni redirection, ID seul vers `AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID` ; secret non recopié ; JSON complet |
| 6 | Copie embarquée (tâche Gradle `syncOAuthSecrets`, commande ponctuelle), build et `adb install -r`, cas `INSTALL_FAILED_UPDATE_INCOMPATIBLE` |
| 7 | Essai réel : compte test, jeton Drive, sauvegarde visible, repli hors ligne |
| Dépannage | `DEVELOPER_ERROR` (package/SHA-1/projet/propagation), autre clé de signature, `access_denied`, 403 de portée, `canSignIn` faux, compte déjà connecté, copie périmée |

Le document remplace les renvois vagues (« à enregistrer côté Cloud Console »)
de `RESTE_A_FAIRE.md` (Étape 20) et de
`regles_themes_et_identifiants_google.md` §2, mis à jour avec la troisième clé
du JSON. La numérotation de cette section (7 avant 5) est corrigée au passage.

### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart run tool/debug_sha1.dart` | exit 0, empreinte `F7:4C:…:DB:80` lue dans `C:\Users\amahp\.android\debug.keystore` |
| `dart run tool/debug_sha1.dart --help` | exit 0, aide affichée |
| `dart run tool/debug_sha1.dart --nope` | une ligne « option inconnue » puis l'aide, aucun plantage |
| `dart format lib test tool` | 102 fichiers, **0 changement** |
| `flutter analyze` | **No issues found!** (183,9 s) |

### Ce qui n'est pas vérifié

- Aucun client OAuth Android ni « Application Web » n'a été créé : la procédure
  n'a pas été déroulée dans la console par l'assistant.
- Aucune connexion Google réelle ni aucune sauvegarde Drive.
- Aucun compte testeur ajouté, aucun appareil `adb` connecté.

---

## Étape 22 — Langue immédiate, permissions réelles, Home Lab, cycle de vie, règlements et solde en direct (24/11/2026)

### 1. Langue de l'onboarding

- Cause : l'onboarding écrivait `settings.set('language', …)` ; les globales
  (`AkibaL10n`, `AkibaDate`) n'étaient resynchronisées que par le `builder`
  racine, et l'habillage du parcours restait en français — la sélection
  semblait sans effet.
- Correctif : `AkibaSettings.setLanguage` normalise, applique `AkibaL10n` et
  `AkibaDate` **avant** `set()` (qui notifie), et `notifyListeners` resynchronise
  aussi la langue. L'onboarding passe par ce chemin, et son habillage est
  traduit : titre « Votre langue / Your language », note explicative, boutons
  « Retour / Continue / Enter AKIBA », compteur d'étape, en-têtes de thème.
- Résultat : choisir « English » à E1 bascule immédiatement l'onboarding, la
  navigation, l'accueil et le Profil ; le réglage reste enregistré.

### 2. Permissions des rappels (matin / midi / soir)

- `LocalNotifications.permissionGranted()` lit l'état réel
  (`areNotificationsEnabled()` sur Android 13+, `checkPermissions()` sur
  iOS/macOS) sans ouvrir de fenêtre.
- `requestPermission()` relit l'état après la demande : un `null` de certaines
  versions ne devient plus « refusé ».
- L'onboarding : lecture → demande → **relecture**, garde de ré-entrance
  (l'interrupteur est désactivé pendant la demande), message seulement en cas
  de refus réel, bouton « Ouvrir les réglages système » (`openAppSettings`) si
  le refus est définitif, et message honnête sur Windows (pas de livraison
  système) au lieu de « autorisation refusée ».
- `ReminderScheduler` ne se fie plus au seul drapeau `permission_notifications`
  périmé : l'état système fait foi, et un accord réel remet le drapeau à jour.
  Le Profil distingue « non autorisé » de « planification indisponible ».

### 3. Test de connexion Home Lab

- `BackupService.normalizeUrl` : accepte `192.168.1.80`, `192.168.1.80:8080`,
  `akiba.local`, et les URL complètes ; ajoute `http://` quand le schéma manque,
  refuse les adresses vides ou sans hôte, et rejette toujours les schémas autres
  que http/https.
- `probeRemote` : délai de connexion 8 s, en-têtes `Accept` et `User-Agent`,
  distinction **port fermé** / **nom introuvable** / **pas de route** /
  certificat refusé / délai / autre code HTTP, et message dédié pour une
  connexion interrompue.
- Le centre de sauvegarde valide l'adresse **avant** l'appel réseau, enregistre
  l'adresse normalisée et teste exactement celle-là ; le texte d'aide explique
  qu'une IP seule suffit.

### 4. Assertions Flutter (débordements de Dropdown et sortie d'écran)

- `DropdownButton` : les valeurs `timezone` / `dateStyle` inconnues (restauration,
  ancienne version) sont ajoutées à la liste — Profil et onboarding ; la
  catégorie de l'assistant est toujours ramenée à la liste courante ; les comptes
  sont dédupliqués ; une ligne SMS qui pointe un compte disparu retombe sur le
  premier.
- `framework.dart` « check that it really is our descendant » : l'assistant
  capturait `Navigator.of(context)` **après** `pop()` pour afficher la fête
  d'épargne et les bandeaux de confirmation. Le navigateur et le messager sont
  maintenant pris avant `pop()`, la fête s'affiche sur le navigateur, `_say` des
  paramètres IA vérifie `mounted`, et les `catch` ne font plus `setState` après
  fermeture.

### 5. Règlement des créances et des dettes

- Nouvelle opération `AkibaStore.settleDebt` (SQLite chiffré, simulation, repli
  vide) : une **créance encaissée** crée une entrée `+montant` sur le compte
  choisi ; une **dette payée** crée une sortie `−montant` du compte choisi. Le
  montant est borné au reste dû et le reste dû est mis à jour dans la même
  opération. Catégories explicites `Créance` / `Dette`, `isNeutral: false`.
- Portefeuille : « Régler » demande désormais **le compte** (en plus du montant),
  avec un texte adapté (« L'encaissement entre sur le compte choisi », « Le
  paiement sort du compte choisi »), et l'annulation supprime le mouvement puis
  restaure la dette.
- Assistant : quand la phrase décrit une créance ou une dette, un bouton « Cette
  créance a été encaissée » / « Cette dette a été payée » ouvre le mode
  règlement, liste les lignes ouvertes du même sens (reste dû masqué si
  masquage), préremplit le montant et le contact, et demande le compte.
- Une créance ou une dette **ouverte** reste hors du solde disponible : seule
  son encaissement ou son paiement déplace de l'argent.

### 6. Solde de l'accueil en temps réel et déconnexion

- **Cause réelle du solde figé** : `DashboardScreen._reload` faisait
  `setState(() => _snapshot = store.loadDashboard())`. Le callback rendait un
  `Future`, ce que Flutter refuse (« setState() callback argument returned a
  Future ») : la relance était rejetée à chaque `revision.bump()`. Le même
  défaut existait dans Analyses et Portefeuille.
- Correctif : le `Future` est créé hors de `setState`, puis affecté dans un bloc
  synchrone ; `_refresh` fait de même. Un test widget vérifie qu'une entrée, une
  dépense puis un règlement changent le solde affiché **sans changer d'onglet**.
- Profil → Sauvegarde : nouveau bouton « Se déconnecter » avec confirmation.
  `GoogleDriveService.signOut` supprime le jeton de rafraîchissement et l'e-mail
  du coffre système (`disconnect` sur Android), `google_linked` repasse à faux ;
  les données locales chiffrées ne sont jamais supprimées.

### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 101 fichiers, **0 changement** |
| `flutter analyze` | **No issues found!** (21,1 s) |
| `flutter test` | **139 tests, tous passés** (133 → 139, `test/fixes_test.dart`) |

Nouveaux tests : globales de langue avant notification, bascule réelle de
l'onboarding (« Your language », « Continue », plus de « Votre langue »),
créance encaissée (+5 000 sur le solde), dette payée (−2 000 puis annulation),
règlement borné au reste dû, solde de l'accueil actualisé après entrée, dépense
et règlement.

Invariants tenus : chiffrement AES-256 (SQLCipher) et AES-256-GCM inchangés,
argent de tiers toujours isolé (`isNeutral` explicite), masquage respecté dans
les nouveaux libellés, cinq thèmes et barre basse non flottante non modifiés,
aucun serveur maître, aucun secret versionné.

### Ce qui n'est pas vérifié

- Aucun appareil Android connecté : permission accordée/refusée réellement,
  livraison des rappels, `openAppSettings`, déconnexion Google et Home Lab sur un
  vrai Wi-Fi n'ont pas été exercés.
- Les écrans métier détaillés restent en français (Analyses, Portefeuille,
  saisie rapide) : la traduction couvre navigation, accueil, Profil et
  l'habillage de l'onboarding.
- Aucun contrôle visuel des nouveaux boutons (règlement dans l'assistant,
  déconnexion) : seul l'analyseur et les tests widget sont passés.

---

## Étape 23 — Bienvenue après onboarding et SMS financiers détectés en arrière-plan (24/11/2026)

### 1. Notification de bienvenue

- `AppNotifications.welcome` (nouveau fichier
  `lib/core/notifications/app_notifications.dart`) n'envoie la bienvenue que si
  `permission_notifications` est enregistré **et** si le système autorise
  réellement (`LocalNotifications.show` relit l'état).
- Déclenchement à la dernière étape de l'onboarding, juste après
  `onboarding_done`, sans bloquer l'entrée dans l'application
  (`unawaited`).
- Texte dans la langue active, **sans aucun montant** :
  « Bienvenue dans AKIBA — Votre espace est prêt. Touchez le cochon pour
  enregistrer votre première ligne ; vos chiffres restent privés et chiffrés. »
  (version anglaise équivalente).
- Canal Android dédié `akiba_accueil` (« AKIBA »), notification ponctuelle
  (pas de planification). Sur Windows, rien n'est affiché : l'application ne
  prétend pas le contraire.

### 2. Détection SMS Flooz / Mixx by Yas / banques, application fermée

| Élément | Détail |
| --- | --- |
| Récepteur | `android/.../SmsReceiver.kt` : `Telephony.Sms.Intents.getMessagesFromIntent`, concaténation des SMS multipart, filtre opérateur/banque + devise + montant |
| Protection | `android:permission="android.permission.BROADCAST_SMS"`, `exported="true"`, priorité 999 : aucune application tierce ne peut simuler un SMS financier |
| Permissions | `READ_SMS` (déjà) + `RECEIVE_SMS` (nouveau) ; demandées à l'activation dans l'onboarding **et** depuis le Profil (nouveau bouton « Activer la détection ») |
| Notification | Canal `akiba_sms`, texte fixe « Nouveau SMS financier — Touchez pour vérifier et confirmer l'opération. » : **aucun montant**, donc masquage respecté par construction |
| Transport | Le texte voyage dans l'`Intent` du `PendingIntent` (extrait retiré après lecture) : aucun fichier, aucune préférence, aucune base |
| Pont Flutter | `MainActivity` expose `akiba/sms` (`consumePendingSms`) et `akiba/sms_events` ; `lib/core/sms/sms_bridge.dart` les consomme |
| Ouverture | `AkibaShell` : au démarrage (application fermée) et sur événement (application en arrière-plan), filtre `SmsDetector.isFinancialSms`, analyse `SmsParser`, puis ouvre la **saisie rapide préremplie** |
| Préremplissage | `SmsEntryIntent` : montant, sens (entrée/sortie), support (`flooz`, `mixxByYas`, `orabank`), contact et référence ; le compte du support est présélectionné ; bandeau « Prérempli depuis un SMS · vérifiez puis confirmez. » |
| Écriture | Toujours après le bouton « Enregistrer » : test widget vérifiant base vide avant, une ligne après |

Analyse étendue (`SmsParser`) :

- sources : Flooz/Moov, Mixx/Yas, **Orabank** et banques (`bank`, `banque`,
  BOA, Ecobank, Coris, NSIA, UBS, BSIC, Attijari, Société Générale, SGC…) avec
  le libellé générique « Banque » quand le nom exact n'est pas connu ;
- montants : `FCFA`, `XOF`, `CFA` et **`F CFA`** espacé ;
- sens : dépôt/crédit/crédité/virement reçu/remboursement → entrée ;
  retrait/débit/débité/prélèvement/chèque/paiement/achat/DAB/commission →
  sortie ;
- `SmsDetector.isFinancialSms` : source connue **et** montant exploitable,
  utilisé par le pont avant toute ouverture.

### 3. Vérifier sur l'appareil

```bash
# 1. Autoriser : Onboarding E8 ou Profil → SMS financiers → Activer la détection
adb shell dumpsys package com.akiba.app | grep -E "READ_SMS|RECEIVE_SMS|POST_NOTIFICATIONS"

# 2. Logs de l'application (aucun montant n'y est journalisé)
adb logcat -c && adb logcat -s flutter

# 3. Émulateur : envoyer un vrai SMS système, application fermée
adb emu sms send 12345 "Flooz: Vous avez recu 25000 FCFA de KOFFI Ama. Ref FL8842."
adb emu sms send 12345 "Orabank: Debit de 12000 FCFA - PAIEMENT CARTE."
adb emu sms send 12345 "Mixx by Yas: Paiement de 3500 FCFA effectue chez ALIMENTATION."

# 4. Appareil physique : envoyer le SMS depuis un second téléphone.
#    `adb shell am broadcast` est volontairement refusé (protection BROADCAST_SMS).

# 5. Constater la notification puis toucher : la fiche s'ouvre préremplie
adb shell dumpsys notification --noredact | grep -A 8 akiba_sms
```

Attendu : notification « Nouveau SMS financier » (sans montant), ouverture de
la saisie rapide avec montant, sens et compte Orabank/Flooz/Mixx présélectionné,
et aucune écriture avant « Enregistrer ». Un SMS ordinaire ne produit rien.

### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 105 fichiers, 0 changement après formatage |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **149 tests, tous passés** (139 → 149, `test/sms_welcome_test.dart`) |
| `./gradlew :app:compileDebugKotlin` | **BUILD SUCCESSFUL in 3m 53s** : nouveau récepteur, `MainActivity` et manifeste compilés (app + plugins) |

Nouveaux tests : dépôt Orabank (entrée, support `orabank`), retrait/paiement
Orabank (sortie), banque générique, `F CFA` espacé, Flooz et Mixx by Yas
(supports et sens), message non financier ignoré, bienvenue refusée sans
permission / envoyée sans aucun chiffre et dans la langue choisie, et fiche
préremplie sans écriture avant confirmation.

Invariants tenus : aucune écriture automatique, chiffrement AES-256 (SQLCipher)
et AES-256-GCM inchangés, aucun montant dans une notification, argent de tiers
et créances/dettes inchangés, cinq thèmes, Home Lab seul, barre basse non
flottante.

### Ce qui n'est pas vérifié

- Le code Kotlin **compile** (`:app:compileDebugKotlin`), mais l'APK complète
  n'a pas été réassemblée et aucun appareil `adb` n'est connecté : le
  manifeste fusionné, l'installation et le parcours réel restent à vérifier par
  `flutter build apk --debug` puis `adb install -r`.
- Aucun SMS réel reçu sur un téléphone : le parcours notification → fiche n'est
  couvert que par les tests Dart et la lecture de code.
- Aucun contrôle visuel du bandeau de préremplissage ni de la notification.

---

## Étape 24 — Rapport mensuel PDF, avis IA, prévisualisation et envoi (24/11/2026)

### 1. Ce qui est livré

| Élément | Détail |
| --- | --- |
| Modèle de rapport | `lib/core/report/monthly_report.dart` : période (mois en cours, mois dernier, 30 derniers jours), entrées/sorties/solde, catégories, comptes, épargne, argent de tiers, créances/dettes, réserve de sécurité, six derniers mois |
| Règle des montants | **Toujours en clair** dans le rapport et le PDF : aucune lecture de `MaskedAmounts`, aucun `masked: true` dans le document. Le masquage global reste actif partout ailleurs |
| Isolation | Les entrées/sorties viennent de `categoryTotals` (tiers et épargne exclus par SQL) ; l'argent de tiers, l'épargne et les créances/dettes sont affichés dans des blocs **séparés** et jamais additionnés aux revenus |
| Avis IA | `ReportAdvisor` : trois conseils locaux déterministes (FR/EN) puis enrichissement optionnel par l'IA configurée (`AiTask.analysis`, quota journalier, cascade). Repli local instantané sans clé, hors ligne, quota atteint, erreur ou réponse illisible |
| PDF | `lib/core/report/report_pdf.dart` : logo embarqué (`akiba_mark_light/dark` selon le fond), en-tête AKIBA, période, indicateurs, détails catégories/comptes, épargne, **argent de tiers isolé**, créances/dettes, graphiques six mois, puis **avis et conseils de l'assistant** ; couleurs et langue du thème actif |
| Prévisualisation | `lib/features/report/report_preview.dart` : pages PDF rendues dans l'app (`PdfPreview`) + actions Email, WhatsApp et partage système avec le PDF en pièce jointe |
| Paramètres | Tuile « Rapport mensuel » : période, interrupteur données de simulation, destinataire Email, numéro WhatsApp, fin de mois, copie Home Lab, bouton « Générer et prévisualiser », date du dernier rapport |
| Fin de mois | `ReportScheduler` : au premier lancement d'un nouveau mois, si l'option est active, génère le rapport du mois écoulé, l'enregistre dans le dossier privé et affiche une notification **sans montant** |
| Home Lab | `ReportScheduler.sendToHomeLab` : PUT JSON (`pdf-base64`) vers l'adresse et le jeton déjà configurés dans la sauvegarde, uniquement après le geste de génération et si l'option est active |
| Dépendances | `pdf: 3.12.0` (génération pure Dart, hors ligne) et `printing: 5.14.2` (aperçu et feuille de partage) |

### 2. Tests

`test/monthly_report_test.dart` (6 tests) vérifie : montants lisibles même quand le masquage est actif ailleurs, argent de tiers exclu des totaux, bornes de période, avis local FR/EN, PDF (logo/titre, catégories, devise, avis), fidélité de la couleur du thème actif, langue anglaise, mode simulation, avis IA injecté, repli local sans IA.

`test/savings_messages_test.dart` (7 tests) couvre le catalogue d'épargne et le repli local du coach (Étape 25).

### 3. Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 112 fichiers, 0 changement après formatage |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **162 tests, tous passés** (149 → 162) |
| `./gradlew :printing:compileDebugJavaWithJavac :app:compileDebugKotlin` | **BUILD SUCCESSFUL in 3m 23s** (greffon `printing` + application) |

### 4. Limites

- Le PDF fait deux pages A4 avec le contenu actuel ; la prévisualisation native (`printing`/PDFium) et le partage n'ont pas été exercés sur un appareil.
- L'envoi Email/WhatsApp passe par la feuille de partage du système (pièce jointe) ou `wa.me` (lien texte) : aucun serveur AKIBA n'envoie de message.
- L'IA ne reçoit les chiffres que si elle est explicitement configurée (`ai_remote_enabled`) ; sinon l'analyse reste locale.

---

## Étape 25 — Messages d'épargne, taquineries de retrait et transition (24/11/2026)

- `lib/core/savings/savings_messages.dart` : catalogue local FR/EN (10 encouragements et 12 taquineries par langue), sans montant, avec `{pot}` remplacé par le nom du coffre ; sélection sans répétition immédiate (décalage déterministe si le hasard retombe sur le même index).
- `SavingsCoach` : enrichissement **optionnel** par l'IA configurée (`AiTask.coaching`). Le prompt ne contient **aucun montant** ; sans clé, hors ligne, quota épuisé ou erreur, le message local revient instantanément.
- Après un versement : message local immédiat, puis remplacement doux par la phrase IA si elle arrive.
- Après un **retrait** d'épargne : taquinerie locale immédiate en bas d'écran, sans montant et sans bloquer la transaction déjà enregistrée (Portefeuille).
- Fiche de fête (`savings_celebration.dart`) : l'animation de 3 s se termine, puis le message apparaît en fondu + glissement (`AnimatedOpacity`/`AnimatedSlide`/`AnimatedSize`), avec un bouton « Continuer » ; la fête ne se referme plus toute seule avant lecture. Si « Réduire les animations » est actif, l'image finale et le message sont affichés sans mouvement.
- Le même message est repris dans la confirmation de l'assistant après un versement d'épargne.

Vérifications : couvertes par les 162 tests ; la transition visuelle n'a pas été observée sur appareil.

---

## Étape 26 — Identité PDF, cauris, sauvegarde portable et permissions (24/11/2026)

- L’en-tête PDF affiche le nom complet, la photo de profil locale si disponible, sinon un avatar circulaire à initiales. La photo est lue depuis son stockage AES-256-GCM local et n’est pas ajoutée à la sauvegarde ; le rapport conserve les montants en clair et les blocs tiers / créances / dettes restent isolés.
- `SavingsProjection.cauriCountForAmount` applique `montant ~/ 100`, zéro pour les montants non positifs et minimum un cauri au-dessus de zéro. Le nombre reste exact pour les grands montants (aucun badge textuel depuis l’Étape 31), sans prolonger l’animation de 3 secondes. Le son est le WAV embarqué joué à chaque impact avec un plan proportionnel ; son indisponibilité ne bloque pas l’animation.
- Les nouvelles enveloppes version 3 utilisent PBKDF2-HMAC-SHA256 (120 000 itérations) sur le `sub` stable Google et le sel applicatif, avec un sel aléatoire de 16 octets dans l’en-tête. La clé calculée reste en mémoire. Les enveloppes version 2 `device-key` restent lisibles sur l’appareil qui possède leur clé historique.
- Le diagnostic Home Lab renvoie les erreurs d’URL, TLS, délai, port et HTTP; la normalisation garde schéma, port et chemin de santé/API.
- À l’activation d’un rappel, la demande système est déclenchée via le greffon Android (POST_NOTIFICATIONS sur Android 13+). Au retour à l’application, l’autorisation réelle est relue, le réglage miroir est rafraîchi et les rappels actifs sont reprogrammés sans nouvelle demande.

Tests ajoutés : règle de calcul cauri, PDF nom/photo, dérivation/restauration sans clé locale, et sonde Home Lab locale/URL/port.

Vérifications réellement exécutées : `dart format lib test` (113 fichiers, 0 changement au dernier passage), `flutter analyze` (**No issues found!**), `flutter test --reporter compact` (**167 tests passés**). Les essais sur appareil restent listés dans `RESTE_A_FAIRE.md`.





---

## Étape 27 — Permission de rappel dans l’onboarding (24/11/2026)

- Le switch « Rappels matin, midi et soir » interroge d’abord l’état réel. Déjà accordé : il s’active sans redemander. Refus simple : la demande Android est lancée via `Permission.notification` (`POST_NOTIFICATIONS`). Refus permanent : aucun nouvel appel à la permission, un bouton ouvre les réglages de l’application.
- L’onboarding écoute la reprise du cycle de vie. Au retour des réglages, il relit l’autorisation, actualise le switch et persiste immédiatement `permission_notifications`.
- Une frontière injectable `NotificationPermissionGateway` permet de tester l’interaction UI sans simuler le canal natif Android.

Tests widget ajoutés pour les trois cas (déjà accordée, demande puis accord, refus définitif puis ouverture réglages et accord au retour). `dart format lib test` : 115 fichiers, aucun changement au dernier passage. `flutter analyze` : aucun problème. `flutter test --reporter compact` : **170 tests passés**.

Vérification après précision du libellé du bouton : `flutter analyze` sans problème et `flutter test test/onboarding_notification_permission_test.dart` (**3 tests passés**). La suite complète précédente reste à **170 tests passés**; seul le texte du bouton a changé depuis.

## Étape 28 — Bienvenue nominative et reprogrammation (24/11/2026)

- À la fin de l’onboarding, AKIBA relit l’autorisation système, synchronise son miroir local, puis attend l’envoi de la notification avant la navigation. Le message inclut prénom et nom enregistrés, avec un accueil générique si le profil est vide; aucun montant n’y figure.
- Le gateway Android croise `Permission.notification` avec `areNotificationsEnabled()` du plugin, puis relit l’état réel après une demande; le miroir local seul ne détermine plus la permission.
- À la fin de l’onboarding, la permission est relue avant l’envoi; le canal de bienvenue est créé par le plugin lors de l’affichage. Prénom/nom restent personnalisés, aucun montant, envoi attendu avant navigation.
- « Reprogrammer » demande si nécessaire, utilise le nombre planifié pour confirmer le succès et n’affiche le refus général que si la lecture réelle est négative. Le statut distingue aussi une autorisation générale accordée d’un canal Android `akiba_rappels` désactivé (importance `none`).
- Tests widget : bienvenue nominative avant navigation, et clic « Reprogrammer » avec permission accordée/rappels actifs vérifiant l’appel au scheduler, 3 planifications rapportées et absence du faux refus. `dart format lib test` : 0 changement; `flutter analyze` : No issues found; test ciblé : 5 tests passés. Suite complète : en cours de validation.


---

## Étape 29 — Vraie cause du faux négatif « Notifications non autorisées » (25/11/2026)

**Constat sur appareil** : Android affichait « Notifications : Autorisé » pour AKIBA, alors que le Profil répondait « Notifications non autorisées par le système », que « Reprogrammer » échouait et que la bienvenue de fin d’onboarding ne partait pas.

**Cause réelle** : `LocalNotifications.ensureReady` initialisait `flutter_local_notifications` avec `AndroidInitializationSettings('@mipmap/ic_launcher')`. Le greffon valide l’icône par `getIdentifier(nom, "drawable", paquet)` : `ic_launcher` n’existe qu’en `mipmap`, la résolution renvoyait 0, `initialize` répondait `invalid_icon` et `_ready` restait faux. Comme `permissionGranted()` commençait par `if (!await ensureReady()) return false;`, **toutes** les lectures (statut du Profil, reprogrammation, bienvenue, planification) concluaient « non autorisé » sans jamais interroger le système. Le défaut n’était donc ni POST_NOTIFICATIONS ni le canal : c’était un faux négatif fabriqué par l’initialisation.

**Correctifs**
- Icône dédiée `android/app/src/main/res/drawable/ic_stat_akiba.png` (96 px, silhouette du cochon teintée par le système), utilisée par `AndroidInitializationSettings('ic_stat_akiba')` et par `icon:` des notifications `akiba_accueil`, `akiba_rappels` et `akiba_repas`.
- `platformPermissionState()` lit `areNotificationsEnabled()` du `NotificationManager` **sans** passer par l’initialisation ; `null` signifie « illisible », jamais « refusé ». `permissionGranted()` s’appuie dessus et ne retombe sur `permission_handler` qu’en dernier recours.
- `background_reminders.dart` (isolate Workmanager) portait la même icône invalide : il initialise et affiche désormais avec `ic_stat_akiba`, sinon les rappels de repas en arrière-plan échouaient aussi silencieusement.
- `requestPermission()` ne renvoie plus faux quand l’initialisation échoue (tentative au mieux puis relecture de l’état réel) ; `show()` fournit l’icône explicitement et ne dépend plus de `_ready` ; `androidChannelEnabled()` n’exige plus l’initialisation.
- `SystemNotificationPermissionGateway.status()` consulte d’abord l’état plateforme ; `permission_handler` ne sert qu’à nommer un refus et ne contredit jamais un accord constaté. `request()` déclenche une seule fenêtre POST_NOTIFICATIONS puis relit l’état.
- `AppNotifications.welcome` ne consulte plus le miroir `permission_notifications` : l’état système décide, le miroir est seulement synchronisé quand l’accord est constaté. Nouveau point d’injection `permissionCheckOverride` pour tester accord et refus sans plateforme.

**Tests** : « Reprogrammer » avec permission système accordée et miroir local faux affiche « 3 rappels planifiés sur 7 jours » sans message de refus ; fin d’onboarding, « Bienvenue dans AKIBA » avec « Ama Koffi » est envoyée malgré un miroir faux ; refus système simulé, aucun envoi même si le miroir est vrai ; test unitaire « bienvenue : le miroir local périmé ne bloque plus l’envoi ». `dart format lib test` propre, `flutter analyze` — No issues found, tests ciblés — 16 passés, suite complète — 173 passés.

**Limite** : aucun appareil n’était connecté pendant ce tour (`adb devices` vide) ; l’affichage réel de la notification, la création du canal `akiba_accueil` et l’APK reconstruit restent à constater sur téléphone.

---

## Étape 30 — Restauration Drive sans faux rejet et Home Lab en deux étapes (25/11/2026)

**1. Faux rejet « Connectez le même compte Google pour restaurer cette sauvegarde »**

- Cause n°1 : `OnboardingFlow._restoreDriveBackup` appelait `restore(envelope)` **sans** identité Google. Toute enveloppe v3 (clé dérivée du compte) tombait dans la branche « identité absente » et affichait ce message, compte connecté ou non. `_importLocalBackup` avait le même défaut.
- Cause n°2 : `BackupService.createEnvelope` dérivait la clé de la chaîne brute `googleAccountId`, sans normalisation : une variation d'espaces ou de casse (e-mail saisi différemment, identifiant renvoyé avec espaces) suffisait à produire une autre clé.
- Cause n°3 : `GoogleDriveService.currentAccountId()` passait par `_activeSession()` ; hors ligne ou session expirée il levait une exception, et l'identité n'était jamais transmise.
- Nouveau `lib/core/backup/google_account.dart` : `GoogleAccount.normalized` met l'e-mail en minuscules et supprime tous les espaces, conserve l'identifiant stable et la variante brute, et expose `keyCandidates` (identifiant normalisé, identifiant brut, e-mail normalisé, e-mail brut).
- `createEnvelope(account:)` dérive la clé de la première identité candidate et n'écrit dans l'enveloppe que les métadonnées d'affichage du compte, jamais l'identité de dérivation.
- `decryptEnvelope(account:)` essaie chaque variante (filtre `keyId` puis tag GCM) : une reconnexion avec le même compte aboutit même si casse ou espaces diffèrent, et une enveloppe créée avant la normalisation reste lisible.
- `GoogleDriveService.currentAccount()` lit la session mémoire, sinon le coffre (`akiba_google_account_id`, `akiba_google_email`) **sans réseau** : la restauration d'une sauvegarde ne dépend plus d'une reconnexion.
- L'e-mail attendu n'est affiché que si le compte connecté diffère réellement ; compte identique mais clé différente donne un message dédié (« déconnectez puis reconnectez »).
- `_backup` utilisait aussi `currentAccountId()` : sans compte lié, la sauvegarde par dossier synchronisé échouait. Elle utilise désormais une identité vide → clé d'appareil, conformément au repli documenté.

**2. Home Lab en deux étapes**

- Étape 1 — adresse : `HomeLabSetup.testAddress` normalise (IP, `ip:port`, nom, URL), interroge le serveur en GET **sans jeton**, mesure la latence (`HomeLabProbe.latency`) et enregistre l'URL testée. Statut « Communication OK en 18 ms (HTTP 204) » ou diagnostic précis (port fermé, nom introuvable, aucune route, certificat, délai ; 401/403 = joignable mais jeton exigé).
- Étape 2 — jeton : déverrouillée seulement après un test réussi (`tokenStepUnlocked`). `activateToken` revérifie la communication avec le jeton, refuse un jeton refusé sans rien persister, puis écrit le jeton dans `flutter_secure_storage` (`SecureLabTokenStore`, clé `akiba_lab_token`), arme `lab_auto_backup` et envoie immédiatement une première sauvegarde chiffrée AES-256-GCM.
- Le jeton n'est plus écrit dans les réglages SQLite : `lab_token` reste une valeur héritée, migrée vers le coffre puis effacée (`migrateLegacyLabToken`). `ReportScheduler.sendToHomeLab` lit le jeton dans le coffre.
- `HomeLabAutoBackup.runIfDue` (toutes les 6 h, au démarrage via `runLabAutoBackupOnStartup` dans `main.dart`, hors chemin critique) réutilise l'enveloppe AES-256-GCM existante ; silencieux quand le Wi-Fi ou le serveur manque. Aucun serveur maître n'est introduit : cible locale unique.
- UI : pastilles « 1 · Adresse » / « 2 · Jeton & sauvegarde auto », bouton « Tester la communication », zone jeton masquée révélée après succès, bouton « Enregistrer et activer », état de la sauvegarde automatique.

**3. Invariants** : chiffrement AES-256-GCM inchangé (PBKDF2 120 000 tours, sel de 16 octets), aucun montant dans les notifications ni dans l'enveloppe, masquage et rapports/PDF inchangés, cinq thèmes et barre basse non flottante non touchés, argent de tiers et créances/dettes inchangés.

**Tests** : `test/backup_account_restore_test.dart` (normalisation ; e-mail/majuscules/espaces ; enveloppe héritée ; vraie différence avec e-mail attendu ; compte identique/clé différente ; absence de compte) et `test/home_lab_setup_test.dart` (étape 1 sans jeton avec latence et URL persistée ; adresse invalide ; jeton refusé sans activation ; jeton validé → coffre + `lab_auto_backup` + première sauvegarde PUT + échéance respectée ; inactif sans activation). `test/core_test.dart` adapté à la nouvelle API.

**Vérifications exécutées** : `dart format lib test` (119 fichiers, 0 changement au dernier passage), `flutter analyze` — **No issues found!**, `flutter test --reporter compact` — **186 tests passés**.

**Limites** : écran Home Lab et restauration Drive réelle non observés sur appareil (aucun appareil connecté) ; aucun serveur Home Lab réel joint.

---

## Étape 31 — Notifications complètes, cauris individuels, coffre accessible et Google avant le nom (25/11/2026)

**1. Messages de notification jamais tronqués**

- Nouveau `lib/core/notifications/notification_style.dart` : `AkibaNotificationStyle.android(...)` construit un `AndroidNotificationDetails` avec `BigTextStyleInformation(body, contentTitle: title)` et `ticker: body`. Le corps complet part donc à la fois comme `contentText` et comme `bigText` : Android déplie le message entier, sans « … ».
- `LocalNotifications.show` (bienvenue) et `LocalNotifications.schedule` (rappels) utilisent ce style. La planification construisait auparavant **un seul** `NotificationDetails` constant pour tous les rappels : chaque rappel a désormais ses propres détails, donc son propre texte étendu.
- Canaux et contenus inchangés (`akiba_accueil`, `akiba_rappels`), toujours aucun montant, et les mêmes règles de permission.

**2. Chute de cauris individuels (1 cauri = 100 FCFA)**

- `CauriDropAnimation` remplace le cauri unique + badge « ×N » par une **file de cauris** : 2 000 FCFA font tomber 20 cauris, chacun avec son départ échelonné, sa chute accélérée, sa rotation, un léger écart latéral resserré vers la fente, puis sa disparition dans la tirelire.
- Plus aucun multiplicateur textuel. La durée totale reste `AkibaDurations.cauriDrop` = **3 s**, quel que soit le montant : l'espacement se resserre quand le nombre grandit et la tirelire respire jusqu'au dernier cauri.
- Grands montants : au-delà de `maxVisibleCauris` (60), la file est plafonnée pour rester fluide ; aucun compteur n'est réintroduit. Son d'épargne, halo, étincelles et mode « Réduire les animations » conservés.
- `showSavingsCelebration` reçoit déjà le nombre exact (`SavingsProjection.cauriCountForAmount`) : le message d'encouragement apparaît toujours à la fin des 3 s, en fondu.

**3. Coffre d'épargne accessible, plus aucune « phase » en attente sur l'accueil**

- L'action rapide « Épargne » de l'accueil ouvre désormais le portefeuille sur l'onglet **Épargne** (`ValueNotifier<int> segmentRequest` transmis par `AkibaShell`), où les coffres, versements, retraits, objectifs et création de coffre sont opérationnels.
- « Voir tout » ouvre l'onglet **Mouvements** (historique complet déjà présent). Un mouvement d'épargne modifié depuis l'accueil renvoie vers l'onglet Épargne au lieu d'annoncer une phase.
- La carte d'aperçu IA ouvre l'assistant déjà implémenté (`openAssistant`) ; le libellé « module M12 (Phase 6) » devient « module M12 ».
- Plus aucun message « Phase 5 » / « Phase 6 » sur l'accueil (`_notYet` supprimé). Les invariants restent : montants masqués selon le réglage, argent de tiers et créances/dettes isolés, cinq thèmes, barre basse non flottante.

**4. Onboarding : Google avant la saisie du nom**

- Ordre des étapes : E1 bienvenue, E2 valeur, **E3 Sauvegarde et restauration (Google)**, E4 devise, **E5 identité manuelle**, puis comptes, PIN, permissions, habitudes, données, prêt.
- Nouveau `lib/core/backup/google_profile.dart` : `GoogleProfile.fromIdToken` lit `given_name`/`family_name` (ou `name`) et `GoogleProfile.fromDisplayName` coupe un nom complet au premier espace. `GoogleSession` porte ce profil ; Android le remplit depuis `GoogleSignInAccount.displayName`, le flux de bureau depuis l'`id_token` (portée `profile` ajoutée).
- À la connexion, prénom et nom sont pré-remplis **sans écraser** une saisie existante, puis affichés dans l'étape Google en champs modifiables. Si les deux champs sont renseignés, l'étape d'identité manuelle est **sautée** ; sans connexion Google, elle reste demandée et validée comme avant.
- Les noms issus du profil sont enregistrés avec `google_linked` dès l'étape Google, donc l'étape sautée ne laisse aucun réglage vide.

**5. Invariants** : AES-256-GCM et PBKDF2 inchangés, aucun montant dans les notifications, masquage et rapport/PDF inchangés, argent de tiers et créances/dettes inchangés, cinq thèmes et barre basse non flottante non touchés, Home Lab toujours seul sans serveur maître.

**Tests** : `test/notification_style_test.dart` (bigText complet sans « … », bienvenue), `test/savings_animation_test.dart` (20 cauris pour 2 000 FCFA, aucun « × », 3 s, plafond fluide), `test/savings_vault_access_test.dart` (action Épargne → coffres, ouverture directe du segment), `test/onboarding_order_test.dart` (profil Google, Google avant le nom). `test/onboarding_pin_test.dart` adapté au nouvel ordre.

**Vérifications** : `dart format lib test` (125 fichiers, 0 changement), `flutter analyze` — **No issues found!**, `flutter test --reporter compact` — **194 tests passés**.

**Limites** : rendu réel des notifications, de la pluie de cauris et de l'écran Google non observé (aucun appareil connecté) ; un vrai compte Google reste nécessaire pour constater le pré-remplissage du prénom et du nom.

---

## Étape 32 — Retours terrain : son, réseau, suppression, démarrage, IA et PDF (25/11/2026) ✅

| Point | Livré |
| --- | --- |
| Son des cauris | `assets/audio/cauri_drop.wav` (WAV embarqué) + `lib/core/audio/cauri_sound.dart` : lecture à **chaque impact** (comptage dans la timeline, plan proportionnel au nombre de cauris (jusqu a 10 nuances)), volume `1.0`, préchargement après la première image, aucune erreur silencieuse. « Réduire les animations » coupe aussi le son. `audioplayers` déclaré et `assets/audio/` ajouté à `pubspec.yaml`. |
| Serveur de sauvegarde | Diagnostic Home Lab déjà branché (adresse normalisée, `GET` lecture seule, latence) ; `putRemote`/`fetchRemote` distinguent désormais **TLS (`HandshakeException`)**, `SocketException`, `TimeoutException` et erreur HTTP, avec messages explicites. |
| Suppression « Dernières transactions » | La ligne est retirée localement (`_hidden`) avant l'écriture SQLite, le `Dismissible` ne termine plus sa propre animation : plus d'assertion éphémère. Échec → ligne restaurée + un seul message clair ; exception journalisée (type + pile courte). « Annuler (5 s) » réécrit la ligne. |
| Démarrage ~1 s | La porte d'ouverture reste à `1 s` (`AkibaDurations.splash`) ; contrôle d'intégrité, photo, rappels, sauvegarde Home Lab, préchauffage des logos et son sont déplacés dans `addPostFrameCallback`. `main` ne garde que base, réglages, thème et verrou. |
| Assistant IA | Nouveau `lib/core/ai/ai_finance_context.dart` : résumé local (soldes, budgets, coffres, créances/dettes, derniers mouvements), **sans chiffre** en mode masqué. Une phrase sans montant devient une **question conseillée** (réponse affichée, aucune écriture). Une phrase avec montant reste un ordre JSON (`action` : expense / income / transfer / savings / third_party / debt), relu et confirmé ; un transfert écrit deux lignes symétriques. |
| PDF | Zoom tactile (`InteractiveViewer`, zoom tactile sans plafond fixe, déplacement une fois zoomé, bouton Réinitialiser) dans l'aperçu. La section du PDF devient **« Avis & analyse IA »** quand le modèle a répondu, sinon « Avis et conseils » (analyse locale déterministe). |

**Vérifications** : `dart format lib test` (0 changement), `flutter analyze` — **No issues found!**, `flutter test` — **197 tests passés** (dont `test/ai_finance_context_test.dart`).

**Limites** : son, zoom PDF et réponses IA non observés sur appareil ; le diagnostic réseau n'a pas été confronté à un vrai serveur Home Lab.


### Complément Étape 32 — détection IA et réponse de test

Le panneau IA sélectionne automatiquement le fournisseur lorsqu’une seule clé chiffrée est configurée et que le fournisseur courant n’en possède pas. En cas de plusieurs clés, le choix courant est conservé. Le test de connexion envoie une requête courte au modèle et affiche sa réponse dans le panneau; ce diagnostic ne consomme pas le quota quotidien. Vérification : `dart format` et `flutter analyze` réussis; cinq tests ciblés dans `test/ai_test_reply_test.dart` couvrent modèle, réponse et erreurs.

### Complément du 26/11/2026 — clé sans endpoint, réponse sous « Tester », zoom et son

| Point | Livré |
| --- | --- |
| Saisie de clé sans endpoint | Le champ d'adresse n'est plus demandé : `AiProviderSettings.baseUrl` résout l'endpoint par défaut du fournisseur en arrière-plan. L'adresse et le modèle restent disponibles dans « Réglages avancés (facultatif) », replié par défaut (`ExpansionTile` clé `ai-advanced-settings`). |
| Activation immédiate | `activateAiProviderWithKey` (dans `ai_provider.dart`) enregistre le fournisseur et passe `ai_remote_enabled` à vrai dès qu'une clé est enregistrée. L'assistant, les ordres et la génération de rapport/PDF relisent ces réglages à chaque appel : aucun redémarrage ni manipulation cachée. Le masquage et l'interrupteur restent prioritaires (aucun appel en mode masqué). |
| Réponse dans la carte du bouton | Nouveau `lib/features/assistant/ai_test_panel.dart`, inséré **juste sous le bouton « Tester »**, dans la même carte : titres « Réponse du modèle » / « Test de connexion », état « Test en cours… », réponse réelle ou erreur déjà catégorisée. Aucune URL, aucun corps brut, aucune clé. |
| Sélection du modèle testé | `selectAiTestModel` : premier modèle Gemini encore présent dans le catalogue frais selon la priorité ; modèle configuré pour les fournisseurs compatibles OpenAI. Le modèle soumis est bien celui de cette sélection (`test/ai_test_reply_test.dart`). |
| Erreurs réseau | `fetchAiTestReply` convertit tout échec en `AiFailureKind` (délai, réseau, clé refusée, quota, service, réponse illisible) ; `AiTestException.message` n'expose que la phrase utilisateur. |
| Zoom PDF | Nouveau `lib/core/widgets/pinch_zoom.dart` (`PinchZoom`, `AkibaZoom.maxScale = 50`, marge de déplacement 160 dp) utilisé par l'aperçu du rapport : zoom au pincement jusqu'à 50×, panoramique une fois agrandi, bouton Réinitialiser. |
| Équilibre sonore | `CauriSoundPlan` reste la source du son : densité (une note de plus tous les 4 cauris, plafond 10), cadence resserrée (`staggerFor`) et nuance progressive (0,72 → 1.0) avec alternance et accent final, sans saturation. `CauriDropAnimation` joue chaque note à son impact, hors mode « Réduire les animations ». |

**Tests ajoutés** : `test/cauri_sound_test.dart` (densité, cadence, nuances bornées, impacts dans la timeline, absence de répétition mécanique), `test/pinch_zoom_test.dart` (échelle maxi ≥ 20 et 50, panoramique), `test/ai_settings_ui_test.dart` (sélection automatique du fournisseur, activation immédiate, panneau de test, absence de champ endpoint replié).

**Vérifications** : `dart format lib test` propre, `flutter analyze` — **No issues found!**, tests ciblés — 38 passés, suite complète — **224 tests, tous passés**.

**Limites** : le pincement réel, l'audibilité du son et la réponse d'un vrai fournisseur n'ont pas été observés sur appareil.

---

## Étape 33 — Serveur multi-utilisateurs, liste des modèles IA et réponse serveur fiable (26/11/2026) ✅

### 1. Restauration serveur : fin du faux « Format de sauvegarde non reconnu »

| Cause trouvée | Correction |
| --- | --- |
| Le serveur historique répondait **204 sans corps** quand aucune sauvegarde n'existait ; seul `404` était traité comme « rien à restaurer ». Le corps vide partait ensuite vers l'analyse JSON, puis vers `_checkEnvelope`, d'où le message trompeur. | `fetchRemote` traite désormais `404`, `204` **et** un `200` au corps vide comme « Aucune sauvegarde » (`null`), sans aucune analyse. |
| `HttpClientRequest.write` encode en **latin1** quand le `Content-Type` n'a pas de charset : l'enveloppe (libellés accentués : tiers, catégories, réglages) partait en octets invalides, le serveur la recevait altérée et la rendait telle quelle. C'était la vraie corruption de format. | `putRemote` écrit `request.add(utf8.encode(jsonEncode(envelope)))`. L'enveloppe est identique à l'octet près à l'aller et au retour. |
| Une réponse proxy (page web, JSON enveloppé, chaîne JSON) produisait le même message générique. | Nouveau `BackupService.decodeRemoteBackup` : corps vide → `null`, chaîne JSON redécodée, enveloppe rangée sous `backup` / `envelope` / `latest` / `data` dépliée, page web et JSON étranger → message explicite (« page web », « n'a pas renvoyé une sauvegarde AKIBA »), jamais « format non reconnu ». |
| Le serveur renvoyait `octet-stream` et un fichier unique. | `GET /` et `/backup` renvoient l'enveloppe **brute** en `application/json`, `Cache-Control: no-store`, ou **404** motivé. |

`LocalRestorePage` reste limitée à l'adresse et au jeton, normalise l'URL, cherche puis restaure automatiquement, et distingue maintenant « aucune sauvegarde pour ce jeton » d'une vraie erreur.

### 2. `config_serveur/` — serveur multi-utilisateurs avec jetons dédiés

Le dossier existant a été inspecté puis remplacé/complété (l'ancien `latest_backup.bin` unique et la route multipart ont disparu) :

| Fichier | Contenu |
| --- | --- |
| `main.py` | FastAPI : `USER_TOKENS` au format `jeton:utilisateur,jeton2:utilisateur2` (repli `API_TOKEN` → utilisateur `default`), comparaison `secrets.compare_digest`, dossier par utilisateur `/data/backups/<utilisateur>/` avec `latest.json` + `history/` limité à 30 fichiers horodatés, écriture atomique, `GET/PUT /` et `/backup`, `GET /health` (utilisateur authentifié, présence et taille de la sauvegarde), `GET /ping` sans jeton pour le healthcheck, reprise automatique de l'ancien `latest_backup.bin` dans `default/latest.json`, validation `format == "akiba-backup"` en `PUT`. |
| `requirements.txt` | `fastapi==0.115.6`, `uvicorn==0.34.0` uniquement. |
| `Dockerfile` | `python:3.11-slim`, port 8080, `uvicorn --proxy-headers`. |
| `docker-compose.yml` | `restart: unless-stopped` (redémarrage après reboot), `8080:8080`, volume `/DATA/AppData/akiba-backup/data:/data`, `USER_TOKENS` commenté avec deux exemples, healthcheck `/ping`. |
| `README_INSTALLATION.md` | Placement des fichiers, génération d'un jeton par personne (`openssl rand -hex 32`), ajout d'un utilisateur, arborescence des dossiers, activation Docker au boot, tests `curl`, configuration dans AKIBA, dépannage. |
| `commandes_activation.txt` | Toutes les commandes d'activation dans l'ordre (mkdir, jetons, `systemctl enable docker`, `docker compose up -d --build`, `ufw allow 8080/tcp`, tests, vérification après `reboot`). |

### 3. Test IA : fin du « Le modèle a répondu hors format »

| Cause | Correction |
| --- | --- |
| `HttpClientRequest.write` en latin1 rendait le prompt accentué invalide côté fournisseur (le corps JSON était corrompu dès l'envoi). | UTF-8 explicite (`request.headers.contentType = ContentType.json` + `request.add(utf8.encode(...))`) dans `_send` **et** `fetchAiTestReply`. Corrige aussi tous les appels de l'assistant. |
| L'extraction ne lisait que `candidates[0].content.parts[].text` (Gemini) et `choices[0].message.content` (OpenAI). Les modèles à réflexion renvoient un `content` vide + `reasoning_content`, ou des parties `thought`, ou plusieurs candidats : tout cela finissait en « hors format ». | `extractAiText` tolérant : tous les candidats, parties `thought` ignorées, listes de parties, `reasoning_content` / `reasoning` / `text`, repli racine `text` / `output_text` / `response` / `content`. Un corps texte non JSON est accepté **pour le diagnostic seulement** (`allowPlainText`). Une réponse réellement vide reste une erreur catégorisée. |
| Limite de jetons trop basse pour les modèles à réflexion. | `generationConfig.maxOutputTokens` (Gemini) et `max_tokens` (OpenAI-compatible) à 1024, dont 1024 pour le diagnostic. |
| Le diagnostic pouvait être pris pour une consommation de quota. | Inchangé et vérifié : `fetchAiTestReply` ne reçoit aucun réglage et ne touche pas `AiQuota` (test dédié). |

### 4. Réglages IA : liste déroulante de tous les modèles accessibles

- La carte « Modèles et priorité » (cases à cocher + flèches) est remplacée par **« Modèle utilisé »** : un `DropdownButton` listant **tous** les modèles renvoyés par `models.list` du fournisseur avec la clé saisie (Gemini comme OpenAI-compatible), cache par fournisseur (`ai_models_cache_<fournisseur>`).
- Repli propre : avant le premier chargement, la liste contient le modèle configuré, le modèle par défaut et le cache existant ; le catalogue se charge automatiquement à l'ouverture si une clé est enregistrée, et via « Actualiser la liste ».
- Le modèle choisi est mémorisé (`ai_model_<fournisseur>`) et **c'est exactement lui** qui part dans `fetchAiTestReply`. Pour Gemini, il passe aussi en tête de `ai_model_priority` (cascade de secours conservée).
- La détection automatique du fournisseur à l'ouverture est conservée (une seule clé → ce fournisseur, plusieurs clés → choix courant) et charge désormais sa liste de modèles.

### 5. Sauvegarde automatique et HTTP local

Vérifié sans modification : `AutoBackupCoordinator` (anti-rebond 3 s, canaux indépendants Google Drive / serveur local, `auto_backup_pending_at`, reprise par minuteur et sur `AppLifecycleState.resumed` dans `main.dart`), `test/auto_backup_test.dart` (échec hors ligne puis reprise), et `android:usesCleartextTraffic="true"` présent dans `AndroidManifest.xml`.

### 6. Vérifications exécutées

`dart format lib test` propre · `flutter analyze` — **No issues found!** · `flutter test` — **241 tests, tous passés** (224 → 241, dont 17 nouveaux : `test/backup_server_decode_test.dart`, `test/ai_reply_parsing_test.dart`, liste déroulante dans `test/ai_settings_ui_test.dart`) · `python -m py_compile config_serveur/main.py` sans erreur.

**Limites** : aucun serveur CasaOS réel ni appareil Android joint pendant ce tour ; le conteneur n'a pas été construit (`docker build`) sur le poste ; la joignabilité d'une IP locale et le redémarrage réel après reboot restent à confirmer sur le serveur du porteur.

### 7. Jeton unique partagé, utilisateurs toujours séparés (26/11/2026)

- `SHARED_TOKEN` : **un seul jeton** pour tout le monde. Chaque personne écrit `JETON:son_nom` (ou `JETON/son_nom`) dans le champ « Jeton d'accès » d'AKIBA ; `authenticate` vérifie le jeton puis range la sauvegarde dans `data/backups/<nom>/`. Sans nom, tout va dans `default`.
- `USER_TOKENS` reste disponible et accepte les deux formes : `jeton:utilisateur` (jeton dédié, sans nom à saisir) et `jeton` seul (partagé). `API_TOKEN` sert de repli partagé. `GET /health` renvoie `shared_token`.
- `_same()` compare des octets UTF-8 : `secrets.compare_digest` lève `TypeError` sur du non-ASCII, ce qui donnait un 500 pour un nom accentué. `Amélie Durand` devient proprement `Am_lie_Durand`.
- Application inchangée fonctionnellement : seuls les textes d'aide du champ jeton (`features/onboarding/local_restore_page.dart`, `features/backup/backup_center.dart`) mentionnent `JETON:mon_nom`.
- Serveur réellement lancé (`SHARED_TOKEN=partage-test`, port 8098) : `/ping` 200 ; alice `404` avant `PUT`, puis enveloppe **identique octet pour octet** après ; bob `404` après le `PUT` d'alice ; jeton seul → `default` ; mauvais jeton `401` ; nom accentué accepté. Aucun fichier temporaire laissé (`config_serveur/` propre).
- Rappel de sécurité documenté : le jeton partagé donne accès à tous les dossiers (contenu toujours chiffré AES-256-GCM), d'où l'option des jetons dédiés.

### 8. 401 à la restauration et échecs du test IA expliqués (27/11/2026)

**401 « Lecture impossible »** — le code seul ne disait pas quoi corriger.

- `BackupService.fetchRemote` / `putRemote` lisent maintenant le corps de la réponse et reprennent le motif du serveur (`{"detail": …}`) : `Jeton manquant`, `Jeton invalide` ou `Aucun jeton configuré` s'affichent, avec la marche à suivre. Message dédié 401/403 : « Jeton refusé par le serveur… SHARED_TOKEN doit être identique et le conteneur recréé (`docker compose up -d`) ». Aucun jeton n'apparaît dans le message (`serverDetail`, borné, jamais un corps HTML).
- Cause réelle côté application : le centre de sauvegarde utilisait **seulement** le jeton du coffre, même quand la personne venait de coller le bon jeton dans le champ. `_currentLabToken()` préfère la saisie, `_requireLabToken()` explique l'absence de jeton au lieu d'un 401 sec.
- Cause réelle côté serveur : `docker restart` ne recharge pas les variables d'environnement. `clean_token()` ignore désormais les guillemets et espaces collés (`"jeton"`) et le nom peut être écrit `JETON : nom`. Les 401 du serveur portent un motif actionnable au lieu de « Jeton invalide. » seul.
- Vérifié sur serveur réel (`SHARED_TOKEN="jeton-test"` avec guillemets, port 8099) : sans jeton → 401 « Jeton manquant » ; mauvais jeton → 401 « Jeton invalide » + aide ; `"jeton-test":awa` et `jeton-test : awa` acceptés ; `awa` en 200 après `PUT`, `mamadou` en 404 → isolation intacte.

**Test IA : « n'a pas répondu à temps », puis « le service a renvoyé une erreur »**

- Gemini signale une **clé refusée par `400 API_KEY_INVALID`**, pas 401 : tout `400` était classé « réponse hors format », donc la vraie cause restait invisible. `aiErrorText()` lit `error.message`, `error.status` et `details[].reason`, et `AiHttpException.kind` en déduit `auth`, `quota`, `model` ou `server`. Nouvelle catégorie `AiFailureKind.model` (« modèle introuvable »).
- La clé part en en-tête `x-goog-api-key` (au lieu de `?key=`) : forme acceptée par les clés `AIza…` **et** par les nouvelles clés `AQ.…`, et la clé ne traîne plus dans l'URL ni dans les journaux réseau.
- Délai du diagnostic porté de 8 s à **40 s** (un modèle à réflexion dépassait 8 s → faux « délai dépassé »), avec un second essai unique sur 5xx.
- Le test ne condamne plus le modèle choisi : sur `model` ou `server`, les deux modèles suivants du catalogue sont essayés, celui qui répond est retenu et enregistré, et l'échec nomme les modèles testés.
- Modèles de départ mis à jour (`gemini-flash-latest`, `gemini-flash-lite-latest`, 2.5 Flash/Pro) : les versions 1.5 sont retirées et répondaient 404. Modèle Gemini par défaut : `gemini-flash-latest`.
- Vérifié par tests locaux (serveur HTTP réel en boucle locale) : `400 API_KEY_INVALID` → « clé refusée », `404` → « modèle introuvable », `429` → quota ; 46 tests ciblés passés, `flutter analyze` sans problème, `python -m py_compile` OK. La clé Gemini réelle et son quota n'ont pas été exercés ici.

### 9. Format de sortie de l'IA et avis réel dans le PDF (27/11/2026)

**Constat** : Gemini renvoyait un objet JSON (`{"conseil_financier": "…"}`) que
l'assistant affichait tel quel, accolades comprises. Le même JSON, réduit à une
seule ligne, faisait échouer `ReportAdvice.parse` (moins de deux lignes) : le
PDF retombait silencieusement sur l'avis local, donc jamais l'avis réel du
modèle.

| Correctif | Détail |
| --- | --- |
| `lib/core/ai/ai_text.dart` (nouveau) | `AiText.blocks` / `plain` / `lines` : décode un objet JSON (première valeur texte trouvée), une liste, des fences ``` et du Markdown, puis rend des paragraphes et des puces nettoyées (guillemets, puces, espaces insécables, titres `#`). |
| Assistant (`features/assistant/assistant_sheet.dart`) | La réponse passe par `AiText.plain` : plus d'accolades ni de guillemets JSON. Nouveau rendu `_AnswerText` (paragraphes aérés, puces avec pastille terracotta) et `_highlight` qui met les montants FCFA en gras. Une réponse vide affiche « Le modèle a répondu hors format… ». |
| Rapport (`core/report/monthly_report.dart`) | `ReportAdvice.parse` lit la réponse via `AiText.lines`, accepte `avis`/`conseils` en JSON, le Markdown et le texte libre ; un paragraphe unique est découpé aux phrases pour retrouver un verdict puis des conseils. |
| Consigne du rapport | Le prompt demande explicitement un objet JSON `{"avis": …, "conseils": […]}` (FR et EN). |
| Délai | `AiTask.analysis` passe de 10 s à 18 s pour laisser au modèle le temps de répondre avant le repli local. |

**Tests** : `test/ai_text_test.dart` (4 cas : JSON, fences, liste, Markdown),
`test/monthly_report_test.dart` (une réponse JSON du modèle arrive telle quelle
dans le PDF), `test/core_test.dart` (plage du délai d'analyse 8–20 s).

**Vérifications** : `dart format lib test` propre · `flutter analyze` — *No
issues found!* · `flutter test test/ai_text_test.dart test/monthly_report_test.dart
test/core_test.dart` — 65 tests passés · `flutter build apk --debug` —
`BUILD_EXIT=0`, APK installé (`adb install -r`) et application relancée sans
`FATAL` / `E/Flutter` dans logcat.

**Limites** : le rendu réel de la carte conseil et de la carte « Avis & analyse
IA » du PDF n'a pas été observé (aucune saisie synthétique dans l'application) ;
une réponse Gemini réelle n'a pas été rejouée.

### 10. Assistant : épargne récurrente et actions réellement exécutées (27/11/2026)

**Constat** : « je veux commencer à mettre 100 francs par jour de côté pour
pouvoir me payer un moniteur… » produisait une sortie de 100 FCFA en catégorie
« Alimentation ». Le montant était lu comme une dépense, sans coffre ni
projection : l'assistant ne « faisait » donc pas ce qui était demandé.

| Correctif | Détail |
| --- | --- |
| `AiCommandParser` | Nouveau plan d'épargne : un montant suivi de « par jour » / « chaque jour » / « tous les jours », avec un verbe d'épargne, produit un brouillon `isSavingsGoal`. Le montant quotidien est celui **juste avant** le rythme (pas le prix de l'objet cité plus loin). |
| Nom de l'objectif | Extrait de « me payer un moniteur » → `Moniteur`, en s'arrêtant au premier mot grammatical (« donc », « pour », « tu »…), jamais la phrase entière. |
| Premier versement | « demain » devient le lendemain à minuit (`occurredAt`) ; sans date, le jour même. |
| Priorité | `_analyse` applique cette lecture **locale avant tout modèle distant** : un modèle ne peut plus requalifier l'épargne en dépense, comme c'était déjà le cas pour les créances et dettes. |
| Carte dédiée | `_savingsGoalCard` : nom du coffre, prix de l'objectif, versement quotidien, date du premier versement, nombre de versements et date d'atteinte calculés en direct. Le bouton « Créer l'épargne » crée un `SavingsPot` de type `goal` et mémorise le rythme (`savings_plan_<id>`). Aucun débit n'est écrit. |
| Projection | `SavingsProjection.dateForDailyPlan` et `depositsFor` : rythme fixe, objectif déjà atteint, rythme nul et au-delà de dix ans traités sans fausse promesse. |
| Modèle distant | Action `savings_goal` ajoutée à la consigne JSON (`daily_amount`, `target`, `goal`) et relue par `_readRemote`. |

**Actions que l'assistant exécute** (toujours relues dans une carte, jamais à
l'aveugle) : dépense, entrée, transfert entre deux comptes (deux écritures
symétriques), argent de tiers isolé, créance / dette et leur règlement,
versement d'épargne, et désormais objectif d'épargne récurrent. Chaque action
passe par les services existants (`AkibaStore`), donc les invariants
(trésorerie, tiers, budgets, dettes) restent ceux du reste de l'application.

**Tests** : `test/savings_plan_test.dart` (phrase réelle de l'utilisateur,
montant quotidien, nom, « demain » ; versement unique et dépense ordinaire non
confondus ; projections).

**Limites** : aucun prélèvement automatique n'est créé (le premier versement
reste un geste volontaire) ; l'assistant n'automatise pas encore d'autres écrans
( budgets, réglages, thèmes) : il exécute les écritures financières listées ci-dessus.

### 11. Sauvegarde du serveur : code à 4 chiffres, sans compte Google (27/11/2026)

**Constat** : à la restauration depuis le serveur, AKIBA répondait « Cette
sauvegarde appartient au compte Google amahpaulin30@gmail.com : connectez ce
compte pour la restaurer. » Or le jeton du serveur est le seul lien attendu ;
imposer une connexion Google contredisait l'usage hors ligne.

| Correctif | Détail |
| --- | --- |
| `lib/core/backup/backup_code.dart` (nouveau) | `BackupCodeStore` (coffre système `akiba_backup_code`, version mémoire pour les tests), `isValidBackupCode` (exactement 4 chiffres), normalisation des espaces. |
| Enveloppe version 4 | `kdf: "PBKDF2-CODE"` + sel aléatoire de 16 octets, clé dérivée du code (PBKDF2-SHA256, 120 000 tours) ; aucun champ `account`, le code n'est jamais écrit. |
| Compatibilité | Les enveloppes `device-key` (v2) et Google (v3) restent lisibles par leurs chemins respectifs : une ancienne sauvegarde Drive continue de demander le compte, une ancienne sauvegarde locale sa clé d'appareil. |
| Configuration | Le centre de sauvegarde Home Lab demande le code à l'étape 2 ; `HomeLabSetup.activateToken` refuse un jeton valide sans code, protège le code dans le coffre et l'utilise pour la première sauvegarde. La sauvegarde automatique au démarrage lit le même code. |
| Restauration | La page d'onboarding et le centre de sauvegarde demandent le code ; un dialogue dédié dans « Restaurer » préremplit le code du coffre. Code absent → message `codeRequired` ; code faux → message `codeWrong` (« Code à 4 chiffres incorrect… créez une nouvelle sauvegarde avec un nouveau code… repartirez de zéro »). |
| Oubli | Aucun chemin de récupération : une nouvelle sauvegarde avec un nouveau code remplace `latest.json` sur le serveur (historique conservé mais illisible). C'est le comportement demandé. |

**Tests** : `test/backup_code_test.dart` (version 4, absence de compte et de
code en clair, réouverture avec le même code, code absent, code faux, longueur
invalide, compatibilité `device-key` et Google) ; `test/home_lab_setup_test.dart`
(code obligatoire, code conservé hors réglages) ; parcours d'onboarding inchangé.

**Limites** : le code n'a que 10 000 valeurs ; il protège d'une lecture
accidentelle, pas d'un attaquant qui détiendrait le fichier et beaucoup de temps
de calcul (voir `REVUE_SECURITE.md`). Le parcours réel sur téléphone contre le
serveur du porteur (configuration, restauration, code oublié) reste à rejouer.
