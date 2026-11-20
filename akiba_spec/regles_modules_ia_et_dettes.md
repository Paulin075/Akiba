# Règles formalisées — module IA et module Créances et dettes

Référence : `Cahier des charges AKIBA.md` v2.0, `akiba_animations_notifications_regles..txt`.
État : **20/11/2026**. Ces règles complètent les Étapes 8 à 10 ; elles
s'appliquent aux modules déjà livrés sans modifier les étapes suivantes.

---

## 1. Module IA — clé API de la personne

### 1.1 Où la clé est demandée

`Profil → Assistant IA → « Clé et modèles »` (`lib/features/assistant/ai_settings_sheet.dart`).
Aucun autre écran ne saisit, n'affiche ni ne transmet la clé.

### 1.2 Ce qui est stocké

| Élément | Emplacement | Protection |
| --- | --- | --- |
| Clé API | réglage `ai_api_key_sealed` (table `settings`, base SQLCipher) | chiffrée **avant** écriture, AES-256-GCM, nonce 96 bits aléatoire par valeur, format `base64(nonce).base64(mac).base64(chiffré)` |
| Clé maîtresse 32 octets | `flutter_secure_storage` (`akiba_ai_master_key`) | Keystore Android / DPAPI Windows |
| Date de remplacement | `ai_api_key_updated_at` | date seule, jamais la clé |
| Liste des modèles | `ai_models_cache` + `ai_models_cached_at` | identifiants et libellés publics |
| Ordre et sélection | `ai_model_priority` (identifiants séparés par des virgules) | aucun secret |
| Appels distants autorisés | `ai_remote_enabled` (`0` par défaut) | choix explicite |

Règles :

1. **Jamais en clair sur disque.** La clé n'est écrite qu'une fois chiffrée ;
   la clé maîtresse ne quitte pas le coffre du système.
2. **Jamais affichée.** L'interface montre `••••••••` et la date de dernier
   remplacement. Le champ de saisie est masqué (`obscureText`) avec un bouton
   œil temporaire, vidé dès l'enregistrement.
3. **Jamais journalisée.** Ni la clé, ni l'URL complète (elle la contient), ni
   le corps des requêtes ne passent dans un log ou un message d'erreur.
4. **Jamais sauvegardée.** `ai_api_key_sealed` et `ai_api_key_updated_at` sont
   dans `BackupService.excludedSettings` : une enveloppe restaurée sur un autre
   appareil ne pourrait pas la déchiffrer (autre clé maîtresse), elle ne la
   contient donc pas.
5. **Remplaçable et effaçable.** « Remplacer » écrase l'ancienne valeur ;
   « Effacer » supprime la valeur chiffrée, la clé maîtresse et coupe les
   appels distants.
6. **Testable.** « Tester » appelle `models.list` : il valide la clé, récupère
   les modèles et remplit le cache. Un échec n'efface jamais la clé.
7. **Contrôle de forme local** avant tout appel : vide, moins de 20 caractères,
   plus de 400 ou contenant un espace → refus avec message clair.
8. **Coffre indisponible** (stockage sécurisé refusé) : message explicite, pas
   de repli en clair.

### 1.3 Liste des modèles

- Récupérée avec la clé (`GET /v1beta/models`), filtrée sur
  `supportedGenerationMethods` contenant `generateContent`, dédoublonnée.
- Mise en cache dans la base chiffrée ; en cas d'échec réseau, le cache (ou les
  quatre modèles de départ) reste utilisé : l'assistant ne devient jamais
  inutilisable.
- L'ordre de priorité est **configurable** : cases à cocher + flèches
  monter/descendre. Seuls les modèles cochés sont essayés, dans cet ordre.
  Un identifiant enregistré mais absent du catalogue est ignoré.

---

## 2. Module IA — délais, cascade et repli

### 2.1 Délais par tâche

| Tâche | Délai | Usage |
| --- | --- | --- |
| `quickEntry` | **5 s** | saisie rapide d'une opération, assistant |
| `smsReview` | **6 s** | classement d'un SMS collé |
| `analysis` | **10 s** | analyse, bilans |
| `coaching` | **12 s** | conseils, coaching |

Les tâches courtes restent dans la fenêtre 4–6 s, les analyses dans 8–12 s.

### 2.2 Cascade

1. Un seul essai par modèle, modèles pris dans l'ordre de priorité.
2. **Plafond d'essais** : 3 par défaut, réglable de 1 à 5.
3. Bascule sur le modèle suivant si : délai dépassé, `429` (quota / débit),
   `5xx`, erreur réseau, réponse vide ou illisible.
4. **Arrêt immédiat** si `401`/`403` : la clé est refusée, insister n'a aucun
   sens et multiplierait les appels.
5. **Mise en veille** : un modèle qui échoue **deux fois de suite** est écarté
   pendant **10 minutes** ; il revient ensuite automatiquement.
6. Aucun modèle en veille n'est sollicité : `AkibaAiClient.chain` les retire.

### 2.3 Repli

- Échec de la cascade → l'analyse **locale** (`AiCommandParser`) produit la
  carte de compréhension. L'application ne bloque jamais, aucun écran d'erreur.
- Indication discrète : `Modèle : <identifiant>` en cas de succès,
  `Analyse locale · <raison>` sinon. Jamais de code HTTP ni de détail technique.
- **Aucune écriture** n'est faite par un appel IA : la proposition reste une
  carte éditable, et seule l'action « Confirmer » écrit.
- **Mode masqué** : si le masquage est actif, **aucun appel distant** n'est
  fait (la phrase peut contenir un montant). Seule la phrase tapée est envoyée,
  jamais les soldes, transactions ou noms de comptes.
- Le réglage `ai_quota_per_day` existe mais n'est pas encore appliqué : le
  plafond réel reste celui du fournisseur.

---

## 3. Module Créances et dettes

### 3.1 Sens exact

- Sélecteur à deux positions `« On me doit »` / `« Je dois »`, index =
  `DebtDirection.values[index]` (`owedToMe`, `iOwe`), stocké tel quel et relu
  par `fromStorage` sans heuristique.
- Le texte sous le sélecteur dit ce que le sens implique pour le solde.

### 3.2 Avec ou sans mouvement de trésorerie

| Cas | Case « mouvement immédiat » | Écriture |
| --- | --- | --- |
| Prêt accordé (« on me doit », argent sorti) | cochée | sortie **normale** sur le compte choisi (`-montant`), le solde baisse réellement |
| Crédit / service (« on me doit », rien n'est sorti) | décochée | aucune écriture : un simple suivi |
| Emprunt reçu (« je dois », argent entré) | cochée | entrée **neutre** (`isNeutral`), donc exclue du solde disponible, du budget et des statistiques tant qu'elle doit être rendue |
| Achat à crédit (« je dois », rien n'est entré) | décochée | aucune écriture |

Règle d'isolation : `solde disponible = comptes + épargne − argent de tiers`.
Une entrée neutre alimente `thirdPartyHeld`, donc **elle ne peut pas être
dépensée par erreur**. Les dettes elles-mêmes ne modifient jamais le solde.

### 3.3 Remboursements et états

- Règlement **partiel ou total** : `settledAmount` augmente, plafonné au reste
  dû ; `remaining` n'est jamais négatif.
- États, par ordre de priorité d'affichage :

| État | Condition |
| --- | --- |
| **Soldé** | `remaining == 0` |
| **En retard** | non soldé et `dueDate` antérieure au jour courant |
| **Partiellement remboursé** | non soldé, pas en retard, `settledAmount > 0` |
| **En cours** | non soldé, pas en retard, aucun règlement |

- L'échéance se compare au **jour**, pas à l'heure : une échéance du jour n'est
  pas encore en retard. Le pourcentage réglé est affiché (`progressPercent`).
- Un règlement est réversible : bandeau **« Annuler »** de 5 secondes qui
  restaure l'état précédent.

### 3.4 Portefeuille

- Les créances et dettes sont **regroupées par contact** (nom, casse ignorée),
  avec le total du contact (`On me doit … · Je dois …`).
- Cartes de synthèse globales conservées (« On me doit » / « Je dois »),
  toujours masquées quand le masquage est actif.
- Ajout : bandeau **« Annuler »** de 5 secondes qui supprime la dette **et** son
  mouvement de trésorerie éventuel.

### 3.5 Masquage et rappels

- Tous les montants (reste dû, totaux par contact, synthèse, maximum de
  règlement) passent par `AkibaMoney.format(..., masked:)`.
- Les rappels d'échéance ne contiennent **aucun montant** : les banques de
  messages parlent d'« échéances du jour », et `ReminderPlanner.sanitize`
  retire tout `… FCFA` résiduel. Un rappel dédié par dette reste à brancher
  (Phase 7), avec la même interdiction de montant.
- Aucun nom de contact n'est inclus dans une notification système.

---

## 4. Tests de non-régression

| Sujet | Test |
| --- | --- |
| Chiffrement de la clé | aller-retour, clé maîtresse différente, valeur altérée |
| Contrôle de saisie | vide, trop court, espace, clé valide, libellé masqué |
| Modèles | analyse de `models.list`, filtrage, doublon, cache, priorité, déplacement |
| Délais | 5 / 6 s pour la saisie et les SMS, 10 / 12 s pour analyse et coaching |
| Cascade | délai → 429 → succès, clé refusée = arrêt, plafond d'essais, veille 10 min |
| Dettes | quatre états, échéance du jour, emprunt neutre hors solde, suppression sans effet sur les comptes |
