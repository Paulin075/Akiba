# REVUE_SECURITE — AKIBA

Dernière mise à jour : **20/11/2026** · Périmètre examiné : Étapes **1.1 → 1.3**,
**4** (saisie rapide), **5** (portefeuille), **6** (analyses), **7** (profil,
PIN, biométrie, rappels), **8** (assistant IA, SMS, sauvegardes chiffrées) et
**9** (onboarding, animations), **10** (revue complète, release Android et
Windows, devises et dettes), **11** (clé IA, cascade de modèles, règles des
créances et dettes), **12** (quota IA, photo de profil chiffrée, Google Drive
PKCE, Home Lab) et **13** (identifiant OAuth branché hors dépôt, cinq thèmes
persistants), dépôt Flutter complet.

Légende : ✅ conforme · 🟠 partiel · ⬜ non implémenté (attendu à ce stade) · 🔒 à vérifier sur appareil

---

## 1. Synthèse

Depuis l'Étape 1.2, l'application **stocke des données financières** dans une
base SQLite chiffrée (SQLCipher, AES-256). Il n'y a toujours ni réseau, ni clé
d'API, ni compte utilisateur. Le risque a donc changé de nature : il porte
désormais sur la protection au repos et sur la confidentialité de l'affichage.

| Domaine | État | Commentaire |
| --- | --- | --- |
| Secrets dans le dépôt | ✅ | Aucune clé, aucun jeton, aucun `.env` versionné. La clé de base est générée sur l'appareil. Depuis l'Étape 13, l'identifiant OAuth arrive par `--dart-define-from-file` depuis `secrets/` (ignoré par Git). |
| Données sensibles en clair | ✅ | Le fichier `akiba.db` est chiffré par SQLCipher ; **test dédié** : sans clé, `SELECT` lève `SqliteException`. WAL et journal sont chiffrés par SQLCipher. |
| Clé de chiffrement | 🟠 | 256 bits aléatoires conservés dans `flutter_secure_storage` (Keystore / DPAPI). Pas encore liée au PIN (Étape 2.1), pas encore de rotation (2.4). |
| Masquage des montants | ✅ | Préférence persistée (`montants_masques`) et appliquée à l'accueil, aux analyses, au portefeuille, au profil, aux jauges et aux rappels (§8). |
| Authentification locale (PIN) | 🟠 | Empreinte SHA-256 salée 20 000 tours, PIN triviaux refusés, verrouillage sur pause (§8). La clé de base n'est pas encore dérivée du PIN. |
| Biométrie | 🟠 | `local_auth` avec repli PIN systématique ; limitation des essais non implémentée, non testée sur appareil (§8). |
| Argent de tiers isolé | 🟠 | Règle implémentée et testée (`disponible = comptes + épargne − tiers`, les mouvements neutres sont hors budget du mois). Les écritures ne sont pas encore exposées : Phase 5. |
| Notifications sans montants | ✅ | Messages constants sans FCFA, filtre `sanitize` en plus et test qui parcourt les quatre banques de messages ; planification native non compilée (§8). |
| Sauvegarde chiffrée | 🟠 | AES-256-GCM + PBKDF2 120 000 tours, enveloppe sans clair, restauration additive testée, connexion Google PKCE et `appDataFolder`, Home Lab avec jeton Bearer. Transport des serveurs non imposé TLS et aucun essai réel (§9, §13). |
| Photo de profil | ✅ | Image chiffrée AES-256-GCM dans un fichier dédié, clé maîtresse dans le coffre système, aucune exportation, 4 Mo maximum (§13). |
| Quota IA | ✅ | Compteur daté `ai_quota_date` / `ai_quota_used`, plafond 0–200, repli local sans appel ; testé (§13). |
| Jetons OAuth | 🟠 | Jeton d'accès en mémoire, jeton de rafraîchissement dans le coffre système, déconnexion et `invalid_grant` gérés ; flux non exercé sur le réseau (§13). |
| Synchronisation serveur maître | 🟠 | PUT/GET avec jeton Bearer et contrôle de conflit par `lastMutationAt` ; pas d'API dédiée, pas de LWW complet (§9). |
| Dépendances tierces | 🟠 | Socle : `sqlite3` (SQLCipher/OpenSSL), `flutter_secure_storage`, `path_provider`, `path`. Étapes 7-8 : `crypto`, `cryptography` (AES-GCM/PBKDF2), `local_auth`, `flutter_local_notifications`, `timezone`. Aucune n'ouvre de réseau ni de télémétrie ; les greffons natifs n'ont pas encore été compilés ici. |
| Télémétrie / analytics | ✅ | Aucune. Aucun appel réseau dans le code actuel. |
| Injection SQL | ✅ | Toutes les requêtes du magasin sont **paramétrées** (`?`), aucune concaténation de valeur utilisateur. Les rares concaténations portent sur des constantes du code. |

---

## 2. Contrôles réalisés sur les Étapes 1.1 → 1.3

1. **Chiffrement effectif** : test d'intégration qui chiffre un fichier, le
   rouvre sans clé (échec attendu) puis avec la clé (lecture réussie). Le test
   échouerait si SQLCipher n'était pas réellement compilé.
2. **Gestion de la clé** : `AkibaSecureKey` n'expose la clé qu'en mémoire vers
   `PRAGMA key` ; elle n'est ni journalisée, ni écrite dans un fichier du
   projet. `isHexKey` refuse tout format inattendu et
   `AkibaDatabase.openEncrypted` lève `ArgumentError` sur une clé invalide.
3. **Journalisation** : `main` n'écrit que le **type** de l'erreur d'ouverture
   (`debugPrint('… (${error.runtimeType})')`). Aucun montant, aucun chemin de
   fichier, aucun contenu de base.
4. **Requêtes** : lectures et écritures paramétrées, clés étrangères actives
   (`PRAGMA foreign_keys = ON`), contraintes `CHECK` (montant ≠ 0, objectif ≥ 0,
   montant initial > 0, indicateurs 0/1).
5. **Intégrité des soldes** : aucun champ solde en base ; la vue
   `v_account_balances` additionne les transactions. Un solde ne peut donc pas
   être falsifié par une écriture directe, et les tests couvrent compte,
   épargne et tiers.
6. **Sémantique** : chaque ligne de transaction porte un libellé complet
   (« titre, contexte, montant ») et les avatars décoratifs sont exclus de la
   sémantique.
7. **Aucune permission ajoutée** : les manifestes Android/Windows n'ont pas été
   modifiés. `flutter_secure_storage` utilise le Keystore/DPAPI sans permission
   supplémentaire sur Android.
8. **Aucune saisie utilisateur** pour l'instant : pas de formulaire, donc pas de
   validation d'entrée à auditer (Phases 3 et 4).
9. **Dépendance obsolète retirée** : `sqlcipher_flutter_libs` 0.7.0 (paquet
   EOL, vide) est absent du `pubspec.yaml`.
10. **Chaîne d'approvisionnement** : les binaires SQLite/SQLCipher proviennent
    des releases GitHub de `package:sqlite3`, vérifiées par empreinte SHA-256
    et publiées avec attestations SLSA niveau 3 (voir `doc/hook.md` du paquet).
    La licence SQLCipher/OpenSSL doit être acceptée pour une diffusion.

---

## 3. Exigences à ne pas perdre de vue (à cocher phase par phase)

### Authentification et accès
- [ ] PIN 4→6 chiffres, hash **salé** stocké dans le Keystore (Android) / DPAPI (Windows), jamais en clair ni dans les préférences.
- [ ] Refus des PIN triviaux (0000, 1234, suites, répétitions).
- [ ] Verrouillage automatique au retour d'arrière-plan et après inactivité.
- [ ] Limitation du nombre d'essais (délai croissant), sans destruction de données.
- [ ] Biométrie : repli PIN systématique, aucun secret stocké en clair.
- [ ] Dérivation de la clé de base depuis le PIN, et non plus une clé indépendante.

### Données
- [x] Base chiffrée AES-256 (SQLCipher), clé 256 bits conservée dans le Keystore/DPAPI.
- [ ] Rotation de la clé et restauration d'une base chiffrée par une sauvegarde.
- [ ] Fichiers temporaires, exports et sauvegardes également chiffrés.
- [ ] Purge des exports CSV/JSON après partage.
- [ ] Aucune donnée personnelle dans les journaux ou les rapports de crash.

### Confidentialité de l'affichage
- [ ] Masquage persistant : montants, pourcentages, graphiques et notifications.
- [ ] Aucun montant dans les aperçus de notification quand le masquage est actif.
- [ ] Aperçu multitâche (Android) masqué si l'utilisateur le demande.

### Argent de tiers
- [x] Une entrée neutre n'entre jamais dans le budget du mois (test dédié).
- [x] Le Solde disponible est calculé **toujours** comme comptes + épargne − tiers, jamais saisi.
- [ ] Un reversement ne peut pas dépasser le montant neutre non soldé (contrôle d'écriture, Phase 5).

### IA et SMS
- [ ] Clé Gemini fournie par l'utilisateur, stockée côté serveur/Keystore, jamais dans le code ni dans les assets.
- [ ] Consentement explicite avant envoi d'un texte à l'IA ; possibilité de désactiver totalement.
- [ ] Lecture SMS limitée aux expéditeurs financiers configurés ; aucun SMS stocké hors base chiffrée.
- [ ] Aucun contenu de SMS envoyé à un tiers sans action de l'utilisateur.

### Sauvegarde et synchronisation
- [ ] Phrase secrète de sauvegarde jamais stockée en clair, non récupérable, test de restauration guidé.
- [ ] Chiffrement **côté appareil** avant dépôt sur Drive.
- [ ] API serveur maître : HTTPS, jeton par appareil, révocation, pas d'accès anonyme.
- [ ] Home Lab Backup uniquement sur le Wi-Fi domestique, sans exposition Internet.

### Chaîne de build
- [ ] `flutter pub outdated` traité avant chaque release ; audit des paquets ajoutés.
- [ ] Aucun mode debug ni clé de signature de test dans les builds de production.
- [ ] Permissions Android déclarées au strict nécessaire (SMS, notifications, micro, localisation Wi-Fi) et expliquées à l'utilisateur.
- [x] Vérification `flutter analyze` à 0 et tests verts avant toute livraison.
- [ ] Ouvrir réellement la base sur un appareil Android et sous Windows (le plugin de stockage sécurisé et les binaires natifs n'ont pas été exécutés dans l'application).

---

## 4. Points d'attention identifiés dès maintenant

1. **Logos officiels** : les fichiers fournis (`moov_money.jpg`, `mixx.png`,
   `orabank_dark.png`) sont des marques déposées. Vérifier l'autorisation d'usage
   avant diffusion publique de l'application.
2. **Polices** : l'absence de Poppins/Inter embarquées n'est pas un risque de
   sécurité, mais le repli système doit être vérifié pour ne pas altérer la
   lisibilité des montants (accessibilité AA).
3. **`a_savoir.txt` vide** : s'il devait contenir des consignes de sécurité
   (phrase secrète, serveur, VPN), il doit être complété — et ne jamais contenir
   de secret réel dans le dépôt.
4. **Bouton cochon** : il ouvrira la saisie rapide ; quand elle existera,
   vérifier qu'aucun montant saisi n'est conservé en mémoire après fermeture.
5. **Perte de la clé** = perte des données : aucun mécanisme de récupération
   n'existe encore. La sauvegarde chiffrée (Phase 8) doit être conçue avec une
   phrase secrète indépendante de l'appareil.
6. **Repli silencieux** : si le stockage sécurisé échoue, l'application démarre
   sur une base vide. Il faudra un message explicite (Phase 2.4) pour que
   l'utilisateur ne croie pas avoir perdu ses données.
7. **WAL** : activé pour la performance. SQLCipher chiffre le journal, mais un
   arrêt brutal laisse des fichiers `-wal`/`-shm` : prévoir un checkpoint
   contrôlé lors de la fermeture (Phase 2.4 / 8.1).
---

## 5. Contrôles de l'Étape 4 (saisie rapide)

1. **Validation des montants** : entier uniquement (`digitsOnly`), strictement
   positif, borné à 999 999 999 FCFA. Un transfert exige deux comptes
   distincts. Les erreurs bloquent l'écriture ; les avertissements ne la
   bloquent pas, conformément au cahier des charges.
2. **Argent de tiers** : une saisie « Tiers » écrit `is_neutral = 1`, ce qui
   l'exclut du solde disponible, du budget et des statistiques. Couvert par un
   test de base et par le calcul `BalanceSummary`.
3. **Bandeau d'annulation** : le texte ne contient **aucun montant**
   (« Enregistré · Sortie enregistrée »), pour que le masquage reste effectif
   jusque dans l'aperçu de notification du système.
4. **Annulation** : elle appelle `deleteTransaction` sur les écritures d'origine
   (restauration comprise). Aucun écran ne conserve les contrôleurs de saisie
   après fermeture : ils sont libérés dans `dispose`.
5. **Suppression d'un transfert** : les deux écritures symétriques sont
   supprimées dans la même requête, sinon le total des comptes dériverait.
   Testé.
6. **Requêtes** : les nouvelles suppressions et insertions restent
   paramétrées ; aucun identifiant n'est concaténé dans le SQL.
7. **Budgets** : `saveBudget` supprime puis insère la ligne de la catégorie.
   **Point d'attention** : ces deux ordres ne sont pas dans une transaction
   SQL ; une coupure entre les deux ferait perdre le plafond. À corriger avec
   les autres écritures multi-lignes en Phase 2.4.
8. **Comptes par défaut** : créés uniquement si la table `accounts` est vide ;
   appeler deux fois la méthode ne duplique rien (testé).
9. **Pas de nouvelle permission**, pas de réseau, pas de journal de montant :
   la feuille n'écrit que dans la base chiffrée.
10. **Suppression par glissement** : elle est immédiate et réversible 5 s
    seulement. Risque d'effacement accidentel à arbitrer (confirmation ou
    annulation plus longue, idée 47).

### Points de la checklist impactés

- [x] Aucun montant dans le bandeau d'annulation ni dans les messages d'erreur.
- [x] Une entrée neutre reste hors budget, épargne et statistiques.
- [x] Les montants saisis ne survivent pas à la fermeture de la feuille.
- [ ] Écritures multi-lignes atomiques (transfert, budget) — Phase 2.4.
- [ ] Confirmation ou annulation longue avant suppression définitive.
---

## 6. Contrôles de l'Étape 5 (portefeuille)

1. **Cloisonnement de l'argent de tiers** : le portefeuille affiche le montant
   détenu par tiers, calculé depuis les seules écritures `is_neutral = 1`. Un
   reversement est une sortie neutre : il ne peut pas dépasser ce qui est
   détenu (contrôle dans le dialogue).
2. **Créances et dettes** : elles n'entrent dans aucun total de solde ; le
   texte de l'écran le dit explicitement. Un règlement est plafonné au reste
   dû et ne peut pas rendre `settledAmount` négatif.
3. **Épargne** : un retrait est plafonné au montant réellement épargné
   (somme des transactions `savings` du coffre), jamais au compte.
4. **Aucune donnée dérivée écrite** : comptes, coffres et tiers n'ont pas de
   champ de solde ; tout est recalculé. Une modification manuelle du fichier
   chiffré ne peut donc pas créer un faux solde.
5. **Masquage** : l'œil du portefeuille partage l'état global, y compris les
   totaux, les pourcentages de jauge et les montants des tiers.
6. **Requêtes** : le filtre de période est construit avec des paramètres liés
   (`?`), jamais par concaténation de dates.
7. **Dialogues de saisie** : montants en chiffres seulement, plafonds vérifiés
   avant l'écriture, aucun montant accepté à 0 ou négatif.
8. **Aucune nouvelle permission, aucun réseau** : le portefeuille ne lit que la
   base chiffrée locale.
9. **Point d'attention** : le versement d'épargne et le reversement sont des
   écritures simples, donc atomiques ; en revanche un transfert entre comptes
   reste deux insertions (voir §5.10).
10. **Vie privée de l'aperçu** : les dialogues affichent le montant saisi (c'est
    une action volontaire de l'utilisateur) ; les listes et totaux restent
    masquables.

### Points de la checklist impactés

- [x] Une entrée neutre reste hors budget, épargne et statistiques.
- [x] Un reversement ne peut pas dépasser le montant neutre non soldé.
- [x] Le solde disponible n'inclut jamais les créances ni les dettes.
- [x] Aucun montant de liste en clair quand le masquage est actif.
- [ ] Paliers et simulation de coup dur (M11) — Étape 6/Phase 5 restante.
---

## 7. Contrôles de l'Étape 6 (analyses)

1. **Isolation vérifiée par test** : `categoryTotals`, `accountTotals` et
   `monthlyTotals` excluent les écritures `is_neutral = 1` et les mouvements
   d'épargne. Un test injecte une dépense neutre et un versement d'épargne et
   vérifie qu'ils n'apparaissent dans aucun total.
2. **Bilans** : l'argent de tiers est présenté dans une ligne séparée
   (reçu / reversé) et n'entre ni dans les revenus ni dans les dépenses.
3. **Masquage** : totaux, ventilations, jauges chiffrées et pourcentages
   suivent l'état global ; les pourcentages affichent `••• %`.
4. **Besoins** : le seuil « payable » est calculé à partir du solde disponible
   et de la réserve, jamais saisi comme un solde. Une réserve négative est
   impossible (champ numérique positif ou nul).
5. **Budgets** : plafond strictement positif (contrainte SQL + validation du
   dialogue) ; la suppression est immédiate et ne touche aucune transaction.
6. **Requêtes** : période bornée par paramètres liés ; les seules concaténations
   SQL portent sur des fragments constants choisis dans le code
   (`SUM(-amount)` / `SUM(amount)`).
7. **Aucune écriture comptable depuis les analyses** : l'écran ne crée ni ne
   modifie de transaction, seulement des budgets, des besoins et la réserve.
8. **Point d'attention** : `monthlyTotals` exécute une requête par mois
   (6 ou 12). Coût négligeable sur une base personnelle, mais à surveiller si
   l'historique devient très long.
9. **Aucune nouvelle permission, aucun réseau, aucune télémétrie** : les
   analyses sont entièrement locales.
10. **Réserve** : stockée dans `settings`, donc dans la base chiffrée, jamais
    dans un fichier de préférences en clair.

### Points de la checklist impactés

- [x] Une entrée neutre n'entre jamais dans les statistiques ni dans le bilan.
- [x] Aucun montant ni pourcentage en clair quand le masquage est actif.
- [x] Aucune donnée personnelle dans les journaux.
- [ ] Export du bilan (M17) : devra respecter le masquage et être purgé après
  partage.
- [ ] Notification de seuil de budget : aucun montant si le masquage est actif.
## 8. Contrôles de l'Étape 7 (profil, accès, apparence, rappels)

1. **Le PIN n'est jamais stocké** : `PinVault.setPin` écrit `pin_salt` (128 bits
   aléatoires, `Random.secure`) et `pin_hash` (SHA-256 salé, 20 000 tours). Un
   test vérifie que `pin_hash` n'est pas le PIN en clair.
2. **PIN triviaux refusés** : chiffres identiques, suites `0123` / `4321`,
   longueur < 4 → `ArgumentError`. Longueur 4 à 6 et chiffres uniquement.
3. **Biométrie non bloquante** : toute erreur de `local_auth` (capteur absent,
   greffon indisponible, échec) renvoie faux ; le PIN reste le repli et aucune
   donnée n'est déverrouillée sans lui.
4. **Verrouillage sur pause** : si `lock_on_resume` est actif, `LockGate` se
   reverrouille au retour d'arrière-plan ; le PIN est redemandé.
5. **Réglages sensibles dans la base chiffrée** : le PIN, les jetons de serveur
   et les URLs passent par `settings`, donc par SQLCipher, jamais par un fichier
   de préférences en clair.
6. **Masquage** : la bascule « Afficher les montants » est persistée et
   s'applique à l'accueil, aux analyses, au portefeuille, au profil et aux
   jauges.
7. **Rappels sans données** : les messages sont des constantes sans montant ;
   `ReminderPlanner.sanitize` retire en plus tout « … FCFA » et un test parcourt
   les quatre banques de messages pour vérifier l'absence de `FCFA` / `XOF`.
8. **Fuseau et heures** : heures bornées (0→23, 0→59) ; la plage « Ne pas
   déranger » gère le passage de minuit sans bloquer la journée entière
   (from == to → jamais silencieux).
9. **Aucune nouvelle permission** à l'étape 7 : les notifications demandent
   l'autorisation système au moment de la planification, avec un message clair
   en cas de refus.
10. **Point d'attention** : la biométrie seule ne protège pas la base chiffrée ;
    un accès au système de fichiers peut contourner l'écran de verrouillage. La
    dérivation de la clé de base depuis le PIN (ligne 2.1) reste la vraie
    parade.

### Points de la checklist impactés

- [x] Le code PIN n'est jamais stocké en clair ; l'empreinte est salée et
  itérée.
- [x] Les PIN triviaux sont refusés.
- [x] Aucune notification ne contient de montant.
- [ ] Limitation du nombre d'essais de PIN : non implémentée.
- [ ] Dérivation de la clé de base depuis le PIN : non implémentée.

---

## 9. Contrôles de l'Étape 8 (IA, SMS, sauvegardes)

1. **Aucune exécution automatique** : `AiCommandParser.parse` est une fonction
   pure qui renvoie un `AiDraft` ; seule l'action « Confirmer » de la feuille
   écrit, avec les champs relus par la personne. Aucun interpréteur de commandes
   générique n'est exposé.
2. **Aucun réseau pour l'IA** : l'analyse est locale, sans clé, sans appel HTTP ;
   le micro ne fait qu'afficher un halo et un message (aucun enregistrement).
3. **Argent de tiers** : la proposition porte `isNeutral`, la transaction créée
   reçoit `is_neutral = 1` et un tiers optionnel ; les tests d'isolation
   existants (Étape 5) continuent de la tenir hors budget et hors solde.
4. **SMS sans permission système** : aucun `READ_SMS` ; le texte est collé. Une
   erreur d'analyse produit « à classer », jamais une écriture devinée.
5. **Chiffrement** : AES-256-GCM (`cryptography`), clé PBKDF2-HMAC-SHA256,
   120 000 tours, sel 128 bits, nonce aléatoire par enveloppe. L'enveloppe ne
   contient que du base64 + des métadonnées (dates, appareil, compteurs).
6. **Intégrité** : MAC GCM vérifié au déchiffrement et empreinte SHA-256 du clair
   comparée ; toute anomalie lève `BackupException` avec un message générique
   (« phrase incorrecte ou sauvegarde altérée ») qui n'oriente pas l'attaquant.
7. **Phrase secrète** : 8 caractères minimum, jamais persistée, jamais journalisée.
8. **Secrets exclus** : `pin_hash`, `pin_salt`, `master_token`, `lab_token` et
   `restore_pending_at` sont dans `excludedSettings` — ni exportés ni restaurés.
   Un test vérifie l'absence de `pin_hash` dans la charge utile.
9. **Restauration non destructive** : ajout uniquement, identifiants existants
   ignorés ; aucun `DELETE`. Deux restaurations successives ne créent aucun
   doublon (testé).
10. **Conflit** : `BackupMetadata.isNewerThan` compare `lastMutationAt` ; l'UI
    demande confirmation avant d'écraser ou de restaurer. Aucune fusion
    silencieuse.
11. **Transport** : serveur maître et Home Lab en HTTPS/PUT explicites avec jeton
    Bearer ; Google Drive passe par un dossier local synchronisé, donc la
    confidentialité dépend du fournisseur de synchronisation — à documenter pour
    la personne qui l'utilise.
12. **Point d'attention** : les jetons de serveur sont stockés dans la base
    chiffrée mais affichés dans un champ de texte du Profil ; sur un appareil
    partagé, cela reste visible une fois déverrouillé. Aucun masquage dédié.

### Points de la checklist impactés

- [x] L'IA ne fait jamais d'écriture sans confirmation explicite.
- [x] Aucune donnée ne part sans action de la personne.
- [x] Les sauvegardes sont chiffrées de bout en bout et vérifiées en intégrité.
- [x] Une restauration ne supprime jamais de données locales.
- [x] L'argent de tiers issu d'un SMS ou de l'IA reste isolé.
- [ ] Chiffrement du transport vers le serveur maître / Home Lab : dépend de
  l'URL fournie (HTTPS non imposé par le code).
- [ ] Révocation / rotation des jetons : manuelle (ressaisie).

---

## 10. Contrôles de l'Étape 9 (onboarding, animations, global)

1. **Aucun contournement de l'accès** : après l'onboarding, `LockGate` est monté
   avant `AkibaShell` ; le dashboard n'existe pas dans l'arbre tant que le PIN
   n'est pas vérifié.
2. **Reprise d'onboarding** : `onboarding_step` ne contient qu'un entier (aucune
   donnée personnelle) ; le prénom et le nom ne sont écrits qu'à l'étape E3.
3. **Soldes d'ouverture** : créés en transactions `opening`, jamais en modifiant
   directement un solde ; un champ vide n'écrit rien.
4. **PIN d'onboarding** : mêmes règles que le Profil (refus des PIN triviaux) ;
   « Plus tard » laisse l'accès direct, ce qui est annoncé dans l'interface.
5. **Mode simulation** : réglage explicite + bandeau permanent sur les quatre
   onglets ; aucune donnée réelle n'est présentée comme fictive ni l'inverse.
6. **Animations** : toutes pilotées par `MediaQuery.disableAnimations`, donc
   coupables par le réglage système ou par « Réduire les animations ». Aucune
   animation ne porte d'information nécessaire.
7. **Masquage** : les jauges gardent leur forme et leurs paliers mais affichent
   `•••••• FCFA` ; les paliers 25/50/75 % ne révèlent aucun montant.
8. **Repli de stockage** : si la base chiffrée ne s'ouvre pas, `EmptyAkibaStore`
   prend le relais et l'interface reste utilisable sans écrire nulle part.
9. **Cohérence** : barre basse pleine largeur, cochon latéral, IA juste au-dessus,
   aucun écran ne flotte au-dessus de la barre (marge basse de défilement).
10. **Point d'attention** : sans exécution graphique, ni les transitions, ni le
    rendu à 360 px / 1 280 px, ni le comportement réel du verrouillage au retour
    d'arrière-plan n'ont été observés.

### Points de la checklist impactés

- [x] Le dashboard n'est accessible qu'après l'onboarding et le déverrouillage.
- [x] Aucun montant dans les notifications ni dans les messages système.
- [x] Les animations se coupent sur demande et au niveau système.
- [x] Aucune télémétrie, aucun réseau ajouté par l'onboarding.
- [ ] Contrôle visuel mobile / grand écran : non réalisé.
- [ ] Test de verrouillage au retour d'arrière-plan sur appareil : non réalisé.
## 11. Contrôles de l'Étape 10 (revue complète et release)

1. **Analyse statique** : `flutter analyze` sans aucun problème après les
   modifications (devises, dettes, manifeste, icônes).
2. **Isolation de l'argent de tiers** : réexaminée sur les agrégats et les
   écrans. `available = comptes − tiers`, les écritures `is_neutral = 1` sont
   exclues du budget, des statistiques et des mouvements « normaux ». Deux tests
   couvrent désormais l'ajout simultané d'une créance et d'une dette.
3. **Créances et dettes** : le sens est stocké tel quel (`owedToMe` / `iOwe`,
   `fromStorage` sans heuristique), les montants restent **hors** du solde
   disponible et du budget, le reste dû affiché au règlement respecte le
   masquage. Aucun effet de bord sur les comptes.
4. **Masquage** : les montants des rappels n'existent pas ; `sanitize` retire
   tout `… FCFA` résiduel, et un test parcourt les quatre banques de messages.
   Les pourcentages, jauges et soldes suivent `MaskedAmounts`.
5. **Devises et réseau** : c'est le **seul** appel réseau ajouté ces dernières
   étapes (`https://flagcdn.com/w160/<région>.png`). Il part sans identifiant,
   sans cookie, sans en-tête personnalisé, uniquement pour quatre devises
   connues. Le logo est mis en cache dans le dossier de support de
   l'application ; hors ligne, un jeton typographique le remplace. Le choix de
   la devise reste dans la base chiffrée.
6. **Aucune conversion de devise** : le libellé change, la valeur non. Une
   devise différente ne crée donc pas de montant faux ; c'est une limite
   assumée, écrite dans l'UI et dans `DEJA_FAIT.md`.
7. **Durcissement release Android** :
   - `allowBackup="false"` + `fullBackupContent="false"` : plus de copie système
     de la base chiffrée vers un cloud dont la clé ne suivrait pas.
   - `READ_SMS` absent, la revue SMS reste un collage manuel.
   - `INTERNET` déclaré : nécessaire aux logos et aux sauvegardes distantes.
   - Aucun `usesCleartextTraffic` : le trafic HTTP en clair reste bloqué par
     Android 9+, donc un Home Lab en `http://` doit passer en HTTPS (limite à
     documenter pour le porteur).
   - `applicationId` propre (`com.akiba.app`) et signature release par
     `android/key.properties` quand il existe ; **sinon repli debug explicite**,
     qui ne doit pas servir à publier.
8. **Windows** : titre et métadonnées AKIBA, icône multi-tailles ; aucune
   signature de code (certificat à fournir). L'exécutable reste `akiba.exe`.
9. **Icônes** : générées localement depuis l'emblème du dépôt, sans service
   tiers ; le script est reproductible et ne contient aucun secret.
10. **Points d'attention restants** :
    - la build release n'a pas été compilée (mode développeur Windows absent) ;
    - les permissions Android et la biométrie n'ont pas été exercées sur
      appareil ;
    - un Home Lab en HTTP sera refusé par Android ;
    - le CDN de logos apprend quelle devise a été choisie (métadonnée mineure,
      mais réelle) ; un mode 100 % local consisterait à embarquer les quatre
      images.

### Points de la checklist impactés

- [x] L'argent de tiers reste isolé du solide disponible et du budget.
- [x] Les créances et dettes ne modifient pas le solde disponible.
- [x] Le masquage couvre les rappels et le reste dû affiché.
- [x] Les permissions demandées sont minimales et justifiées.
- [x] `READ_SMS` n'est pas demandé.
- [x] La sauvegarde système Android est désactivée.
- [ ] Signature release réelle (clé du porteur) : à faire avant publication.
- [ ] Compilation et installation release sur Android et Windows : non faites.

## 12. Contrôles de l'Étape 11 (clé IA, cascade, dettes)

1. **Clé API au repos** : chiffrée **avant** écriture (AES-256-GCM, nonce
   aléatoire, format `nonce.mac.chiffré`) puis stockée dans un réglage de la
   base SQLCipher. La clé maîtresse de 32 octets vit dans le coffre du système
   (Keystore / DPAPI), jamais dans la base ni dans un fichier de projet.
2. **Aucune fuite d'affichage** : l'UI montre `••••••••` et une date ; le champ
   de saisie est masqué et vidé après enregistrement ; aucun message d'erreur
   ne reprend la clé ; l'URL d'appel (qui la contient) n'est jamais journalisée.
3. **Non-export** : `ai_api_key_sealed` et `ai_api_key_updated_at` sont dans
   `BackupService.excludedSettings` ; une enveloppe restaurée ailleurs ne
   contient donc pas la clé (sa clé maîtresse ne suivrait pas).
4. **Intégrité** : `AiKeyVault.open` renvoie `null` sur valeur altérée, nonce
   tronqué ou clé maîtresse différente — testé. Aucun détail n'est remonté.
5. **Coffre indisponible** : exception explicite `AiKeyException`, aucun repli
   en clair sur disque. Limite : non exercé sur appareil.
6. **Portée réseau** : les appels distants sont **désactivés par défaut**
   (`ai_remote_enabled = 0`). Quand ils sont activés, seule la phrase saisie
   part ; aucun solde, transaction, nom de compte ni réglage.
7. **Mode masqué** : aucun appel distant n'est effectué si le masquage est
   actif — la phrase peut contenir un montant. Repli local silencieux.
8. **Aucune écriture par l'IA** : le client renvoie du texte, l'interface le
   transforme en carte éditable ; `store.saveTransaction` n'est appelé que par
   « Confirmer ».
9. **Cascade maîtrisée** : un essai par modèle, plafond de 3 (1 à 5), arrêt
   immédiat sur 401/403 pour ne pas multiplier les requêtes refusées, veille de
   10 minutes après deux échecs consécutifs (protection quota et batterie).
10. **Données de tiers et dettes** : un emprunt reçu est écrit en transaction
    **neutre**, donc exclu du solde disponible, du budget et des statistiques ;
    un prêt accordé est une sortie normale. Aucune dette ne modifie
    directement un solde (toujours dérivé des transactions).
11. **Réversibilité** : « Annuler » supprime la dette créée et son mouvement
    (`deleteDebt` + `deleteTransaction`), ou restaure le `settledAmount`
    précédent ; aucune suppression d'un autre enregistrement.
12. **Confidentialité des rappels** : les messages d'échéance ne contiennent
    aucun montant ni nom de contact ; `ReminderPlanner.sanitize` retire tout
    `… FCFA` résiduel.
13. **Points d'attention** :
    - le stockage sécurisé n'a pas été exercé sur appareil ;
    - `ai_quota_per_day` n'est pas appliqué, le plafond réel est celui du
      fournisseur ;
    - la veille des modèles est en mémoire : un redémarrage la réinitialise
      (comportement voulu, documenté) ;
    - un modèle distant voit la phrase saisie : c'est un choix explicite de la
      personne, rappelé dans les réglages.

### Points de la checklist impactés

- [x] La clé API n'est jamais stockée en clair ni affichée.
- [x] La clé ne part pas dans une sauvegarde.
- [x] Aucune écriture n'est faite sans confirmation humaine.
- [x] Le mode masqué interdit tout envoi distant.
- [x] L'argent emprunté reste hors du solde disponible.
- [x] Les rappels d'échéance ne contiennent aucun montant.
- [ ] Test du coffre système et d'un appel réel : non réalisés (pas de clé sur
  le poste).

---

## 13. Contrôles de l'Étape 12 (quota, photo, Google, Home Lab)

1. **Simplification sans affaiblissement** : le chiffrement AES-256-GCM et la
   gestion de clé maîtresse ont été **factorisés** (`AesBox`, `SecureMasterKey`) ;
   la clé API conserve ses tests (altération, autre clé, valeur illisible).
   Aucune vérification n'a été retirée pour faire passer un test.
2. **Quota local** : compteur `ai_quota_date` + `ai_quota_used` en base
   chiffrée ; la remise à zéro est implicite (date différente), donc pas d'appel
   réseau ni de tâche de fond. Une unité est réservée uniquement après lecture
   réussie de la clé, donc jamais en mode masqué ni distant désactivé.
3. **Repli** : quota atteint → analyse locale et mention discrète ; aucune
   exception, aucun blocage, aucune donnée envoyée.
4. **Photo de profil** : encodage base64 puis AES-256-GCM ; le fichier
   `profile/avatar.sealed` ne contient aucun pixel lisible. La clé maîtresse
   reste dans le coffre système et le fichier n'est **pas** dans les
   sauvegardes. Le retrait efface fichier et clé.
5. **Pas de fuite de photo** : aucun envoi réseau, aucune miniature distante,
   aucune inclusion dans l'enveloppe ; l'affichage se fait depuis la mémoire.
6. **Écran de verrouillage** : la photo et le prénom n'apparaissent que sur
   l'écran verrouillé ; le PIN reste obligatoire, la photo ne déverrouille rien.
7. **Google** : PKCE S256, redirection sur la boucle locale uniquement, écoute
   limitée à `127.0.0.1`, arrêt du serveur après le retour, délai de 3 minutes.
   Aucun secret client n'est requis ni embarqué.
8. **Portée minimale** : `drive.appdata` seulement ; l'application ne peut pas
   lire le reste du Drive. L'enveloppe déposée est déjà chiffrée : Google ne
   voit que du chiffré, la phrase secrète reste locale.
9. **Jetons** : jeton d'accès en mémoire ; jeton de rafraîchissement et adresse
   dans le coffre système ; aucun jeton dans la base, les journaux ou les
   fichiers du projet. `invalid_grant` déconnecte au lieu de boucler.
10. **Home Lab** : jeton en en-tête `Authorization: Bearer`, jamais dans l'URL ;
    `PUT`/`GET` de l'enveloppe chiffrée ; « Vérifier » lit sans écrire et sans
    phrase secrète ; 404 traité comme « aucune sauvegarde ». Un test fait
    l'aller-retour complet contre un serveur HTTP local : jeton reçu, enveloppe
    sans montant en clair, déchiffrement réussi avec la phrase secrète.
11. **Dépendances ajoutées** : `image_picker` et `url_launcher` (plus leurs
    implémentations de plateforme). Elles n'ajoutent ni télémétrie ni accès
    réseau autonome ; `url_launcher` n'ouvre que l'URL de consentement Google
    construite par l'application.
12. **Points d'attention** :
    - le flux Google et l'envoi Drive n'ont pas été exercés (pas d'identifiants) ;
    - aucun serveur Home Lab réel n'a été joint ;
    - Android refuse le HTTP en clair : un Home Lab doit être en HTTPS ;
    - les greffons natifs ne sont pas compilés ici (mode développeur Windows
      absent) ;
    - le sélecteur d'images donne accès à la photothèque : c'est un choix
      explicite de la personne, aucune lecture automatique.

### Points de la checklist impactés

- [x] La photo de profil ne quitte jamais l'appareil et reste chiffrée au repos.
- [x] Le quota IA empêche les appels au-delà du plafond quotidien.
- [x] Les jetons Google ne sont jamais écrits en clair dans le projet.
- [x] La sauvegarde Drive reste chiffrée de bout en bout.
- [ ] Connexion Google réelle et envoi Drive non testés (identifiants à fournir).
- [ ] Home Lab réel non joint ; TLS dépend de l'URL fournie.

---

## 14. Contrôles de l'Étape 13 (identifiant OAuth, thèmes)

1. **Aucun secret dans le code suivi** : le `client_secret_*.json` et le
   dossier `secrets/` sont ignorés par Git ; `GoogleOAuthConfig` ne contient
   qu'un repli vide et lit `String.fromEnvironment`. L'identifiant du client
   de bureau n'est donc présent que dans `secrets/google_oauth.json`, jamais
   dans `lib/`.
2. **Portée du client** : type `installed` (application de bureau), **sans
   secret** ; l'échange de jetons n'envoie `client_secret` que s'il existe.
   La portée reste `drive.appdata` : rien d'autre du Drive n'est lisible.
3. **Transport** : PKCE S256, redirection `http://127.0.0.1:<port>` seulement,
   écoute limitée à la boucle locale, arrêt du serveur après le retour.
4. **Chiffrement de bout en bout** : l'enveloppe déposée sur Drive reste
   AES-256-GCM avec une phrase secrète locale ; Google ne reçoit que du
   chiffré et l'identité du compte.
5. **Jetons** : jeton d'accès en mémoire, jeton de rafraîchissement dans le
   coffre système, jamais dans la base, les journaux ou les fichiers.
6. **Thèmes et lisibilité** : les cinq palettes sont vérifiées par test
   (titres ≥ 10:1, textes secondaires ≥ 4.5:1, texte clair sur action ≥ 3:1).
   Aucun thème ne dépend d'un réglage système qui pourrait dégrader le
   contraste ; tout identifiant inconnu retombe sur Blanc.
7. **Invariants d'interface** : barre basse pleine largeur ancrée (non
   flottante), cochon latéral avec l'icône IA au-dessus, logos Flooz / Mixx by
   Yas / Orabank dans leur tuile blanche — identiques dans les cinq thèmes.
8. **Points d'attention** :
   - l'identifiant OAuth est un identifiant public de client, mais il est
     traité comme une donnée de configuration privée : ne pas le recopier dans
     un fichier versionné ;
   - un téléphone ADB sans fil reste exposé à toute machine du réseau qui
     connaît son port : couper le débogage sans fil après la recette ;
   - le flux Google complet (consentement, dépôt, restauration) n'a pas été
     exercé : à refaire sur appareil.

### Points de la checklist impactés

- [x] Aucun identifiant OAuth ni secret client versionné.
- [x] Sauvegarde Drive toujours chiffrée AES-256-GCM, portée `appDataFolder`.
- [x] Contraste des cinq thèmes contrôlé par test automatisé.
- [x] Barre basse et boutons latéraux conformes dans les cinq thèmes (code).
- [ ] Connexion Google réelle et contrôle visuel des thèmes sur appareil.
