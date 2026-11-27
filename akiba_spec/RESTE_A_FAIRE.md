# RESTE_A_FAIRE — Feuille de route AKIBA

Dernière mise à jour : **25/11/2026** · Référence : `Cahier des charges AKIBA.md`
v2.0 + `akiba_animations_notifications_regles..txt`.

Légende : ✅ fait · 🚧 en cours · ⬜ à faire · 🔒 dépend d'une décision ou d'un accès externe.

> État au 25/11/2026 : les Étapes 1.1 → 1.3 puis 4 → 32 sont livrées et
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
| 2.1 | PIN 4→6 chiffres : hash salé en Keystore / DPAPI, refus des PIN triviaux, verrouillage au retour d'arrière-plan, dérivation de la clé de base depuis le PIN. **Fait :** empreinte SHA-256 salée 20 000 tours dans la base chiffrée, refus des PIN triviaux, activation réellement persistée (magasin des réglages, plus le magasin simulé), `LockGate` verrouille dès l'activation et sur pause/**hidden**. **Reste :** dérivation de la clé de base | M02 | 🚧 |
| 2.2 | Biométrie / Windows Hello, repli PIN systématique, limitation des essais. **Fait :** `local_auth` avec repli PIN ; **limitation persistante des essais** (`PinAttempts` : 3 essais libres puis 30 s, 1 min, 2 min, 5 min, compteur dans la base chiffrée, message neutre sans nombre d'essais restants, délai relu au redémarrage). **Reste :** vérification sur appareil | M02 | 🚧 |
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
| 3.5 | E6 PIN + biométrie, E7 Google optionnel (OAuth, hors ligne géré). **Fait :** PIN (relu après enregistrement pour activer le verrou), biométrie optionnelle avec repli PIN, bouton « Se connecter avec Google » avec flux PKCE prêt (`access_type=offline`, `prompt=consent`, messages `invalid_request`), repli dossier Drive. **Reste :** identifiants OAuth du porteur et essai réel de connexion | M01, M02 | 🚧 |
| 3.6 | E8 Permissions pédagogiques (notifications, SMS Android, micro, Wi-Fi local), E9 Habitudes d'épargne/budget | M01, M13, M18 | ✅ |
| 3.7 | E10 Données réelles / simulation + sauvegardes, E11 Prêt (cauri, récapitulatif). **Fait aussi :** zoom du logo jusqu'à couvrir l'écran puis fondu, avant l'Accueil. **Reste :** visite guidée 4 bulles | M01, M21 | 🚧 |
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
| 5.1 | Coffre épargne interne, versement/retrait = transfert compte ↔ coffre. **Fait :** proposition de versement 0→30 % (part réglable dans l'onglet Épargne, montant proposé recalculé sur le compte choisi, jamais automatique) | M09 | ✅ |
| 5.2 | Objectifs d'épargne : création, jauge. **Fait :** date d'atteinte dynamique au rythme observé. **Reste :** accélération (proposer les versements nécessaires pour tenir la date cible) | M10 | 🚧 |
| 5.3 | Fonds d'urgence (coffre + jauge). **Fait :** repères de paliers 25/50/75 % avec haptique. **Reste :** simulation de coup dur | M11 | 🚧 |
| 5.4 | Écran Argent de tiers : entrée neutre, reversement (plafonné au non soldé), exclusion budget-épargne-statistiques, total par tiers | M14 | ✅ |
| 5.5 | Créances et dettes (« On me doit » / « Je dois »), mouvement de trésorerie optionnel, états (En cours, Partiellement remboursé, Soldé, En retard), regroupement par contact, « Annuler » 5 s, masquage | M15 | ✅ |
| 5.6 | Rappel dédié par échéance de dette (même interdiction de montant et de nom). **Fait :** `ReminderPlanner.planDebts` — un rappel à 9 h le jour de l'échéance pour chaque créance/dette non soldée, message neutre (« Une échéance de dette tombe aujourd'hui »), ni montant ni nom, réglage `notif_debt` | M15, M18 | ✅ |

---

## Phase 6 — Analyses, IA et SMS

> L'Étape 6 du porteur couvre les lignes 6.1, 6.3 (bilans) et la partie budget /
> besoins ; l'IA (6.3 conseils, 6.4) et les SMS (6.5) restent en phase 6.

| Étape | Contenu | Modules | État |
| --- | --- | --- | --- |
| 6.1 | Statistiques : semaine / mois / année / tout, histogramme double tonalité, ventilation par catégorie et par compte | M16 | ✅ |
| 6.2 | Calendrier des mouvements, détail et reclassement d'une transaction. **Fait :** fiche de détail (type, compte, date, catégorie, note, budget) et reclassement par catégorie, sans changer montant, date, compte ni identifiant | M16, M06 | ✅ |
| 6.3 | Bilans mensuels comparés avec argent de tiers isolé (Étape 6). **Reste : détail, export et conseils IA** | M17 | 🚧 |
| 6.4 | Saisie libre IA texte et voix (micro, halo, carte de compréhension éditable). **Fait :** analyse locale par règles, carte éditable, écriture sur confirmation, halo de micro, appel au modèle distant en cascade (Gemini, DeepSeek, OpenRouter, Home Lab/Ollama ; clé chiffrée par fournisseur) avec repli local, **analyse automatique après la dictée**, créances (« Koffi me doit 5 000 ») et dettes (« je dois 5 000 à Ama ») reconnues hors solde disponible. **Reste :** appel réel au fournisseur non exercé (pas de clé sur le poste), qualité de la dictée dépendante du téléphone | M12 | 🚧 |
| 6.5 | Extraction SMS Android multi-opérateurs (Flooz + Mixx by Yas), expéditeurs configurables, feuille de classement. **Fait :** collage de SMS, analyse multi-opérateurs (dont Orabank), feuille de classement et isolement des tiers. **Reste :** lecture de la boîte SMS et expéditeurs configurables | M13 | 🚧 |
| 6.6 | Clé API côté configuration utilisateur, quotas et mode hors ligne. **Fait :** clé chiffrée AES-256-GCM (clé maîtresse Keystore/DPAPI), masquée, testable et remplaçable ; liste des modèles récupérée et mise en cache ; priorité configurable ; délais 5/6/10/12 s ; cascade timeout/429/5xx avec plafond d'essais et veille 10 min ; repli local non bloquant ; indicateur discret du modèle ; `ai_quota_per_day` branché sur un compteur daté remis à zéro chaque jour. **Reste :** persister la veille entre deux lancements, essai réel avec une clé | M12, M17 | 🚧 |

---

## Phase 7 — Notifications et animations

| Étape | Contenu | Modules | État |
| --- | --- | --- | --- |
| 7.1 | Notifications locales planifiées : matin / midi / soir, heures personnalisables, plage « Ne pas déranger », reprogrammation après redémarrage. **Fait :** planification et annulation depuis le Profil ; **reprogrammation automatique au démarrage** (`ReminderScheduler.reprogram`, sans nouvelle demande d'autorisation grâce à `permission_notifications`, greffon initialisé avant planification, Workmanager inscrit une seule fois par réglage). **Reste :** prise en charge Windows | M18 | 🚧 |
| 7.2 | Messages variés et non répétitifs, aucune somme en FCFA si le masquage est actif | M18, M03 | ✅ |
| 7.3 | Périodes de fête : Noël, Nouvel An, fêtes religieuses/nationales, rentrée, plage personnalisée, budget spécial fête désactivable. **Fait :** fin d'année et plage personnalisée avec message dédié. **Reste :** calendrier des fêtes locales et budget spécial fête | M18 | 🚧 |
| 7.4 | Animations signature A→F (splash cauri, cascade du dashboard, paliers d'épargne, onde verte d'entrée, haptique de sortie, halo vocal) avec « Réduire les animations ». **Fait :** `CauriDropAnimation` partagé — **3 s** à chaque versement d'épargne, **1 s** à l'ouverture (choix explicite de l'Étape 16 pour ne pas retarder le verrou), cascade, paliers, halo vocal, haptique, réduction globale. **Reste :** onde verte d'entrée | M03, M09, M12, M18 | 🚧 |

---

## Phase 8 — Sauvegarde, synchronisation et exploitation

| Étape | Contenu | Modules | État |
| --- | --- | --- | --- |
| 8.1 | Sauvegarde chiffrée Google Drive (sans phrase secrète; clé AES-256-GCM d'appareil). **Fait :** restauration additive, PKCE, `appDataFolder`, cinq versions récentes. **Reste :** consentement/test OAuth réel, sélection manuelle d'une version | M19 | 🚧 |
| 8.2 | Synchronisation serveur maître | M20 | Retiré du périmètre : aucune UI ni flux maître; Home Lab est la cible locale distante prise en charge |
| 8.3 | Home Lab Backup sur Wi-Fi domestique, sans VPN. **Fait :** URL + jeton masqué, PUT/GET de l'enveloppe chiffrée, jeton en en-tête Bearer, « Vérifier » sans écriture, **bouton « Tester la connexion »** (GET en lecture seule, actif dès la saisie de l'URL, retour précis : joignable/refusé 401/404/certificat/injoignable/délai), messages d'erreur distincts. **Reste :** découverte Wi-Fi et essai contre un vrai serveur | M22 | 🚧 |
| 8.4 | Mode simulation complet (magasin mémoire isolé, bandeau permanent). **Fait :** données FCFA fictives isolées des données réelles | M21 | ✅ |
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
| Identifiant OAuth Google **chargé automatiquement** (copie `assets/config/google_oauth.json` régénérée sans commande depuis `secrets/` : au démarrage sur ordinateur et avant chaque build Android ; ignorée par Git comme `secrets/` et `client_secret_*.json` ; `--dart-define` reste prioritaire) — voir Étapes 19 et 20 | ✅ |
| Connexion Google **Android native** (`google_sign_in`, portée `drive.appdata`, repli dossier synchronisé) — voir Étape 20 | 🚧 (configuration Cloud Console et appareil attendus) |
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

## Étape 14 — État restant

Le correctif code couvre contraste, icônes/logos, « Tout », réactivité au changement de magasin, langue immédiate, OAuth `state`, rappel de dépenses, seed de simulation et célébration vocale. Vérifications exécutées : `flutter analyze` sans problème; `flutter test` — 81 tests passés. Restent la recette Google réelle (testeur/consentement, client Desktop, Drive API), notifications/permissions Workmanager Android, contrôle visuel des cinq thèmes, builds natifs et test réel Home Lab/Drive. Les anciennes lignes sur phrases secrètes/serveur maître sont historiques : sauvegarde AES-256-GCM sans phrase, Google Drive et Home Lab uniquement.

### OAuth — vérification complémentaire

La requête installée a été minimisée : redirect loopback sans chemin, PKCE S256 + `state`, scope Drive appdata, et aucun paramètre d’autorisation incrémentale. À refaire sur appareil avec le client **Application de bureau** attendu. Si Google bloque encore cette requête sur Android, il faudra migrer l’authentification Android vers Google Identity Services avec un client Android associé au package/signature; ne pas substituer un client Android au redirect loopback desktop.

Le bouton Google est désormais affiché sans identifiants configurés et le splash natif/Flutter est blanc. À vérifier après reconstruction/réinstallation sur le téléphone, avec le repli hors ligne.

## Étape 15 — État restant (22/11/2026)

Correctifs livrés : démarrage allégé (`runApp` avant intégrité/photo/Workmanager), animation cochon + cauri de 3 s partagée par le splash et chaque versement d'épargne, zoom-fondu de fin d'onboarding, activation réelle du PIN (magasin des réglages, relecture après enregistrement, `LockGate` réactif), analyse vocale automatique après dictée et créances/dettes correctement extraites, requête Google durcie (`access_type=offline`, `prompt=consent`, messages `invalid_request`), bouton « Tester la connexion » Home Lab, débordements Épargne/Budget corrigés et icône par catégorie de budget.

Vérifications exécutées : `dart format lib test` (0 changement), `flutter analyze` sans problème, `flutter test` — **94 tests passés**.

Restent, inchangés : recette Google réelle (testeur/consentement, client Desktop, Drive API), essai Home Lab contre un vrai serveur, contrôle visuel du splash de 3 s, du zoom d'onboarding et des cinq thèmes, builds natifs, notifications/Workmanager sur appareil, qualité de la dictée hors ligne selon le téléphone.

## Étape 16 — État restant (22/11/2026)

Correctifs livrés : cochon et cauri correctement détourés (cochon entier, blancs internes préservés), ouverture réduite à l'animation seule pendant 1 s, suppression des deux `AnimatedSwitcher` qui provoquaient l'assertion Flutter au premier code PIN, et prise en charge de **Gemini, DeepSeek, OpenRouter et Home Lab / Ollama** avec clé chiffrée par fournisseur, adresse et modèle par fournisseur, blocage en mode masqué et repli local hors ligne.

Vérifications exécutées : `dart format lib test` (0 changement), `flutter analyze` sans problème, `flutter test` — **105 tests passés**.

Restent, inchangés : essai réel d'un fournisseur compatible OpenAI (DeepSeek, OpenRouter ou Ollama) faute de clé et de serveur sur le poste ; recette Google réelle ; contrôle visuel de l'ouverture et de l'écran de réglages IA sur appareil ; builds natifs ; notifications/Workmanager.

---

## Étape 17 — Bilan exact et correctifs (23/11/2026)

Ce bilan remplace toute impression de « tout est fait » : il distingue ce qui
est **codé et testé**, ce qui est **codé mais non reçu sur appareil**, et ce qui
est **encore à écrire**.

### 1. Livré et vérifié dans cette étape

| Élément | Détail | Preuve |
| --- | --- | --- |
| Saisie vocale créances / dettes | Nombres **écrits en lettres** reconnus (« Guy me doit trois mille francs », « douze mille cinq cents », « quatre-vingt mille ») ; garde-fou : aucun montant sans multiplicateur (« un café » ne vaut pas 1 FCFA) | `ai_command_parser.dart`, 6 tests |
| Enregistrement d'une créance / dette | Aucun compte n'est exigé ; le contact est nettoyé (chiffres retirés, phrase entière → « Contact ») ; analyse automatique après la dictée déjà en place | `assistant_sheet.dart` |
| Limitation des essais de PIN (2.2) | 3 essais libres puis 30 s / 1 min / 2 min / 5 min ; compteur et échéance dans la base chiffrée ; message neutre ; délai relu au redémarrage ; aucune donnée effacée | `pin_attempts.dart`, `splash_screen.dart`, 3 tests |
| Proposition de versement 0→30 % (5.1) | Part réglable (0/10/20/30 %) dans l'onglet Épargne ; bouton « Proposer X % » recalculé sur le compte sélectionné ; jamais automatique | `savings_projection.dart`, `portfolio_screen.dart` |
| Date d'atteinte dynamique (5.2) | « À ce rythme : jj/mm/aaaa » au rythme observé depuis la création du coffre | `savings_projection.dart`, 2 tests |
| Reprogrammation des rappels au démarrage (7.1) | `ReminderScheduler.reprogram` relit les réglages, ne redemande pas l'autorisation (`permission_notifications`), ne planifie rien sur Windows | `reminder_scheduler.dart`, `main.dart`, `profile_screen.dart` |

### 2. Écarts des demandes récentes : état réel

| Écart | État | Preuve / limite |
| --- | --- | --- |
| Saisie vocale créances/dettes | ✅ Corrigée (chiffres et lettres) | tests « Guy me doit 3000 fr », « Je dois 3000 fr à Guy », « trois mille » |
| Transition zoom + transparence de fin d'onboarding | ✅ Déjà codée | `AnimatedScale(12)` + `AnimatedOpacity` 800 ms dans `onboarding_flow.dart` |
| Animation cochon + cauri à l'épargne | ✅ 3 s à chaque versement | `AkibaDurations.cauriDrop` + `showSavingsCelebration` |
| Animation cochon + cauri à l'ouverture | ⚠️ **1 s**, pas 3 s | choix explicite de l'Étape 16 (ne pas retarder le verrou) ; à réarbitrer par le porteur si les 3 s sont voulues |
| Activation du PIN | ✅ Persistée, `LockGate` réactif, vérifiée | tests `onboarding_pin_test` / `regressions_test` |
| Débordement Portefeuille > Épargne | ✅ `FittedBox` + `Wrap`, test 320 px | test de robustesse (avec `AkibaSettingsScope`) |
| Icônes Analyses > Budget | ✅ `LabelIcons.forCategory` par plafond | test « une icône par catégorie » |
| Test de connexion Home Lab | ✅ Bouton + `probeRemote` (GET en lecture seule, jeton Bearer) | ⚠️ aucun serveur réel joint |

### 3. Modules encore ouverts — rien n'est coché par complaisance

#### 3.1 À écrire, sans dépendance externe

| Étape | Reste |
| --- | --- |
| 1.4 | Extraire `BarChart`, `BreakdownRow`, `MosaicTile` réutilisables (aujourd'hui en ligne dans Analyses) |
| 1.6 | Embarquer Poppins / Inter (aucun `.ttf` dans le dépôt) |
| 1.7 | Rail latéral Windows, raccourcis Ctrl+M/N/I/K |
| 2.1 | Dérivation de la clé de base depuis le PIN |
| 2.4 | Rotation de la clé, message si le coffre système est indisponible |
| 3.7 | Visite guidée 4 bulles |
| 4.2 | Table `categories` paramétrable |
| 4.5 | Mois budgétaire paramétrable, lignes récurrentes |
| 5.3 | Simulation de coup dur |
| 6.3 | Détail/export des bilans, conseils IA |
| 6.5 | Lecture de la boîte SMS, expéditeurs configurables |
| 6.6 | Persister la veille des modèles entre deux lancements |
| 7.3 | Calendrier des fêtes locales, budget spécial fête |
| 7.4 | Onde verte d'entrée |
| 8.1 | Choix manuel d'une version Drive |
| 8.3 | Découverte mDNS du Home Lab |
| 8.5 | 30 scénarios de recette |
| 9.4 / 9.5 | Signature release et recette sur appareil |

#### 3.2 Bloqué par un accès ou un appareil (🔒)

- OAuth Google réel (identifiants du porteur, testeur, consentement, Drive API).
- Home Lab contre un vrai serveur sur le Wi-Fi.
- Builds natifs : `flutter build apk` échoue sur la configuration AGP 9
  préexistante (`android/app/build.gradle.kts`) et Visual Studio est absent
  pour Windows.
- Vérifications sur appareil : biométrie, notifications/Workmanager, dictée
  hors ligne, contrôle visuel des cinq thèmes et du geste cauri.
- Clé IA réelle (Gemini, DeepSeek, OpenRouter ou Ollama).
- Certificats de signature Android/Windows.
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

### 1. Chargement sans option de compilation

| Élément | Détail |
| --- | --- |
| Problème | Flutter n'offre aucun `--dart-define-from-file` « par défaut » : il fallait répéter l'option à chaque `flutter run` / `flutter build`, sinon `clientId` restait vide |
| Solution | `tool/sync_oauth_secrets.dart` copie `secrets/google_oauth.json` (ignoré par Git) vers `assets/config/google_oauth.json` (ignoré par Git, embarqué au build) |
| Résolution | `GoogleOAuthConfig.load()` (appelé dans `main` et par `GoogleDriveService.signIn`) : `--dart-define`, puis `secrets/google_oauth.json` à l'exécution (ordinateur), puis la copie embarquée (Android/iOS) |
| Garde-fous du script | Identifiant vide ou ne finissant pas par `.apps.googleusercontent.com` → copie supprimée ; identifiant jamais affiché en entier ; cible non réécrite si déjà à jour |

### 2. Requête OAuth conforme (Android inclus)

| Point | État |
| --- | --- |
| Espaces du `scope` | Encodés en `%20` via `Uri.encodeComponent` (plus de `+` ambigu) — testé sur la chaîne réellement envoyée |
| `client_id` vide | Plus jamais émis ; `signIn()` refuse avant d'ouvrir le navigateur avec la marche à suivre |
| `redirect_uri` | `http://127.0.0.1:<port>`, sans chemin, identique à l'échange du code — testé |
| Paramètres | `access_type=offline` + `prompt=consent` requis pour le jeton de rafraîchissement ; `include_granted_scopes` absent (non supporté) |
| Android | Boucle locale **dépréciée par Google pour les applications mobiles** : AKIBA reste sur un client « Application de bureau » et le message `invalid_request` nomme cette cause ; `<queries>` VIEW/https ajouté pour que `url_launcher` ouvre le navigateur sur Android 11+ |
| Repli | Inchangé : sans identifiant ou en cas d'échec, dossier Drive synchronisé / mode hors ligne, aucun blocage |

### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart run tool/sync_oauth_secrets.dart` | Copie écrite, code retour 0, fichier ignoré par Git |
| `dart format lib test tool` | 97 fichiers, 3 reformatés, relance sans changement |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **128 tests, tous passés** |

### Ce qui n'est pas vérifié

- Connexion Google réelle depuis un téléphone (consentement, retour du
  navigateur, échange du code) : impossible sans appareil ni compte de test.
- Build natif : configuration AGP 9 préexistante toujours bloquante.

---

## Étape 20 — Copie OAuth automatique et connexion Android native (23/11/2026)

### 1. Simplification de l'Étape 19

| Élément retiré | Raison |
| --- | --- |
| `clientIdPlaceholder` / `clientSecretPlaceholder` | Toujours vides, aucun usage |
| `isLoaded` | État statique inutile : `load()` relit, `signIn()` ne relit que si rien n'est chargé |
| `redirectPath` | Constante d'un seul caractère, écrite une fois dans l'écouteur |
| `GoogleAuthException` dans `google_drive_backup.dart` | Fichier dédié, ré-exporté (compatible avec les imports existants) |
| `FlutterSecureStorage` dans l'API du service | Remplacé par `GoogleTokenVault`, ce qui rend les deux branches testables |

### 2. Génération réellement automatique

| Mécanisme | Portée |
| --- | --- |
| Tâche Gradle `syncOAuthSecrets` avant `preBuild` | **Seule** copie automatique : `flutter run` / `flutter build` Android rafraîchissent `assets/config/google_oauth.json` avant `compileFlutterBuildDebug`, sans commande |
| `dart run tool/sync_oauth_secrets.dart` | Ponctuel / diagnostic uniquement |
| `GoogleOAuthConfig.load()` | Lecture seule : `--dart-define`, puis `secrets/google_oauth.json` (ordinateur), puis la copie embarquée |

La copie au démarrage et son avertissement `copyNotice` ont été retirés : sur
ordinateur, la copie n'est jamais relue (le fichier `secrets/` gagne) ; sur
Android, seul le build peut l'embarquer.

### 3. Connexion Google Android (`google_sign_in`)

| Point | État |
| --- | --- |
| Dépendance | `google_sign_in: ^7.2.0` |
| Branche Android | `GoogleSignInAndroidAuth` : `authenticate` + `authorizationForScopes(driveScopes)`, reconnexion silencieuse, `disconnect` |
| Identifiants | Client OAuth **Android** (package `com.akiba.app` + SHA-1) et client **Application Web** (`AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID`) ; aucun secret dans le dépôt ni dans l'APK |
| Jetons | Jeton d'accès Drive en mémoire (50 min), rien de durable hors du coffre système ; Play services renouvelle |
| Flux ordinateur | PKCE / boucle locale conservé, inchangé |
| Repli | Échec ou annulation → message explicite + dossier Drive synchronisé / mode hors ligne |
| Erreurs nommées | Annulation, écran indisponible, configuration (package, SHA-1, compte testeur, `drive.appdata`) |

### Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test tool` | 101 fichiers, 0 changement |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **133 tests, tous passés** (5 nouveaux sur la branche Android et le repli) |
| `dart run tool/sync_oauth_secrets.dart` | « déjà à jour », code retour 0 |
| `./gradlew :app:assembleDebug` | **BUILD SUCCESSFUL in 7m 22s**, APK `build/app/outputs/flutter-apk/app-debug.apk`, copie OAuth présente dans l'APK, `syncOAuthSecrets` exécutée avant l'assemblage des assets |
| `git check-ignore -v` | `secrets/` et `assets/config/google_oauth.json` ignorés |

### Ce qui n'est pas vérifié

- Connexion Google réelle sur Android (consentement, jeton Drive, restauration) :
  aucun compte testeur, aucune empreinte SHA-1 enregistrée.
- Application non lancée sur le téléphone : l'APK est produite mais ni
  l'installation via `adb` ni le parcours de connexion n'ont été exercés.
- Empreinte SHA-1 de signature : se relève avec
  `dart run tool/debug_sha1.dart` et s'enregistre côté Google Cloud Console avec
  le package `com.akiba.app` (client Android) et le client « Application Web »
  (`AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID`). Procédure exacte, étape par étape :
  `akiba_spec/activer_connexion_google_android.md`.

---

## Étape 22 — Correctifs ciblés : langue, permissions, Home Lab, dropdowns, règlements, solde et déconnexion (24/11/2026)

### 1. Livré dans cette étape

| Demande | Correctif | Fichiers principaux | État |
| --- | --- | --- | --- |
| Langue de l'onboarding | `AkibaSettings.setLanguage` applique `AkibaL10n` + `AkibaDate` **avant** de notifier ; l'onboarding utilise ce chemin et son habillage (langue, thème, boutons, compteur) est traduit : l'interface bascule dès la sélection d'« English » | `core/state/akiba_settings.dart`, `core/state/akiba_l10n.dart`, `features/onboarding/onboarding_flow.dart` | ✅ |
| Rappels matin / midi / soir « autorisation refusée » | Lecture de l'état **réel** de la permission (`areNotificationsEnabled` / `checkPermissions`) avant et après la demande, relecture après un `null`, garde de ré-entrance, message spécifique si refus définitif + bouton « Ouvrir les réglages système » (`openAppSettings`), Windows annoncé honnêtement au lieu de « refusé » ; la planification ne se fie plus à un drapeau périmé | `core/notifications/local_notifications.dart`, `core/notifications/reminder_scheduler.dart`, onboarding, Profil | ✅ |
| Test Home Lab | `BackupService.normalizeUrl` accepte `192.168.1.80`, `ip:port`, nom local ou URL complète (ajout de `http://`) ; sonde : délai 8 s, en-têtes `Accept`/`User-Agent`, distinction port fermé / nom introuvable / pas de route / certificat / délai / autre code HTTP, adresse normalisée enregistrée et testée | `core/backup/backup_service.dart`, `features/backup/backup_center.dart` | ✅ |
| Crash `DropdownButton` | Valeurs `timezone` / `dateStyle` inconnues ajoutées à la liste au lieu de faire tomber l'assertion (Profil + onboarding), catégorie de l'assistant toujours ramenée à la liste courante, comptes dédupliqués, ligne SMS pointant un compte absent repliée sur le premier | Profil, onboarding, `assistant_sheet.dart`, `sms_review_sheet.dart` | ✅ |
| Assertion « really is our descendant » | `Navigator`/`ScaffoldMessenger` capturés avant `pop()` dans l'assistant (confirmation, créance/dette, épargne), fête d'épargne affichée sur le navigateur, `_say` vérifie `mounted`, `catch` ne fait plus `setState` après fermeture | `features/assistant/assistant_sheet.dart`, `features/assistant/ai_settings_sheet.dart` | ✅ |
| Règlement créance / dette | `AkibaStore.settleDebt` : créance encaissée = **entrée** sur le compte choisi (solde disponible augmenté) ; dette payée = **sortie** du compte choisi ; montant borné au reste dû, annulation complète. Le portefeuille demande le compte, l'assistant propose « Cette créance a été encaissée / Cette dette a été payée » avec la ligne ouverte à régler | `data/akiba_store.dart`, `data/sqlite_akiba_store.dart`, `data/simulation_store.dart`, portefeuille, assistant | ✅ |
| Solde de l'accueil non rafraîchi | **Cause trouvée** : `setState(() => _snapshot = loadDashboard())` rendait un `Future`, refusé par Flutter (« setState() callback argument returned a Future ») : la relance était rejetée à chaque `revision.bump()`. Même bug corrigé dans Analyses et Portefeuille. Les trois écrans relisent maintenant la base de façon synchrone | `features/dashboard/dashboard_screen.dart`, `features/analysis/analysis_screen.dart`, `features/portfolio/portfolio_screen.dart` | ✅ |
| Déconnexion | Bouton « Se déconnecter » dans Profil → Sauvegarde : confirmation explicite, `GoogleDriveService.signOut` (jeton de rafraîchissement + e-mail supprimés du coffre, `disconnect` Android), `google_linked` remis à faux, **aucune donnée locale supprimée** | `features/profile/profile_screen.dart` | ✅ |

### 2. Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 101 fichiers, 0 changement après formatage |
| `flutter analyze` | **No issues found!** |
| `flutter test` | 139 tests, tous passés (dont 6 nouveaux dans `test/fixes_test.dart`) |

Nouveaux tests : langue (globales + bascule réelle de l'onboarding), créance encaissée (+solde), dette payée (−solde et annulation), montant borné au reste dû, solde de l'accueil actualisé après entrée, dépense et règlement sans changer d'onglet.

### 3. Ce qui reste ouvert

- Aucun contrôle sur appareil Android : permission de notification refusée/accordée, rappels réellement livrés, Home Lab joint sur un vrai Wi-Fi, déconnexion Google réelle.
- Aucun serveur Home Lab disponible pour le test : les messages sont vérifiés par lecture de code, pas par un appel réseau réel.
- Les écrans métier détaillés (Analyses, Portefeuille, saisie rapide, onboarding hors habillage) restent en français : seule la navigation, l'accueil, le Profil et l'habillage de l'onboarding sont traduits.
- Le solde de l'accueil suit le signal `revision` : toute nouvelle écriture doit appeler `revision.bump()` (vérifié pour toutes les écritures actuelles).

---

## Étape 23 — Bienvenue et SMS financiers en arrière-plan (24/11/2026)

### 1. Livré dans cette étape

| Demande | Réalisé | Fichiers |
| --- | --- | --- |
| Notification de bienvenue en fin d'onboarding | `AppNotifications.welcome` : envoyée si `permission_notifications` **et** autorisation système, texte sans montant, dans la langue active, déclenchée en fin d'onboarding sans bloquer l'entrée | `core/notifications/app_notifications.dart`, `local_notifications.dart`, onboarding |
| Détection SMS Flooz / Mixx by Yas **application fermée** | Récepteur Android `SmsReceiver` + permissions `READ_SMS`/`RECEIVE_SMS`, filtre opérateur + devise + montant, notification **sans montant**, texte transporté par l'`Intent` (aucun stockage) | `SmsReceiver.kt`, `MainActivity.kt`, `AndroidManifest.xml` |
| Ouverture directe sur la fiche préremplie | Pont `akiba/sms` + `akiba/sms_events`, `SmsBridge`, `AkibaShell` → `openQuickEntry(prefill:)` ; montant, sens, support (Flooz/Mixx/Orabank) et contact préremplis ; bandeau de vérification ; aucune écriture avant « Enregistrer » | `core/sms/sms_bridge.dart`, `sms_entry_intent.dart`, `quick_entry.dart`, `akiba_shell.dart` |
| Extension **SMS bancaires** | `SmsParser` reconnaît Orabank et les banques (BOA, Ecobank, Coris, NSIA, UBS, BSIC, Attijari, Société Générale…), `F CFA` espacé, dépôt/crédit/crédité/virement reçu → entrée, retrait/débit/prélèvement/chèque/paiement/DAB/commission → sortie ; libellé « Banque » quand le nom exact est inconnu | `core/sms/sms_parser.dart` |
| Activation depuis le Profil | Bouton « Activer la détection », état « active / inactive », demande réelle de permission et ouverture des réglages si refus définitif | `features/profile/profile_screen.dart` |

### 2. Vérifications réellement exécutées

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 105 fichiers, 0 changement après formatage |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **149 tests, tous passés** (10 nouveaux dans `test/sms_welcome_test.dart`) |
| `./gradlew :app:compileDebugKotlin` | **BUILD SUCCESSFUL in 3m 53s** (récepteur, `MainActivity`, manifeste) |

### 3. Vérifier sur l'appareil

```bash
adb shell dumpsys package com.akiba.app | grep -E "READ_SMS|RECEIVE_SMS|POST_NOTIFICATIONS"
adb logcat -c && adb logcat -s flutter
adb emu sms send 12345 "Flooz: Vous avez recu 25000 FCFA de KOFFI Ama."
adb emu sms send 12345 "Orabank: Debit de 12000 FCFA - PAIEMENT CARTE."
adb emu sms send 12345 "Mixx by Yas: Paiement de 3500 FCFA effectue chez ALIMENTATION."
adb shell dumpsys notification --noredact | grep -A 8 akiba_sms
```

Sur un appareil physique, `adb shell am broadcast` est refusé (protection
`BROADCAST_SMS`) : envoyer le SMS depuis un second téléphone. Attendu :
notification sans montant, puis fiche préremplie au clic, aucune écriture avant
confirmation.

### 4. Ce qui reste ouvert

- APK complète (`flutter build apk --debug`) et essai réel sur téléphone : non
  exécutés ; seul `compileDebugKotlin` est passé.
- Notification SMS volontairement **générique** (aucun montant) : un montant
  masqué « intelligent » exigerait une préférence native dédiée (idée 168).
- Pas de déduplication d'un SMS déjà converti en écriture (idée 169).
- Windows : ni bienvenue ni SMS (pas de récepteur, greffon de notification non
  planifiable) ; l'application ne le cache pas.

---

## Étape 24 — Rapport mensuel PDF (24/11/2026)

### Livré

- Génération à la demande depuis **Paramètres › Rapport mensuel**, en données réelles ou de simulation, PDF 100 % local (`pdf`), prévisualisation in-app (`printing`), Email / WhatsApp / partage.
- Montants **toujours en clair** dans le rapport et le PDF, y compris graphiques et section IA, quel que soit le masquage global ; isolation stricte de l'argent de tiers, de l'épargne et des créances/dettes (blocs séparés, jamais additionnés).
- Avis et conseils : analyse locale déterministe FR/EN, enrichie par l'IA configurée quand elle est disponible, puis intégrée au PDF.
- Thème actif (5 palettes) et langue FR/EN appliqués au document ; logo AKIBA en tête, graphiques et avis en bas.
- Option fin de mois (génération locale au premier lancement du mois suivant + notification sans montant) et copie Home Lab (PUT JSON base64 vers le serveur déjà configuré).

### Vérifications

| Commande | Résultat |
| --- | --- |
| `dart format lib test` | 112 fichiers, 0 changement |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **162 tests, tous passés** |
| `./gradlew :printing:compileDebugJavaWithJavac :app:compileDebugKotlin` | **BUILD SUCCESSFUL in 3m 23s** |

### Reste ouvert

- Aperçu PDF et partage non testés sur téléphone ; rendu PDF de 2 pages.
- La copie Home Lab exige une adresse et un jeton configurés dans le Centre de sauvegarde.
- Les actions Email/WhatsApp dépendent des applications installées ; le PDF reste partageable autrement.

---

## Étape 25 — Messages d'épargne et taquineries (24/11/2026)

- Catalogue local FR/EN (encouragements + taquineries de retrait), sans montant, sans répétition immédiate.
- Coach IA optionnel pour varier la phrase ; repli local immédiat.
- Transition douce après l'animation de 3 s vers le message, respect de « Réduire les animations ».
- Taquinerie immédiate après un retrait d'épargne, sans bloquer l'opération.

Reste ouvert : rendu visuel de la transition et des messages non observé sur appareil ; l'IA n'est sollicitée que si elle est configurée.

---

## Étape 26 — Restes et limites de validation

- La lecture visuelle du PDF avec une photo réelle et le rendu du son système doivent encore être vérifiés sur un appareil Android ; le son peut être inaudible si le système est silencieux.
- La restauration a été testée en unit-test sans coffre local préexistant. Le parcours OAuth réel, la restauration entre deux appareils et la copie Google Drive restent à valider avec deux appareils connectés au même compte.
- Les anciennes sauvegardes version 2 chiffrées avec une clé d’appareil ne deviennent pas portables rétroactivement : elles restent restaurables sur l’appareil qui conserve cette clé.
- La demande Android 13+ et le rafraîchissement au retour des réglages sont couverts par le code et le manifeste, mais pas par un essai sur téléphone. Vérifier également les refus définitifs et l’autorisation accordée dans Paramètres Android.
- Le test Home Lab utilise une boucle locale; timeout réel, certificat TLS privé, pare-feu Wi-Fi et appareils sur deux réseaux doivent être vérifiés avec un serveur domestique réel.

---

## Étape 27 — Permission de notification pendant l’onboarding

- Les états accordé, demandeable et refusé définitivement sont couverts par des tests widget avec un adaptateur injecté. L’ouverture des réglages et la synchronisation du switch au retour sont vérifiées en test.
- Reste à vérifier sur Android 13+ réel que `permission_handler` affiche la boîte système après installation propre, et que le bouton mène à la fiche de réglages de l’application. Le test widget ne remplace pas cet essai natif.

---

## Étape 28 — Notifications de bienvenue et reprogrammation

- Le test widget vérifie désormais qu’avec permission accordée et rappels actifs, « Reprogrammer » appelle la frontière du scheduler et affiche un succès (nombre planifié), sans message de refus. Le test de bienvenue couvre aussi l’envoi avec prénom/nom quand la permission est active.
- Le gateway Android croise l’état de `Permission.notification` avec `areNotificationsEnabled()` du plugin et relit après demande; ce dernier est la lecture du `NotificationManager` (POST_NOTIFICATIONS sur API 33+, état général sur versions antérieures). Le miroir local n’autorise pas à lui seul un envoi ponctuel.
- Le diagnostic canal est distinct : les canaux `akiba_accueil` et `akiba_rappels` peuvent être désactivés individuellement malgré l’autorisation générale. Le Profil relève l’importance du canal de rappels et guide vers les réglages si celui-ci est bloqué.
- Reste à vérifier sur appareil Android réel (API 33+) l’accord système, la livraison de bienvenue et des rappels, ainsi que le scénario permission accordée mais canal désactivé; les tests widget ne remplacent pas cette recette native.


---

## Étape 29 — Faux négatif de permission Android

- Corrigé : l’initialisation du greffon utilisait `@mipmap/ic_launcher`, refusée par `getIdentifier(nom, "drawable", …)`, ce qui faisait échouer `ensureReady` et renvoyait « non autorisé » partout. L’icône est désormais `drawable/ic_stat_akiba` et la lecture de permission passe par `areNotificationsEnabled()` hors initialisation.
- Reste à constater sur appareil : accord POST_NOTIFICATIONS réel, bienvenue effectivement affichée sur le canal `akiba_accueil`, reprogrammation réussie, puis canal désactivé individuellement. Aucun appareil connecté ni APK reconstruit pendant ce correctif.

---

## Étape 30 — Restauration Drive et Home Lab en deux étapes

- Corrigé : l'onboarding restaure désormais avec l'identité Google du compte lié (lue hors ligne dans le coffre) ; l'identité est normalisée (e-mail minuscule sans espaces + identifiant stable) à la création comme à la restauration, plusieurs variantes sont essayées et l'e-mail attendu n'apparaît qu'en cas de vraie différence de compte.
- Corrigé : le Home Lab se configure en deux étapes — test IP/ping sans jeton avec latence, puis jeton protégé dans `flutter_secure_storage` et sauvegarde automatique AES-256-GCM (toutes les 6 h, au démarrage). L'ancien `lab_token` des réglages est migré puis effacé.
- Reste à vérifier avec un vrai compte Google : restauration Drive sur un second appareil, avec un e-mail saisi différemment, puis avec un autre compte (message attendu).
- Reste à vérifier avec un vrai serveur Home Lab : latence réelle, jeton refusé puis accepté, première sauvegarde automatique et réveil au démarrage suivant.
- L'écran du centre de sauvegarde n'a pas été observé visuellement pendant ce tour (aucun appareil, aucune capture) ; les tests couvrent la machine à états et la requête HTTP, pas le rendu.

---

## Étape 31 — Notifications, cauris, coffre et ordre de l'onboarding

- Fait : notifications Android en `BigTextStyleInformation` (corps complet en `contentText` et `bigText`), pour la bienvenue comme pour chaque rappel planifié ; plus de troncature « … ».
- Fait : l'animation d'épargne fait tomber **un cauri par tranche de 100 FCFA** (2 000 FCFA = 20 cauris), sans badge « ×N », en 3 s constants ; au-delà de 60 cauris visibles, la file est plafonnée pour rester fluide.
- Fait : l'action « Épargne » de l'accueil ouvre l'onglet Épargne du portefeuille (coffres, versements, retraits, objectifs) ; « Voir tout » ouvre les mouvements ; l'aperçu IA ouvre l'assistant. Plus aucune mention « Phase 5 » ou « Phase 6 » sur l'accueil.
- Fait : l'onboarding demande Google **avant** le prénom et le nom ; le profil Google pré-remplit les deux champs (modifiables) et l'étape manuelle est sautée quand ils sont renseignés.
- Tests : 4 nouveaux fichiers ciblés + parcours PIN adapté ; `dart format` propre, `flutter analyze` sans issue, suite complète — 194 tests passés.
- Reste à vérifier sur appareil Android : notification longue réellement dépliée (bienvenue et rappel), pluie de 20 cauris et gros montant, absence de saccade sur un téléphone modeste.
- Reste à vérifier avec un vrai compte Google : pré-remplissage du prénom et du nom sur Android (`displayName`) et sur ordinateur (`id_token` avec portée `profile`), puis saut effectif de l'étape manuelle. Un compte sans nom public gardera la saisie manuelle, ce qui est voulu.
- Reste à faire si voulu : un compteur discret du nombre de cauris (texte accessible) pour les personnes malvoyantes, sans réintroduire de badge visuel permanent.

---

## Étape 32 — Son, réseau, suppression, démarrage, IA et PDF

- Fait : son de cauri embarqué (`assets/audio/cauri_drop.wav`, `audioplayers`) joué **à chaque impact** (comptage dans la timeline, plan proportionnel au nombre de cauris (jusqu'à 10 nuances), volume progressif plafonné à 1.0), préchargé après la première image et coupé avec « Réduire les animations ». Erreurs audio journalisées, jamais silencieuses.
- Fait : le client de sauvegarde distingue désormais certificat refusé (`HandshakeException`), serveur injoignable (`SocketException`), délai (`TimeoutException`), connexion interrompue (`HttpException`) et refus HTTP ; le diagnostic Home Lab existant (adresse normalisée, latence, test sans jeton) reste le point d'entrée.
- Fait : la suppression dans « Dernières transactions » retire la ligne localement avant l'écriture SQLite, ne laisse plus `Dismissible` terminer sa propre animation (fin du message d'erreur fugitif), restaure la ligne en cas d'échec, journalise le type et une pile courte, et conserve « Annuler » 5 s.
- Fait : l'ouverture reste à 1 s ; intégrité de la base, photo, rappels, sauvegarde Home Lab, préchauffage des logos et du son passent dans `addPostFrameCallback`. `main` ne garde que base chiffrée, réglages, thème et verrou.
- Fait : l'assistant répond aux questions avec un résumé local (`ai_finance_context.dart`), sans aucun chiffre en mode masqué, et transforme un ordre en JSON (`expense`, `income`, `transfer`, `savings`, `third_party`, `debt`) relié aux services existants, toujours relu et confirmé. Le transfert écrit deux lignes symétriques.
- Fait : zoom tactile jusqu'à 50× (`AkibaZoom`) dans l'aperçu PDF (déplacement une fois zoomé, bouton Réinitialiser) et section « Avis & analyse IA » quand le modèle a répondu, sinon « Avis et conseils » avec l'analyse locale.
- Tests : `test/ai_finance_context_test.dart` ; `dart format lib test` propre, `flutter analyze` sans issue, suite complète — **197 tests passés**.
- Reste à vérifier sur appareil : son réellement audible au premier impact, zoom PDF au doigt, réponse IA affichée, suppression par glissement sans message parasite.
- Reste à vérifier avec un vrai serveur Home Lab et une vraie clé IA : messages TLS/HTTP, discussion chiffrée et exécution d'un ordre.
- Reste à faire si voulu : un compteur accessible du nombre de cauris (idée 198) et une corbeille de suppression réversible (idée 206).

### Etape 32 - complement IA

- Fait : selection automatique du fournisseur si le fournisseur courant ne possede pas de cle et une seule cle fournisseur est configuree; si plusieurs cles existent, le choix courant reste inchange.
- Fait : le test envoie une requete au modele selectionne (priorite Gemini disponible ou modele configure du fournisseur compatible) et affiche la reponse dans le panneau. Les erreurs sont reduites a des categories reseau, delai, quota, service ou format sans exposer URL, corps ou cle. Le diagnostic ne consomme pas le quota IA quotidien.
- Tests cibles : `test/ai_test_reply_test.dart` (modele choisi, reponse, quota HTTP, delai et endpoint inaccessible).

### Etape 33 - cle sans endpoint, reponse sous Tester, zoom et son (26/11/2026)

- Fait : plus aucune saisie d'endpoint quand une cle est collee. L'adresse par defaut du fournisseur est resolue en arriere-plan ; l'adresse et le modele ne vivent plus que dans « Reglages avances (facultatif) », replies par defaut.
- Fait : `activateAiProviderWithKey` memorise le fournisseur et active `ai_remote_enabled` des l'enregistrement de la cle. L'assistant, les ordres et le rapport/PDF la prennent en compte sans redemarrage. Le masquage reste prioritaire.
- Fait : la reponse du modele (ou l'erreur categorisee) s'affiche dans la meme carte, juste sous le bouton « Tester », avec l'etat « Test en cours… » (`AiTestPanel`).
- Fait : zoom au pincement jusqu'a 50× (`PinchZoom`, `AkibaZoom`) dans l'apercu PDF, panoramique une fois agrandi, bouton Reinitialiser.
- Fait : son des cauris verifie par calcul pur : densite, cadence et nuance proportionnelles au nombre, plafond de 10 notes, volumes bornes a 1.0, impacts dans la duree de l'animation.
- Tests : `test/cauri_sound_test.dart` (6), `test/pinch_zoom_test.dart` (2), `test/ai_settings_ui_test.dart` (9), plus les cinq tests existants de `test/ai_test_reply_test.dart` ; `dart format lib test` propre, `flutter analyze` sans issue, suite complete — **224 tests passes**.
- Reste a verifier sur appareil : pincement reel sur l'apercu PDF (deux doigts), son audible au premier impact et sur une grosse chute, reponse d'une vraie cle API, et absence de blocage quand le reseau est coupe puis retabli.
- Reste a verifier sur Android : serveur local en HTTP clair (192.168.x.x / 10.x.x.x / 127.0.0.1) — `usesCleartextTraffic="true"` est deja declare ; confirmer sur un telephone que l'IP locale est joignable et que la sauvegarde en attente repart au retour du Wi-Fi.

## Règles transverses ajoutées le 26/11/2026

| Règle | État |
| --- | --- |
| Restauration serveur : `404`, `204` et corps vide = « aucune sauvegarde », sans faux « format non reconnu » | ✅ (`fetchRemote`, `decodeRemoteBackup`, tests `backup_server_decode_test.dart`) |
| Enveloppe serveur identique à l'octet près (UTF-8 explicite en `PUT`, corps brut en `GET`) | ✅ (tests locaux ; serveur réel non joint) |
| Serveur `config_serveur/` multi-utilisateurs : un jeton → un dossier, `latest.json` + 30 historiques, `404` si vide, `GET /health` | ✅ (code livré ; `docker build` et déploiement à faire par le porteur) |
| Jeton unique partagé (`SHARED_TOKEN`) : chaque personne écrit `JETON:son_nom` et garde son dossier ; jetons dédiés (`USER_TOKENS`) toujours possibles ; repli `API_TOKEN` | ✅ (vérifié sur serveur réel : 401/404/isolation/reprise des guillemets) |
| Redémarrage automatique du serveur (`restart: unless-stopped`, `systemctl enable docker`) | ✅ (procédure documentée ; reboot réel non observé) |
| Test IA sans faux « hors format » : raisonnement, plusieurs candidats, listes de parties, texte brut, `maxOutputTokens` | ✅ (tests `ai_reply_parsing_test.dart`) |
| Erreurs IA classées par le corps du fournisseur : `400 API_KEY_INVALID` → « clé refusée », `404` → « modèle introuvable », `5xx` → second essai unique | ✅ (tests `ai_test_reply_test.dart`, `ai_provider_test.dart`) |
| Clé Gemini en en-tête `x-goog-api-key` (clés `AIza…` et `AQ.…`), diagnostic à 40 s, reprise sur les deux modèles suivants | ✅ (code + tests ; clé réelle non exercée ici) |
| 401 de restauration expliqué : motif du serveur affiché, jeton saisi utilisé même avant « Enregistrer et activer », guillemets/espaces tolérés côté serveur | ✅ (serveur réel en boucle locale + tests `backup_server_decode_test.dart`) |
| Liste déroulante des modèles accessibles avec la clé, test sur le modèle sélectionné | ✅ (`ai_settings_sheet.dart`, test widget) |
| Sauvegarde auto hors ligne : `auto_backup_pending_at` + reprise au retour au premier plan | ✅ (déjà couvert par `auto_backup_test.dart`) |
| HTTP local Android (`usesCleartextTraffic="true"`, IP privées) | ✅ déclaré ; joignabilité sur téléphone à confirmer |
| Zoom PDF (`AkibaZoom.maxScale = 50`) et son des cauris proportionnel (densité 1 note / 4 cauris, plafond 10) | ✅ alignés sur le code actuel |


### Etape 34 - Format de sortie IA et avis reel dans le PDF (27/11/2026)

- Fait : `AiText` decode JSON, listes, fences et Markdown ; l'assistant affiche des paragraphes et des puces, montants FCFA en gras, jamais l'objet brut.
- Fait : `ReportAdvice.parse` accepte JSON (`avis`/`conseils`), Markdown et texte ; un paragraphe unique est decoupe aux phrases, donc le PDF recoit l'avis reel du modele au lieu du repli local.
- Fait : consigne du rapport en JSON explicite (FR/EN) et delai d'analyse porte a 18 s.
- Tests : `test/ai_text_test.dart`, `test/monthly_report_test.dart` (JSON du modele dans le PDF), plage de delai dans `test/core_test.dart` ; 65 tests cibles passes, `flutter analyze` sans issue, APK debug reconstruit et installe.
- Reste a verifier sur appareil : carte conseil de l'assistant avec une vraie reponse Gemini, et carte « Avis & analyse IA » d'un PDF genere.
