# RESTE_A_FAIRE — Feuille de route AKIBA

Dernière mise à jour : **20/11/2026** · Référence : `Cahier des charges AKIBA.md`
v2.0 + `akiba_animations_notifications_regles..txt`.

Légende : ✅ fait · 🚧 en cours · ⬜ à faire · 🔒 dépend d'une décision ou d'un accès externe.

> État au 20/11/2026 : les Étapes 1.1 → 1.3 puis 4 → 12 sont livrées et
> documentées ; la Phase 9 (release) est préparée mais **non compilée** faute de
> mode développeur Windows sur le poste. Les règles du module IA et du module
> Créances et dettes sont formalisées dans
> `akiba_spec/regles_modules_ia_et_dettes.md` ; celles de la photo de profil, du
> quota IA, de Google Drive et du Home Lab dans
> `akiba_spec/regles_profil_ia_et_sauvegardes.md`.

Chaque phase se termine par : les vérifications listées, une mise à jour de
`DEJA_FAIT.md`, et, si la sécurité est concernée, de `REVUE_SECURITE.md`.

> **Découpage Phase 1** : les Étapes 1.2 et 1.3 ont été livrées à la demande du
> porteur (base chiffrée puis écran d'accueil). La numérotation d'origine
> (1.2 composants, 1.3 graphiques, 1.4 masquage) est donc décalée : les
> composants de l'accueil sont faits, les graphiques et le masquage persistant
> restent à faire.

---

## Phase 1 — Socle : design system, données locales et accueil

| Étape | Contenu | Modules | État |
| --- | --- | --- | --- |
| 1.1 | Tokens clair/sombre, typographie, format FCFA + masquage, barre basse pleine largeur (4 onglets), bouton cochon à droite + icône IA au-dessus, composants logo + nom Liquide/Flooz/Mixx by Yas/Orabank | M03, M23 (socle) | ✅ |
| 1.2 | Base SQLite locale chiffrée (SQLCipher AES-256, clé en Keystore/DPAPI), schéma versionné et indexé, modèles comptes / transactions / épargne / tiers / créances-dettes, soldes toujours dérivés, calcul du solde disponible vs argent de tiers | M06, M14 (socle) | ✅ |
| 1.3 | Écran Accueil : solde disponible en FCFA, séparation de l'argent de tiers, masquage des montants de l'accueil, aperçu IA (coquille), actions rapides, dernières transactions, carte héros à frise, états vide/chargement/erreur, responsivité mobile et grand écran | M03 | ✅ |
| 1.4 | `SegmentedControl`, `BarChart` (7→31 barres, double tonalité), `BreakdownRow`, `MosaicTile` (1×1, 2×1, 2×2), états vides à frise réutilisables | M16, M23 | ⬜ |
| 1.5 | Masquage persistant : préférence enregistrée, propagation à tous les écrans et animations (l'accueil est déjà couvert) | M03 | ✅ |
| 1.6 | Polices Poppins + Inter embarquées, adaptation au réglage texte système jusqu'à 200 %, montants qui réduisent leur corps sans troncature | — | ⬜ |
| 1.7 | Windows : rail latéral (logo, Accueil, Analyses, Portefeuille, Profil, Ajouter, pastille synchro), raccourcis Ctrl+M / Ctrl+N / Ctrl+I / Ctrl+K, focus visible 2 dp, ≥ 900 px deux colonnes, ≥ 1 280 px panneau de saisie permanent | M03 | ⬜ |

**Vérifications de phase** : `flutter analyze` à 0, `flutter test` vert, contrôle
visuel clair + sombre sur 360 px et 1 280 px, ouverture réelle de la base
chiffrée sur Android et Windows.

---

## Phase 2 — Sécurité d'accès et apparence

| Étape | Contenu | Modules | État |
| --- | --- | --- | --- |
| 2.1 | PIN 4→6 chiffres : hash salé en Keystore / DPAPI, refus des PIN triviaux, verrouillage au retour d'arrière-plan, dérivation de la clé de base depuis le PIN. **Fait :** empreinte SHA-256 salée 20 000 tours dans la base chiffrée, refus des PIN triviaux, `LockGate` sur pause. **Reste :** dérivation de la clé de base | M02 | 🚧 |
| 2.2 | Biométrie / Windows Hello, repli PIN systématique, limitation des essais. **Fait :** `local_auth` avec repli PIN. **Reste :** limitation du nombre d'essais, vérification sur appareil | M02 | 🚧 |
| 2.3 | Apparence : **cinq thèmes persistants** (Blanc par défaut, Sombre, Bleu, Vert, Jaune Or) avec aperçu immédiat et contraste vérifié + « Réduire les animations » | M23 | ✅ |
| 2.4 | Robustesse du stockage : rotation de la clé de base, message clair si le Keystore/DPAPI est indisponible, test d'ouverture sur appareil | M02, M06 | ⬜ |

**Vérifications** : tests d'intégrité des soldes, tests de migration, ouverture
refusée sans clé, analyse de sécurité documentée dans `REVUE_SECURITE.md`.

---

## Phase 3 — Onboarding (11 écrans)

| Étape | Contenu | Modules | État |
| --- | --- | --- | --- |
| 3.1 | Ossature du parcours : 11 étapes, barre de progression en points, reprise à l'écran en cours, retour sauf E1 | M01 | ✅ |
| 3.2 | E1 Lancement (emblème + cauri 1,2 s, frise), E2 Valeur perçue (3 cartes) | M01 | ✅ |
| 3.3 | E3 Identité (prénom/nom, validation 2→40 caractères), E4 Devise et fuseau (XOF, Africa/Lome) | M01 | ✅ |
| 3.4 | E5 Comptes et soldes de départ (4 tuiles + logos, total en direct, soldes d'ouverture en transactions) | M01, M06 | ✅ |
| 3.5 | E6 PIN + biométrie, E7 Google optionnel (OAuth, hors ligne géré). **Fait :** PIN + biométrie, bouton « Se connecter avec Google » avec flux PKCE prêt, repli dossier Drive. **Reste :** identifiants OAuth du porteur et essai réel de connexion | M01, M02 | 🚧 |
| 3.6 | E8 Permissions pédagogiques (notifications, SMS Android, micro, Wi-Fi local), E9 Habitudes d'épargne/budget | M01, M13, M18 | ✅ |
| 3.7 | E10 Données réelles / simulation + sauvegardes, E11 Prêt (cauri, récapitulatif). **Reste :** visite guidée 4 bulles | M01, M21 | 🚧 |
| 3.8 | « Rejouer l'accueil » depuis Profil, prénom affiché dans l'en-tête de l'accueil, photo de profil locale. **Fait :** rejouer l'accueil, avatar + prénom dans l'en-tête, photo affichée dans le Profil et sur l'écran de verrouillage, avatar par défaut. **Reste :** contrôle visuel sur appareil | M01, M23 | ✅ |

**Critère** : dashboard atteint en moins de 2 minutes, dashboard inaccessible sans E3.

---

## Phase 4 — Cœur métier : saisie, comptes, budget, besoins

| Étape | Contenu | Modules | État |
| --- | --- | --- | --- |
| 4.1 | Accueil réel : solde disponible = comptes + épargne − tiers, aperçu IA (coquille), actions rapides, 5 dernières transactions. **Réalisé en 1.3** ; restent les actions réellement branchées | M03 | ✅ |
| 4.2 | Entrées d'argent (< 10 s), comptes et catégories **prédéfinies** ; la table `categories` paramétrable reste à faire | M04, M06 | 🚧 |
| 4.3 | Sorties d'argent : montant FCFA, catégorie, note, bandeau « Enregistré · Annuler 5 s » | M05 | ✅ |
| 4.4 | Saisie rapide (feuille modale mobile / dialogue desktop) ouverte par le cochon, transferts et argent de tiers, avertissements non bloquants, glisser pour modifier/supprimer. **Appui long vocal restant (M12, Phase 6)** | M04, M05, M12 | 🚧 |
| 4.5 | Budget : plafonds par catégorie, jauges vert/orange/rouge 80 %/100 %, édition et suppression (Étape 6). **Reste : mois budgétaire paramétrable et lignes récurrentes** | M07 | 🚧 |
| 4.6 | Besoins priorisés : seuil explicite « payable bientôt » / « hors de portée », réserve de sécurité, détail du calcul | M08 | ✅ |
| 4.7 | Transferts entre comptes (deux écritures liées, suppression en cascade) | M04, M05 | ✅ |

---

## Phase 5 — Épargne, objectifs, argent de tiers, dettes

| Étape | Contenu | Modules | État |
| --- | --- | --- | --- |
| 5.1 | Coffre épargne interne, versement/retrait = transfert compte ↔ coffre. **Reste : proposition de versement 0→30 %** | M09 | 🚧 |
| 5.2 | Objectifs d'épargne : création, jauge. **Reste : date d'atteinte dynamique et accélération** | M10 | 🚧 |
| 5.3 | Fonds d'urgence (coffre + jauge). **Fait :** repères de paliers 25/50/75 % avec haptique. **Reste :** simulation de coup dur | M11 | 🚧 |
| 5.4 | Écran Argent de tiers : entrée neutre, reversement (plafonné au non soldé), exclusion budget-épargne-statistiques, total par tiers | M14 | ✅ |
| 5.5 | Créances et dettes (« On me doit » / « Je dois »), mouvement de trésorerie optionnel, états (En cours, Partiellement remboursé, Soldé, En retard), regroupement par contact, « Annuler » 5 s, masquage | M15 | ✅ |
| 5.6 | Rappel dédié par échéance de dette (même interdiction de montant et de nom) | M15, M18 | ⬜ |

---

## Phase 6 — Analyses, IA et SMS

> L'Étape 6 du porteur couvre les lignes 6.1, 6.3 (bilans) et la partie budget /
> besoins ; l'IA (6.3 conseils, 6.4) et les SMS (6.5) restent en phase 6.

| Étape | Contenu | Modules | État |
| --- | --- | --- | --- |
| 6.1 | Statistiques : semaine / mois / année / tout, histogramme double tonalité, ventilation par catégorie et par compte | M16 | ✅ |
| 6.2 | Calendrier des mouvements (fait), **reste** le détail et le reclassement d'une transaction | M16, M06 | 🚧 |
| 6.3 | Bilans mensuels comparés avec argent de tiers isolé (Étape 6). **Reste : détail, export et conseils IA** | M17 | 🚧 |
| 6.4 | Saisie libre IA texte et voix (micro, halo, carte de compréhension éditable). **Fait :** analyse locale par règles, carte éditable, écriture sur confirmation, halo de micro, appel au modèle distant en cascade avec repli local. **Reste :** reconnaissance vocale réelle, et appel réel au fournisseur non exercé (pas de clé sur le poste) | M12 | 🚧 |
| 6.5 | Extraction SMS Android multi-opérateurs (Flooz + Mixx by Yas), expéditeurs configurables, feuille de classement. **Fait :** collage de SMS, analyse multi-opérateurs (dont Orabank), feuille de classement et isolement des tiers. **Reste :** lecture de la boîte SMS et expéditeurs configurables | M13 | 🚧 |
| 6.6 | Clé API côté configuration utilisateur, quotas et mode hors ligne. **Fait :** clé chiffrée AES-256-GCM (clé maîtresse Keystore/DPAPI), masquée, testable et remplaçable ; liste des modèles récupérée et mise en cache ; priorité configurable ; délais 5/6/10/12 s ; cascade timeout/429/5xx avec plafond d'essais et veille 10 min ; repli local non bloquant ; indicateur discret du modèle ; `ai_quota_per_day` branché sur un compteur daté remis à zéro chaque jour. **Reste :** persister la veille entre deux lancements, essai réel avec une clé | M12, M17 | 🚧 |

---

## Phase 7 — Notifications et animations

| Étape | Contenu | Modules | État |
| --- | --- | --- | --- |
| 7.1 | Notifications locales planifiées : matin / midi / soir, heures personnalisables, plage « Ne pas déranger », reprogrammation après redémarrage. **Fait :** planification et annulation depuis le Profil. **Reste :** reprogrammation automatique au démarrage et prise en charge Windows | M18 | 🚧 |
| 7.2 | Messages variés et non répétitifs, aucune somme en FCFA si le masquage est actif | M18, M03 | ✅ |
| 7.3 | Périodes de fête : Noël, Nouvel An, fêtes religieuses/nationales, rentrée, plage personnalisée, budget spécial fête désactivable. **Fait :** fin d'année et plage personnalisée avec message dédié. **Reste :** calendrier des fêtes locales et budget spécial fête | M18 | 🚧 |
| 7.4 | Animations signature A→F (splash cauri, cascade du dashboard, paliers d'épargne, onde verte d'entrée, haptique de sortie, halo vocal) avec « Réduire les animations ». **Fait :** splash, cascade, paliers, halo vocal, haptique, réduction globale. **Reste :** onde verte d'entrée | M03, M09, M12, M18 | 🚧 |

---

## Phase 8 — Sauvegarde, synchronisation et exploitation

| Étape | Contenu | Modules | État |
| --- | --- | --- | --- |
| 8.1 | Sauvegarde chiffrée Google Drive (phrase secrète, restauration, versionnage). **Fait :** enveloppe AES-256-GCM, phrase secrète, restauration additive, dépôt dans un dossier synchronisé, connexion Google PKCE et dépôt/lecture dans `appDataFolder` avec les cinq dernières sauvegardes. **Reste :** identifiants OAuth du porteur, essai réel, sélection manuelle d'une version | M19 | 🚧 |
| 8.2 | Synchronisation serveur maître (API, LWW, pastille de synchronisation, états hors ligne). **Fait :** PUT/GET avec jeton Bearer et contrôle de conflit. **Reste :** API dédiée, pastille et LWW complet | M20 | 🚧 |
| 8.3 | Home Lab Backup sur Wi-Fi domestique, sans VPN. **Fait :** URL + jeton masqué, PUT/GET de l'enveloppe chiffrée, jeton en en-tête Bearer, « Vérifier » sans écriture, messages d'erreur distincts. **Reste :** découverte Wi-Fi, vérification « même réseau » et essai contre un vrai serveur | M22 | 🚧 |
| 8.4 | Mode simulation complet (base isolée, bandeau permanent). **Fait :** réglage persistant et bandeau permanent. **Reste :** base réellement isolée | M21 | 🚧 |
| 8.5 | 30 scénarios de recette, tests sur Android + Windows, accessibilité AA, performance (< 10 s par saisie) | Tous | ⬜ |

---

## Phase 9 — Distribution et durcissement release

| Étape | Contenu | Modules | État |
| --- | --- | --- | --- |
| 9.1 | Manifeste Android release : `applicationId` propre, libellé AKIBA, permissions minimales (réseau, notifications, biométrie), `READ_SMS` absent, sauvegarde système désactivée, desugaring, `FlutterFragmentActivity` | M02, M18, Tous | ✅ |
| 9.2 | Icône AKIBA : PNG 1024, cinq mipmaps Android et `.ico` Windows générés depuis l'emblème | M03 | ✅ |
| 9.3 | Métadonnées Windows (titre, produit, société, icône) | M03 | ✅ |
| 9.4 | Signature release : clé Android via `android/key.properties` (repli debug explicite en attendant) ; certificat Windows à fournir | Tous | 🚧 |
| 9.5 | Compilation réelle et recette sur appareil Android + Windows (icône, permissions, notifications, biométrie, sauvegarde/restauration) | Tous | ⬜ |

## Règles transverses ajoutées à l'Étape 10

| Règle | État |
| --- | --- |
| Sens exact « On me doit » / « Je dois » dans la saisie des créances et dettes, hors solde disponible, reste dû masqué | ✅ |
| Liste de devises (FCFA, Euro, Dollar, Yuan) avec logos téléchargés puis mis en cache, repli hors ligne typographique, sans conversion de valeur | ✅ |

## Règles transverses ajoutées à l'Étape 11

| Règle | État |
| --- | --- |
| Clé API chiffrée localement (AES-256-GCM + coffre système), masquée dans l'UI, testable et remplaçable, exclue des sauvegardes | ✅ |
| Liste des modèles récupérée avec la clé, mise en cache, repli sur le cache ou les modèles de départ hors ligne | ✅ |
| Ordre de priorité configurable (cases + flèches), identifiants inconnus ignorés | ✅ |
| Délais courts saisie/SMS (5–6 s), souples analyse/coaching (10–12 s) ; cascade sur timeout/429/5xx avec plafond d'essais | ✅ |
| Veille temporaire (10 min) d'un modèle en échec répété, arrêt immédiat sur clé refusée | ✅ |
| Indication discrète du modèle utilisé, repli local non bloquant, aucune écriture sans confirmation, aucun appel en mode masqué | ✅ |
| Mouvement de trésorerie optionnel (prêt/emprunt vs crédit/service) et isolation de l'argent emprunté | ✅ |
| États des créances et dettes, regroupement par contact, « Annuler » 5 s, masquage jusque dans les rappels | ✅ |

## Règles transverses ajoutées à l'Étape 12

| Règle | État |
| --- | --- |
| Relecture et simplification : chiffrement AES-GCM partagé (`AesBox`), catalogue IA sans code mort, énumération d'échec resserrée | ✅ |
| Quota IA journalier (`ai_quota_per_day`) avec compteur daté, remise à zéro implicite et repli local propre | ✅ |
| Photo de profil locale, chiffrée sur l'appareil, affichée dans l'en-tête, le Profil et l'écran de verrouillage, avatar par défaut | ✅ (contrôle visuel non fait) |
| « Se connecter avec Google » : identifiants OAuth dans un fichier dédié, flux PKCE, sauvegarde/restauration chiffrées AES-256-GCM dans `appDataFolder`, optionnel hors ligne | 🚧 (identifiants du porteur attendus) |
| Home Lab : URL + jeton sécurisé, envoi/lecture de l'enveloppe chiffrée, test de connexion | 🚧 (serveur réel non joint) |

## Règles transverses ajoutées à l'Étape 13

| Règle | État |
| --- | --- |
| Identifiant OAuth Google fourni par `--dart-define-from-file=secrets/google_oauth.json`, jamais écrit dans le code suivi ; `secrets/` et `client_secret_*.json` dans `.gitignore` | ✅ |
| Sauvegarde Drive chiffrée AES-256-GCM dans `appDataFolder`, optionnelle hors ligne, repli dossier synchronisé | ✅ (flux réel non exercé) |
| Cinq thèmes persistants (Blanc, Sombre, Bleu, Vert, Jaune Or), aperçu immédiat, repli Blanc sur valeur inconnue | ✅ |
| Contraste garanti par test : titres ≥ 10:1, textes secondaires ≥ 4.5:1, texte clair sur action ≥ 3:1 | ✅ |
| Barre basse non flottante, cochon latéral et icône IA juste au-dessus, logos officiels lisibles dans les cinq thèmes | ✅ (contrôle visuel à faire) |
| Exécution sur appareil Android via ADB sans fil | ✅ (APK construit, installé, application lancée sur SM-G781V) |
| Dépendance `flutter_local_notifications` fixée à `^22.3.3` (la 23.x exige Android SDK 37, indisponible en plateforme stable) | ✅ |

## Suivi transverse

| Sujet | État |
| --- | --- |
| Fichiers de suivi à jour après chaque étape | ✅ (Étapes 1.1 → 1.3, puis 4 → 13) |
| Journal des décisions et écarts | ✅ (`DEJA_FAIT.md`) |
| Revue de sécurité continue | 🚧 (`REVUE_SECURITE.md`, Étapes 1.1 → 13 évaluées) |
| Contrôle visuel (accueil, profil, onboarding) | 🚧 application installée et lancée sur le SM-G781V via ADB sans fil (Étape 13) ; contrôle visuel des cinq thèmes à faire par le porteur |
| Ouverture réelle de la base chiffrée sur appareil | ⬜ non vérifiée hors tests |
| `akiba_spec/a_savoir.txt` à remplir par le porteur | 🔒 |
