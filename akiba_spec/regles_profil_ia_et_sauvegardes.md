# Règles — photo de profil, quota IA, Google Drive et Home Lab

Référence : `Cahier des charges AKIBA.md` v2.0 (E7, E10, F19, M12, M19, M22) et
`regles_modules_ia_et_dettes.md`. Cette annexe fixe les règles appliquées à
l'**Étape 12** et sert de contrat pour les étapes suivantes.

---

## 1. Photo de profil locale

| Règle | Application |
| --- | --- |
| Stockage | fichier unique `profile/avatar.sealed` dans le dossier de support de l'application, **chiffré AES-256-GCM** |
| Clé | clé maîtresse de 32 octets aléatoires dans `flutter_secure_storage` (Keystore / DPAPI), nom `akiba_profile_photo_key` |
| Format | base64 de l'image, puis `nonce.mac.chiffré` ; aucun pixel lisible sur le disque |
| Taille | 4 Mo maximum, refus explicite au-delà ; l'image est réduite à 1 024 px et recompressée avant import |
| Affichage | en-tête de l'accueil, écran Profil, **écran de verrouillage** quand le PIN est activé |
| Absence | avatar par défaut : initiale du prénom sur tuile terre cuite, ou silhouette si le prénom est vide |
| Retrait | « Retirer » efface le fichier **et** la clé maîtresse ; l'avatar par défaut reprend sa place immédiatement |
| Sauvegarde | la photo **n'est pas** incluse dans les enveloppes ; `profile_photo_updated_at` est exclu de `BackupService` |
| Réseau | aucun envoi, aucune miniature distante, aucune métadonnée exportée |
| Échec | coffre indisponible ou image illisible → message clair, aucune écriture, aucun repli en clair |

Règles d'usage :

1. La photo ne remplace jamais le PIN : l'écran de verrouillage affiche la photo
   **et** exige le code.
2. Le choix de l'image passe par le sélecteur du système (`image_picker`) ; sur
   Android 13+ le sélecteur de photos ne demande aucune permission de galerie.
3. Changer de photo remplace l'ancienne (une seule photo par appareil).

---

## 2. Quota IA journalier (`ai_quota_per_day`)

| Règle | Application |
| --- | --- |
| Unité | **une analyse distante** = une unité, quel que soit le nombre de modèles essayés par la cascade |
| Compteur | réglages `ai_quota_date` (`aaaa-mm-jj`) et `ai_quota_used` |
| Remise à zéro | implicite : si la date enregistrée n'est plus le jour civil courant, l'usage repart à 0 sans écriture |
| Plafond | `ai_quota_per_day`, 0 à 200, 20 par défaut ; 0 = aucun appel distant |
| Moment | l'unité est réservée **après** la lecture de la clé et **avant** l'envoi ; un échec compte |
| Quota atteint | repli local immédiat, mention `Analyse locale · quota du jour atteint`, aucune erreur, aucun blocage |
| Mode masqué | aucun appel, donc aucune unité consommée |
| Distance désactivée | `ai_remote_enabled = 0` → aucune unité consommée |
| Affichage | dans « Clé et modèles » : `n / plafond aujourd'hui` + explication, réglage par − / + |
| Abaissement du plafond | l'usage affiché est plafonné à la nouvelle valeur ; le compteur n'est jamais réinitialisé à la main |

Le quota local protège la personne **et** son crédit fournisseur : il ne
remplace pas le quota du fournisseur, il s'y ajoute.

---

## 3. « Se connecter avec Google » et sauvegarde Drive

### 3.1 Configuration des identifiants

Un seul fichier : `lib/core/config/google_oauth_config.dart`.

1. Client OAuth de type **Application de bureau** dans Google Cloud Console.
2. API Google Drive activée.
3. Identifiant collé dans `clientIdPlaceholder` (ou fourni par
   `--dart-define=AKIBA_GOOGLE_CLIENT_ID=…`).
4. Secret facultatif ; les clients de bureau récents utilisent PKCE sans secret.

Aucun identifiant n'est présent dans le dépôt : le fichier est livré vide et
`GoogleOAuthConfig.isConfigured` reste faux tant qu'il n'est pas rempli. Dans ce
cas, l'application est **100 % hors ligne** et le centre de sauvegarde propose le
dossier Drive synchronisé de l'appareil.

### 3.2 Connexion

| Règle | Application |
| --- | --- |
| Flux | code d'autorisation + **PKCE S256**, redirection sur la boucle locale `http://127.0.0.1:<port>/oauth2callback` |
| Port | éphémère (0), donc aucune collision ni port fixe à ouvrir |
| Délai | 3 minutes, puis message « Connexion Google expirée » |
| Annulation | `access_denied` → « Connexion Google annulée », aucun état modifié |
| Jetons | jeton d'accès en mémoire uniquement ; jeton de rafraîchissement dans le coffre du système (`akiba_google_refresh_token`) |
| Adresse | e-mail lu dans l'`id_token` pour l'affichage seulement, jamais vérifié comme preuve d'identité |
| Déconnexion | efface le jeton de rafraîchissement et l'adresse ; `google_linked = 0` |
| Hors ligne | message clair, aucune exception technique, l'application reste utilisable |
| Révocation | `invalid_grant` → déconnexion automatique, message « reconnectez-vous » |

### 3.3 Périmètre et confidentialité

- Portée unique de données : `drive.appdata` — l'application **ne peut pas** lire
  ni lister le reste du Drive de la personne.
- La sauvegarde déposée est l'enveloppe **déjà chiffrée AES-256-GCM** (PBKDF2
  120 000 tours) : Google ne voit que du chiffré, la phrase secrète ne quitte
  jamais l'appareil.
- Nommage `akiba-AAAAMMJJ-HHMMSS.akiba` ; **cinq** sauvegardes conservées, les
  plus anciennes sont supprimées.
- Aucun jeton, aucune adresse et aucune taille de fichier n'est journalisée.
- La restauration Drive suit les mêmes règles que les autres cibles : additive,
  confirmée, jamais destructive, contrôle de conflit par `lastMutationAt`.

---

## 4. Home Lab Backup (serveur local)

| Règle | Application |
| --- | --- |
| Configuration | `lab_url` (URL complète de l'endpoint) + `lab_token`, saisis dans le centre de sauvegarde, onglet « Home Lab » |
| Jeton | en-tête `Authorization: Bearer …`, jamais dans l'URL ni dans un journal ; champ masqué à la saisie |
| En-tête technique | `X-Akiba-Backup: AES-256-GCM` pour que le serveur vérifie le type d'enveloppe |
| Écriture | `PUT` de l'enveloppe chiffrée ; réponse 2xx exigée, sinon message avec le code HTTP |
| Lecture | `GET` de la même URL ; 404 = « aucune sauvegarde », traité sans erreur |
| Test | « Vérifier » lit et affiche date, compteurs et conflit **sans rien écrire** ; aucun déverrouillage de la phrase secrète n'y est nécessaire |
| Réseau | même Wi-Fi domestique, sans VPN ni exposition Internet ; le porteur doit publier une URL HTTPS |
| Android | le HTTP en clair est refusé par le système : utiliser HTTPS (certificat local accepté par l'appareil) |
| Délais | connexion 12 s, réponse 20 s, message dédié en cas de dépassement |
| Erreurs | serveur injoignable, jeton refusé, format illisible → messages distincts, aucun détail technique |
| Confidentialité | le serveur ne reçoit que du chiffré et ne connaît ni la phrase secrète ni la clé |
| Restauration | additive, confirmée, identifiants existants ignorés, aucun `DELETE` |

---

## 5. Simplifications appliquées (relecture de l'Étape 11)

| Simplification | Effet |
| --- | --- |
| `lib/core/security/aes_box.dart` | une seule implémentation AES-256-GCM + une seule gestion de clé maîtresse, partagées par la clé API et la photo ; `AiKeyVault.seal/open` restent disponibles pour les tests |
| `AiModelCatalog` | suppression de `priority`, `defaultPriority`, `encodePriority` et `move`, jamais appelés en production ; une seule fonction d'ordre, `selected` |
| `AiFailureKind` | suppression de la valeur `noKey`, redondante avec le contrôle « clé absente » de l'assistant ; `isTerminal` ne garde que `auth` |
| `AkibaAiClient` | suppression du getter `sleeping`, non utilisé ; `isSleeping` suffit |
| Coffre IA | `AiKeyVault` ne réimplémente plus le hexadécimal ni le déchiffrement : 40 lignes en moins, comportement identique (tests inchangés) |

---

## 6. Ce qui reste non vérifié

- Aucun compte Google réel n'a été connecté : le flux PKCE, l'échange de jetons
  et l'envoi Drive n'ont pas été exercés sur le réseau.
- Aucun serveur Home Lab réel n'a reçu d'enveloppe ; seul un aller-retour
  `PUT`/`GET` contre un serveur HTTP local de test a été exécuté.
- La photo n'a pas été importée ni affichée sur un appareil (pas de contrôle
  visuel) ; le chiffrement/déchiffrement repose sur `AesBox`, testé.
- Les greffons natifs (`image_picker`, `url_launcher`) ne sont pas compilés sur
  ce poste : le mode développeur Windows (liens symboliques) reste absent.

---

## 7. Format de sortie de l'IA

| Règle | Application |
| --- | --- |
| Un seul nettoyeur | `AiText` (`lib/core/ai/ai_text.dart`) est le seul endroit qui transforme une réponse de modèle en texte affichable ou imprimable |
| Formats tolérés | objet JSON (`conseil_financier`, `avis`, `conseils`…), liste de conseils, fences ``` et Markdown |
| Interdits à l'écran | accolades, guillemets JSON, astérisques Markdown, puces dupliquées |
| Réponse vide | message explicite « hors format », jamais une carte vide |
| Rapport PDF | l'avis du modèle est injecté tel quel (nettoyé) quand il est lisible ; le repli local ne sert qu'en cas d'absence ou d'erreur réelle |
| Montants | jamais inventés par le nettoyeur ; seuls les montants déjà présents dans la réponse sont mis en gras |

---

## 8. Actions de l'assistant

| Action | Écriture | Garde-fou |
| --- | --- | --- |
| Dépense / entrée | une transaction sur le compte choisi | carte relue, montant éditable |
| Transfert | deux écritures symétriques | comptes source et destination différents |
| Argent de tiers | transaction neutre, hors solde/budget/statistiques | case « Tiers » |
| Créance / dette | ligne `debts`, hors trésorerie | sens déduit de la phrase, jamais inversé par un modèle |
| Règlement | mouvement réel + mise à jour du reste dû | ligne existante sélectionnée |
| Versement
| Versement d'épargne | transaction `savings` rattachée à un coffre | coffre « Épargne libre » créé au besoin |
| Objectif d'épargne récurrent | `SavingsPot` de type `goal` + rythme mémorisé | prix demandé, aucun débit automatique |

- Une phrase de rythme (« par jour ») est traitée **localement avant** tout
  modèle distant : elle ne peut pas devenir une dépense.
- Le modèle distant ne reçoit jamais un montant en mode masqué ; ses réponses
  restent des propositions relues.
- « Faire n'importe quoi » se limite aux écritures listées : l'assistant ne
  modifie ni les thèmes, ni les réglages, ni les écrans hors de ce catalogue.

---

## 9. Code à 4 chiffres du serveur de sauvegarde

| Règle | Application |
| --- | --- |
| Quand il est demandé | une fois à la configuration Home Lab (étape 2), puis à chaque restauration |
| Où il vit | coffre du système (`akiba_backup_code`), jamais dans les réglages, l'enveloppe ou les journaux |
| Ce qu'il chiffre | enveloppe version 4, `kdf: PBKDF2-CODE`, sel aléatoire de 16 octets, PBKDF2-SHA256 120 000 tours |
| Ce qu'il remplace | la dépendance au compte Google pour les sauvegardes du serveur ; Drive garde son propre chemin |
| Oubli | aucune récupération possible : nouvelle sauvegarde avec un nouveau code, `latest.json` remplacé, redépart à zéro |
| Limite | 10 000 combinaisons : protège d'une lecture accidentelle, pas d'un attaquant patient avec le fichier |
