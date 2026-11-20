# Cahier des charges AKIBA

Version 2.0 · 19 novembre 2026 · Application de gestion financière personnelle · Flutter (Android et Windows) · SQLite local-first · Devise FCFA (XOF) · Statut : refonte complète pour validation

## 0. Synthèse de la refonte

Ce document remplace la version 1.2. Il conserve le périmètre métier et la palette AKIBA, adopte le style de la maquette de référence (thème clair chaleureux, carte de solde terre cuite à motif triangles, tuiles arrondies, histogrammes, ventilation par catégorie, liste de transactions), puis détaille l’onboarding écran par écran, toutes les pages, toutes les fonctionnalités pas à pas, et un écran Paramètres entièrement présenté en mosaïque.

### Améliorations et corrections clés

1. **Style** : thème clair par défaut (maquette), thème sombre AKIBA conservé en option. Le code couleur du brief `#0E0DOC` (lettre O) est corrigé en `#0E0D0C`.
2. **Navigation** : passage de « 4 onglets + menu Plus » à 5 emplacements alignés sur la maquette (Accueil, Analyses, bouton Akiba central, Portefeuille, Profil). Tous les modules restent à deux touchers maximum de l’accueil.
3. **Paramètres** : la liste de réglages devient une mosaïque de tuiles de tailles variables (2 colonnes sur mobile, 4 sur PC).
4. **Solde** : la v1.2 définissait le « total personnel » de deux façons contradictoires (somme des comptes, ou somme moins l’argent de tiers). Désormais : Total des comptes, Argent de tiers, **Solde disponible = comptes − tiers**. Le grand chiffre de l’accueil est le Solde disponible.
5. **Épargne** : la v1.2 ne disait pas si l’épargne sortait des comptes. Désormais un versement est un transfert du compte vers le **Coffre épargne** interne ; un retrait est le transfert inverse. Les soldes restent toujours déduits des transactions.
6. **Exemple faux corrigé** : « objectif atteint le 15 août » avec 2 000 FCFA par semaine et 30 000 FCFA restants était incohérent. Au 19 novembre 2026, la date correcte est le **4 mars 2027** (15 semaines).
7. **Connexion Google** : imposée avant tout usage en v1.2, ce qui contredit le local-first. Elle devient optionnelle à l’onboarding (nécessaire seulement pour Drive, e-mail du bilan et jeton de synchronisation). L’onboarding saisit prénom et nom.
8. **SMS** : le module ne parlait que de Flooz ; il devient générique par opérateur (Mixx by Yas inclus).
9. **Besoins priorisés** : la frontière « payable bientôt » / « hors de portée » n’était pas définie ; un seuil explicite est ajouté.
10. **Jauges** : bornes précisées (vert < 80 %, orange de 80 % à 100 %, rouge > 100 %).
11. **Ajouts** : états de chaque écran, critères d’acceptation testables, raccourcis Windows, index SQL, endpoints API, 30 scénarios de recette, tuile « Zone sensible ».

## 1. Présentation du projet

### 1.1 Contexte

Le porteur du projet gère ses finances personnelles et une partie de la trésorerie de tiers (clients) au quotidien, en FCFA, entre argent liquide, monnaie mobile (Flooz, Mixx by Yas) et compte bancaire. Aucun outil existant ne combine : saisie ultra-rapide, budget récurrent, épargne par objectifs, lecture des SMS de dépôt, séparation stricte de l’argent des tiers, assistant IA et maîtrise des données via un serveur personnel.

### 1.2 Objectifs mesurables

- Saisir une opération en moins de 10 secondes (formulaire, SMS ou phrase libre), 3 touches maximum pour une sortie.
- Connaître à tout instant le solde par support et le Solde disponible, avec l’argent de tiers isolé.
- Planifier un budget mensuel récurrent et prioriser les besoins selon le disponible.
- Épargner régulièrement : objectifs, fonds d’urgence, dates d’atteinte dynamiques.
- Rester propriétaire des données : SQLite local, serveur maître, sauvegarde chiffrée Drive et Home Lab Backup.
- Arriver au tableau de bord en moins de 2 minutes à la première ouverture.

### 1.3 Périmètre

**Inclus** : application Flutter Android et Windows ; multi-comptes (Liquide, Flooz, Mixx by Yas, Banque) ; IA Gemini (saisie libre texte et voix, conseils, bilan) ; lecture des SMS Android ; synchronisation avec le serveur maître ; sauvegarde chiffrée Google Drive ; Home Lab Backup ; mode simulation.

**Exclu de la v1** : iOS et macOS, open banking, paiements réels, multi-utilisateurs, comptabilité professionnelle (TVA, factures).

### 1.4 Utilisateur cible

Utilisateur unique, francophone, technophile, basé au Togo, avec un smartphone Android et un PC Windows, un serveur domestique (Docker / CasaOS) et un VPN WireGuard. Interface en français ; montants en FCFA sans décimales avec espace comme séparateur de milliers (`15 000 FCFA`) ; dates `jj/mm/aaaa` ; fuseau Africa/Lome (UTC+0).

### 1.5 Glossaire

| Terme | Définition |
| --- | --- |
| Transaction neutre | Argent qui transite par les comptes sans appartenir à l’utilisateur (client, avance, paiement pour autrui). Exclue du budget, de l’épargne, des statistiques et du bilan personnels. |
| Argent de tiers | Σ entrées neutres non soldées − reversements. |
| Solde disponible | Total des comptes − argent de tiers (« réellement à moi »). |
| Coffre épargne | Portefeuille interne regroupant fonds d’urgence, objectifs et épargne libre. |
| Créance / Dette | Créance : on me doit. Dette : je dois. |
| Serveur maître | Serveur personnel hébergeant la base de référence et l’API de synchronisation. |
| Home Lab Backup | Sauvegarde chiffrée vers le serveur personnel sur le Wi-Fi domestique, sans VPN. |
| LWW | Last-Write-Wins : la modification la plus récente l’emporte. |
| Tuile | Bloc rectangulaire arrondi de la mosaïque Paramètres (1×1, 2×1 ou 2×2). |

### 1.6 Modules et priorités (MoSCoW)

| Module | Intitulé | Priorité |
| --- | --- | --- |
| M01 | Onboarding, identité, connexion Google optionnelle | Must |
| M02 | PIN local et biométrie | Must |
| M03 | Accueil et masquage des montants | Must |
| M04 | Entrées d’argent | Must |
| M05 | Sorties d’argent | Must |
| M06 | Sources et catégories paramétrables | Must |
| M07 | Budget mensuel récurrent | Must |
| M08 | Besoins priorisés | Must |
| M09 | Épargne : proposition, versement, retrait | Must |
| M10 | Objectifs d’épargne | Must |
| M11 | Fonds d’urgence et simulation de coup dur | Should |
| M12 | Saisie libre IA (texte et voix) | Should |
| M13 | Extraction SMS (tous opérateurs configurés) | Should |
| M14 | Argent de tiers (transactions neutres) | Must |
| M15 | On me doit / Je dois | Should |
| M16 | Analyses : calendrier et graphiques | Should |
| M17 | Bilan mensuel et conseils IA | Should |
| M18 | Notifications et rappels | Must |
| M19 | Sauvegarde chiffrée Google Drive | Must |
| M20 | Synchronisation serveur maître | Must |
| M21 | Mode simulation | Could |
| M22 | Home Lab Backup | Should |
| M23 | Profil et Paramètres en mosaïque (nouveau) | Must |

## 2. Direction artistique et design system

### 2.1 Principes issus de la maquette de référence

- **Lisibilité d’abord** : un seul grand montant par écran, entouré d’espace.
- **Carte de solde héroïne** : bloc terre cuite en dégradé, bordé en haut et en bas d’une frise de triangles AKIBA, avec deux boutons d’action intégrés (Transférer : ocre ; Ajouter : blanc).
- **Blocs de conseils IA** : cartes blanches courtes avec icône en tuile, une phrase titre et une phrase d’explication dont le chiffre clé est coloré.
- **Grille d’actions rapides** : 4 tuiles d’icônes avec libellé.
- **Histogramme** : barres à double tonalité (valeur réelle et plafond ou budget), jours en abscisse, légende « Courant ».
- **Ventilation par catégorie** : ligne libellé, montant, pourcentage, barre de progression arrondie.
- **Transactions** : avatar de catégorie arrondi, libellé, catégorie et heure en sous-titre, montant aligné à droite (rouge-terre pour sortie, vert pour entrée).
- **Segmented control** pilule pour changer de période ou de sous-vue ; barre d’onglets flottante arrondie avec indicateur terre cuite sur l’onglet actif.
- **Zéro bordure** : le relief vient de l’écart de teinte et d’ombres très douces (thème clair).

### 2.2 Tokens thème clair (défaut)

| Jeton | Valeur | Usage |
| --- | --- | --- |
| Fond | `#FAF4E6` | Fond d’application (crème) |
| Surface | `#FFFFFF` | Cartes, listes, barre d’onglets |
| Surface élevée | `#F3E9D6` | Champs, puces non sélectionnées, blocs d’indicateurs (Revenus, Budget) |
| Tuile icône | `#F1DFC8` | Fond des icônes de catégories et d’actions |
| Terre cuite | `#C7673D` | Action principale, onglet actif, alertes |
| Terre cuite profonde | `#9E4B27` | Fin du dégradé de la carte de solde (dérivé de la maquette) |
| Ocre | `#C69F47` | Boutons secondaires, jauges neutres, accents |
| Sable | `#E8D5A8` | Montants sur surfaces sombres ou terre cuite, valeurs clés |
| Texte principal | `#1A1816` | Titres, montants |
| Texte atténué | `#6F685B` | Sous-titres, aides, libellés |
| Texte sur terre cuite | `#FFF8EC` | Texte sur la carte de solde |
| Vert / Orange / Rouge | `#5E9E6E` / `#E0963A` / `#C94B3F` | Succès, avertissement, erreur et jauges |

Règle de contraste : texte courant ≥ 4,5:1 ; sur la carte terre cuite, tout texte de moins de 18 pt est en gras et sur la partie profonde du dégradé.

### 2.3 Tokens thème sombre (option)

| Jeton | Valeur |
| --- | --- |
| Noir profond (fond) | `#0E0D0C` |
| Surface | `#1A1816` |
| Surface élevée | `#24211E` |
| Texte clair / atténué | `#F3EEE2` / `#A59E90` |
| Sable, Ocre, Terre cuite | `#E8D5A8`, `#C69F47`, `#C7673D` |
| Sémantique | `#5E9E6E`, `#E0963A`, `#C94B3F` |

En sombre, aucune ombre : relief par la teinte uniquement. Le choix Clair / Sombre / Système est dans la tuile Apparence.

### 2.4 Typographie

Polices : **Poppins** pour titres et corps (identité du logo), **Inter** avec chiffres tabulaires (`FontFeature.tabularFigures`) pour tous les montants, pourcentages et heures afin d’aligner les colonnes.

| Style | Taille / graisse | Usage |
| --- | --- | --- |
| Montant héros | 36 pt / 700 | Solde de la carte principale |
| Montant section | 26 pt / 700 | Total dépensé, solde d’un compte |
| Titre d’écran | 22 pt / 700 | En-têtes |
| Titre de section | 17 pt / 600 | « Aperçu IA », « Transactions » |
| Montant de ligne | 15 pt / 600 | Lignes de liste |
| Corps | 14 pt / 400 | Texte courant |
| Légende | 12 pt / 400 | Sous-titres de lignes |
| Étiquette | 11 pt / 600 majuscules espacées | Libellés de champs |

Le texte s’adapte au réglage de taille du système jusqu’à 200 % ; les montants réduisent leur corps par paliers plutôt que de se tronquer.

### 2.5 Espacements, rayons, élévations

- Échelle d’espacement : 4, 8, 12, 16, 20, 24, 32 dp. Marge d’écran 20 dp ; entre blocs 24 dp ; entre éléments liés 12 dp.
- Rayons : carte de solde 28 dp ; cartes et feuilles 24 dp ; **tuiles de mosaïque 24 dp** ; icônes en tuile 14 dp ; champs 16 dp ; boutons, puces, segmented control, barre d’onglets : forme pilule.
- Élévation clair : `0 8 24 rgba(26,24,22,0.06)` sur les cartes ; la carte de solde `0 12 28 rgba(158,75,39,0.28)`. Aucun contour.
- Zones tactiles ≥ 48 dp ; bouton Akiba 64 dp.

### 2.6 Composants

| Composant | Spécification |
| --- | --- |
| BalanceCard | Dégradé 135° `#C7673D` → `#9E4B27`, frise de triangles `#E8D5A8` à 35 % en haut et en bas (jamais derrière un texte), libellé 13 pt, montant héros, pastille de variation en haut à droite (« +2,4 % »), deux boutons pilule 48 dp. |
| ActionPill | Pilule 48 dp, icône 20 dp + libellé 14 pt/600 ; variantes ocre, blanche, terre cuite. |
| AIInsightCard | Carte blanche 24 dp, tuile icône 40 dp, titre 15 pt/600, texte 13 pt, chiffre clé en ocre ou terre cuite. Maximum 5 lignes. |
| QuickActionTile | Tuile blanche 64 dp, icône 24 dp, libellé 12 pt dessous. |
| TransactionRow | Avatar 44 dp, titre 15 pt/600, sous-titre 12 pt atténué (catégorie · heure), montant aligné à droite. 12 dp entre lignes, pas de filet. |
| BarChart | 7 à 31 barres arrondies en haut, tonalité claire = plafond (budget quotidien), tonalité foncée = dépensé ; barre du jour en terre cuite ; toucher = infobulle du montant. |
| BreakdownRow | Libellé, montant, pourcentage, barre arrondie de la couleur de la catégorie. |
| SegmentedControl | Pilule sur surface élevée, segment actif terre cuite, texte blanc. |
| TabBar | Barre flottante blanche, rayon pilule, marge 12 dp du bord ; onglet actif : icône et libellé terre cuite. |
| MosaicTile | Voir chapitre 6. |
| StatusPill | Pastille pleine 8 dp + texte coloré (jamais de contour). |
| Chip | Pilule 40 dp ; sélectionnée : terre cuite et texte blanc ; sinon surface élevée. |

### 2.7 Motifs et mouvement

- Frise triangles ocre et terre cuite : cartes héros, états vides, écran de lancement.
- Cauri : icône de l’épargne et animation du bouton central.
- Durées : transitions de page 250 ms (courbe standard), feuilles modales 300 ms, cauri qui tombe 400 ms, flottement au repos 3 s (désactivable).
- Si l’utilisateur réduit les animations : fondu de 150 ms et aucune animation de flottement.

### 2.8 Accessibilité

Contraste AA minimum ; libellés de lecteur d’écran sur chaque icône et chaque montant (« 15 000 francs CFA, sortie, transport ») ; navigation complète au clavier sous Windows (Tab, Maj+Tab, Entrée, Échap) avec focus visible de 2 dp en terre cuite ; la couleur ne porte jamais seule l’information (pourcentage écrit, icône ou libellé).

## 3. Navigation et arborescence

### 3.1 Barre d’onglets (Android)

| Position | Onglet | Contenu principal |
| --- | --- | --- |
| 1 | Accueil | Carte de solde, aperçu IA, actions rapides, dernières transactions |
| 2 | Analyses | Segments : Statistiques · Budget · Besoins · Bilans |
| 3 (centre) | Bouton Akiba | Toucher : saisie rapide ; appui long : assistant IA vocal |
| 4 | Portefeuille | Segments : Comptes · Mouvements · Épargne · Tiers et dettes |
| 5 | Profil | Mosaïque Paramètres |

### 3.2 Windows

Rail latéral gauche fixe : logo, Accueil, Analyses, Portefeuille, Profil, bouton Ajouter (Ctrl+N), pastille de synchronisation en bas. Au-delà de 900 px : deux colonnes (liste à gauche, détail ou saisie à droite). Au-delà de 1 280 px : panneau de saisie rapide permanent à droite de l’accueil.

| Action | Android | Windows |
| --- | --- | --- |
| Masquer les montants | Œil dans la barre du haut | Ctrl+M |
| Saisie rapide | Bouton Akiba | Ctrl+N |
| Assistant IA | Appui long sur Akiba | Ctrl+I |
| Recherche | Icône loupe | Ctrl+K |
| Supprimer / modifier | Glisser gauche / droite | Suppr / Entrée ; clic droit : menu |
| Retour | Geste retour | Échap ou bouton retour |

### 3.3 Arborescence complète

- **Accueil** : détail d’un compte, aperçu IA, classement SMS (feuille), épargne proposée (feuille)
- **Analyses** : Statistiques (semaine, mois, année, tout) · Budget (lignes, ajout) · Besoins (ajout, détail du calcul) · Bilans (liste, détail, export)
- **Portefeuille** : Comptes (détail, transfert) · Mouvements (liste, calendrier, détail, reclassement) · Épargne (objectifs, création, versement, retrait, accélération, fonds d’urgence, simulation, statistiques d’épargne) · Tiers et dettes (argent de tiers, reversement, créances, dettes)
- **Profil** : mosaïque et sous-écrans (chapitre 6)
- **Transversal** : verrouillage, assistant IA, saisie rapide, bandeau Mode simulation, pastille de synchronisation

## 4. Onboarding écran par écran

Parcours de 11 écrans, barre de progression en points en haut, bouton Retour sur chaque écran sauf le premier, lien « Plus tard » sur les écrans optionnels. Les réponses sont enregistrées à chaque écran : fermer l’app puis la rouvrir reprend à l’écran en cours. Le parcours est rejouable depuis la tuile « Rejouer l’accueil » du Profil.

### E1. Lancement et langue

- **Objectif** : première impression et choix de langue.
- **Contenu** : fond crème, logo Akiba (tirelire et cauri) qui reçoit le cauri (animation 1,2 s), frise de triangles en haut et en bas, mot AKIBA, accroche « Votre argent, clair et à vous ». Sélecteur de langue pilule : Français (seule langue v1).
- **Actions** : « Commencer » (terre cuite) ; « J’ai déjà une sauvegarde » (ouvre la restauration, voir E10).
- **Validation / erreurs** : aucune. Si la base locale existe déjà, l’écran est sauté et l’app va au verrouillage.
- **Passage** : toucher « Commencer ».

### E2. Valeur perçue (3 cartes balayables)

- **Objectif** : montrer la promesse en 20 secondes.
- **Contenu** : carte 1 « Tout votre argent, un seul coup d’œil » (aperçu de la carte de solde) ; carte 2 « Saisissez en 10 secondes » (aperçu de la saisie rapide et de la voix) ; carte 3 « L’argent des autres reste à part » (aperçu Argent de tiers).
- **Actions** : balayer, « Suivant », « Ignorer » (saute à E3).
- **Validation / erreurs** : aucune ; hors ligne sans effet (contenu embarqué).
- **Passage** : dernière carte puis « Suivant », ou « Ignorer ».

### E3. Identité

- **Objectif** : personnaliser l’app (« Bonjour Paulin »).
- **Contenu** : champs Prénom et Nom (surface élevée, rayon 16), aperçu en direct « Bonjour \[prénom\] ».
- **Actions** : « Continuer ».
- **Validation** : prénom et nom obligatoires, 2 à 40 caractères chacun, lettres, espaces, tirets et apostrophes autorisés ; espaces de début et de fin supprimés ; première lettre mise en majuscule à l’affichage. Message sous le champ : « Le prénom est requis ».
- **Hors ligne** : sans effet.
- **Passage** : les deux champs valides. **Le dashboard n’est jamais accessible sans cet écran.**

### E4. Devise et fuseau

- **Objectif** : fixer les formats.
- **Contenu** : carte « FCFA (XOF) » présélectionnée avec exemple `15 000 FCFA` ; fuseau « Africa/Lome (UTC+0) » ; premier jour de semaine (lundi par défaut) ; jour de début de mois budgétaire (1 par défaut).
- **Actions** : « Continuer » ; « Modifier » ouvre la liste (XOF, XAF, EUR, USD en consultation seulement ; seul XOF actif en v1).
- **Validation** : choix obligatoire (déjà fait par défaut).
- **Passage** : toucher « Continuer ».

### E5. Comptes et soldes de départ

- **Objectif** : créer les comptes initiaux.
- **Contenu** : quatre tuiles : Liquide, Flooz, Mixx by Yas, Banque, chacune avec un interrupteur « Activer » et un champ « Solde de départ (FCFA) » à pavé numérique ; total des comptes en direct en bas. Lien « Ajouter un autre compte ».
- **Actions** : « Continuer » ; « Je n’en ai pas » désactive la tuile.
- **Validation** : au moins un compte actif ; solde entier ≥ 0 jusqu’à 999 999 999 ; un champ vide vaut 0 ; nom de compte personnalisé unique.
- **Passage** : au moins un compte actif et valeurs valides. Les soldes sont enregistrés comme transactions d’ouverture, pas comme valeurs brutes.

### E6. Sécurité : PIN et biométrie

- **Objectif** : protéger l’app.
- **Contenu** : création du PIN (4 à 6 chiffres) avec pavé numérique, confirmation du PIN, puis carte « Activer l’empreinte / le visage » (Windows Hello sur PC).
- **Actions** : « Créer mon PIN » ; « Activer la biométrie » ; « Plus tard » pour la biométrie uniquement (le PIN est obligatoire).
- **Validation** : refus des PIN triviaux (0000, 1234, suites, répétitions) avec message ; les deux saisies doivent correspondre ; le PIN est stocké en hash salé (Keystore / DPAPI).
- **Erreurs** : biométrie indisponible, la carte est masquée ; échec de la biométrie, repli sur le PIN.
- **Passage** : PIN créé et confirmé.

### E7. Compte Google (optionnel)

- **Objectif** : brancher Drive, e-mail du bilan, synchronisation.
- **Contenu** : bouton « Continuer avec Google » ; liste de ce que cela débloque (sauvegarde Drive chiffrée, bilan par e-mail, synchro PC et téléphone) ; lien « Plus tard, rester en local ».
- **Actions** : connexion OAuth ; « Plus tard ».
- **Validation / erreurs** : hors ligne, message « Connexion impossible sans internet, vous pourrez la faire plus tard dans Profil > Données » et bouton « Continuer en local » ; annulation de la fenêtre Google : retour à E7 sans erreur.
- **Passage** : connecté ou « Plus tard ».

### E8. Permissions avec pédagogie

- **Objectif** : demander chaque permission au bon moment, avec explication.
- **Contenu** : 4 cartes, chacune avec icône, bénéfice et bouton « Activer » ou « Plus tard » : Notifications (rappels), SMS (Android seulement : détection automatique des dépôts, seuls les expéditeurs financiers configurés sont lus), Micro (saisie vocale), Wi-Fi proche / localisation (reconnaître le Wi-Fi domestique pour Home Lab Backup).
- **Actions** : « Activer » ouvre la boîte système après un écran d’explication ; « Plus tard » ne bloque rien.
- **Validation / erreurs** : refus : la carte affiche « Désactivé » et un lien vers les réglages système ; SMS non proposé sur Windows ; message d’aide sur l’optimisation de batterie (Android) si activé.
- **Passage** : toucher « Continuer » (aucune permission n’est obligatoire).

### E9. Habitudes d’épargne et de budget

- **Objectif** : préconfigurer l’épargne.
- **Contenu** : curseur « Taux d’épargne proposé » (0 à 30 %, 10 % par défaut) avec exemple « Pour 15 000 FCFA reçus, nous proposerons 1 500 FCFA » ; champ « Réserve de sécurité » pour le calcul des besoins (0 par défaut) ; case « Je veux saisir mes charges fixes maintenant » (ouvre un mini formulaire loyer, transport, abonnements).
- **Actions** : « Continuer » ; « Plus tard ».
- **Validation** : taux entier 0 à 30 ; réserve ≥ 0.
- **Passage** : toucher « Continuer » ou « Plus tard ».

### E10. Données réelles ou simulation, sauvegarde

- **Objectif** : choisir comment démarrer.
- **Contenu** : deux grandes cartes : « Mes vraies données » (présélectionnée) et « Essayer avec des données fictives » (mode simulation, base isolée) ; en dessous, trois lignes à interrupteur « Sauvegarde Google Drive » (désactivée si non connecté), « Home Lab Backup », « Synchronisation » avec lien « Configurer plus tard » ; option « Restaurer depuis une sauvegarde ».
- **Actions** : « Terminer » ; choisir la simulation affiche le bandeau « Mode simulation » partout.
- **Validation / erreurs** : les options de données exigent la configuration complète (phrase secrète, voir F19) ; sinon l’interrupteur reste éteint avec message « À configurer dans Profil > Données ».
- **Passage** : une carte de démarrage sélectionnée.

### E11. Prêt

- **Objectif** : conclure et guider.
- **Contenu** : le cauri tombe dans la tirelire, « Bienvenue \[prénom\] », récapitulatif en 3 lignes (comptes créés, PIN actif, sauvegardes à configurer). Bouton « Voir mon tableau de bord ».
- **Actions** : « Voir mon tableau de bord » ; lien « Faire la visite guidée (30 s) ».
- **Après** : visite guidée en 4 bulles (carte de solde, bouton Akiba, onglet Analyses, onglet Profil), ignorable ; le premier lancement de la saisie rapide montre une infobulle « Touchez pour ajouter, maintenez pour parler ».
- **Critère de passage** : accès au dashboard ; durée totale visée inférieure à 2 minutes.
