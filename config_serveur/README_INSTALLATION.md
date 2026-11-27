# Serveur de sauvegarde AKIBA — installation sur CasaOS / Ubuntu

Ce dossier est prêt à être copié sur le serveur. Il gère **plusieurs
utilisateurs avec un seul jeton** : chaque personne ajoute simplement son nom
après le jeton (`JETON:son_nom`) et obtient son propre dossier, donc ses
propres sauvegardes. Aucune donnée n'est déchiffrée : AKIBA envoie une
enveloppe AES-256-GCM, le serveur la stocke et la rend telle quelle.

```
config_serveur/
├── main.py                     # API FastAPI (jeton partagé + dossiers par nom)
├── requirements.txt            # fastapi + uvicorn
├── Dockerfile                  # image python:3.11-slim, port 8080
├── docker-compose.yml          # redémarrage automatique + volume
├── README_INSTALLATION.md      # ce fichier
└── commandes_activation.txt    # commandes à copier/coller
```

## 1. Où placer les fichiers

Sur le serveur (SSH ou terminal CasaOS) :

```bash
sudo mkdir -p /DATA/AppData/akiba-backup
# copiez les 4 fichiers main.py, requirements.txt, Dockerfile,
# docker-compose.yml dans /DATA/AppData/akiba-backup/
sudo mkdir -p /DATA/AppData/akiba-backup/data
```

Le volume `data/` contiendra :

```
data/
└── backups/
    ├── mamadou/
    │   ├── latest.json          # dernière enveloppe (lue par AKIBA)
    │   └── history/             # 30 dernières, horodatées
    │       └── backup_20261126T101500123456Z.json
    ├── awa/
    │   └── ...
    └── default/                 # sauvegardes envoyées sans nom
```

L'ancien fichier unique `data/backups/latest_backup.bin` est repris
automatiquement dans `data/backups/default/latest.json` au premier démarrage
s'il existe encore.

## 2. Un seul jeton pour tout le monde

Générez **une seule** valeur, une fois :

```bash
openssl rand -hex 32
```

Reportez-la dans `docker-compose.yml`, ligne `SHARED_TOKEN` :

```yaml
SHARED_TOKEN: "9f2c8a…votre_valeur…"
```

C'est tout : il n'y a plus qu'un secret à distribuer à tout le monde.

### Comment chacun garde ses propres sauvegardes

Dans AKIBA, Profil → Sauvegarde → Serveur local, le champ « Jeton d'accès »
accepte deux formes :

| Saisie | Dossier créé sur le serveur |
| --- | --- |
| `9f2c8a…` (jeton seul) | `data/backups/default/` |
| `9f2c8a…:mamadou` | `data/backups/mamadou/` |
| `9f2c8a…:awa` | `data/backups/awa/` |

Autrement dit : **le même jeton pour tous, mais un nom différent par
personne**. Le nom ne doit contenir que lettres, chiffres, `-` et `_` (les
accents et espaces sont remplacés par `_`) ; il devient le nom du dossier sur
le disque. Un nom est obligatoire pour être vraiment séparé : sans nom, tout
le monde écrit dans `default`.

Les sauvegardes restent chiffrées **AES-256-GCM** de bout en bout : le serveur
ne voit que des octets illisibles, et une sauvegarde d'un autre nom ne peut
pas être restaurée sans la clé de son appareil ou de son compte Google.

> ⚠️ Le jeton partagé donne accès à **tous** les dossiers : quelqu'un qui le
> connaît peut écraser la sauvegarde d'un autre nom (sans jamais pouvoir la
> lire, puisqu'elle est chiffrée). Si vous ne voulez pas de ce risque, utilisez
> les jetons dédiés ci-dessous.

### Option : un jeton dédié par personne

Si vous préférez ne rien saisir après le jeton, `USER_TOKENS` reste
disponible. Générez alors un jeton par personne :

```bash
openssl rand -hex 32   # Alice
openssl rand -hex 32   # Bob
```

et déclarez-les au format `jeton:utilisateur` :

```yaml
USER_TOKENS: "JETON_ALICE:alice,JETON_BOB:bob"
```

Chaque jeton ouvre directement son dossier, sans nom à ajouter. Les deux modes
peuvent cohabiter (utile pendant une transition : gardez `SHARED_TOKEN` pour
les nouveaux, les anciens jetons continuent de marcher).

### Ajouter un utilisateur plus tard

Avec le jeton partagé, **rien à faire sur le serveur** : la personne écrit
`JETON:son_nom` dans AKIBA et son dossier est créé au premier envoi.

Avec les jetons dédiés : `openssl rand -hex 32`, ajoutez `nouveau_jeton:carol`
à `USER_TOKENS`, puis `sudo docker compose up -d`.

## 3. Construire et démarrer

```bash
cd /DATA/AppData/akiba-backup
sudo docker compose up -d --build
sudo docker compose ps
sudo docker compose logs -f akiba-backup
```

## 4. Redémarrage automatique

`restart: unless-stopped` relance le conteneur après un redémarrage du
serveur, une coupure de courant ou un crash. Le service Docker doit lui-même
être activé au boot :

```bash
sudo systemctl enable docker
sudo systemctl enable containerd   # si présent
```

Vérification réelle (à faire une fois) :

```bash
sudo reboot
# après reconnexion :
sudo docker ps --filter name=akiba-backup
curl http://127.0.0.1:8080/ping
```

## 5. Ouvrir le port et tester

```bash
sudo ufw allow 8080/tcp          # seulement si ufw est actif
sudo ufw status

TOKEN="LE_JETON_PARTAGE:mamadou"
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8080/health
curl -i -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8080/
```

* `/health` → `{"status":"ok","user":"mamadou","shared_token":true,…}`
* `GET /` sans sauvegarde → **HTTP 404** (et non 204 vide) : AKIBA affiche
  alors « Aucune sauvegarde AKIBA trouvée sur ce serveur ».
* `GET /` avec sauvegarde → l'enveloppe JSON brute, identique à l'octet près
  à celle envoyée en `PUT`.

Test d'envoi avec une fausse enveloppe :

```bash
echo '{"format":"akiba-backup","version":2,"cipher":"AES-256-GCM","ciphertext":"test","createdAt":"2026-11-26T10:00:00Z"}' \
  > /tmp/enveloppe.json
curl -X PUT -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/enveloppe.json \
  http://127.0.0.1:8080/backup
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8080/backup
sudo ls -l /DATA/AppData/akiba-backup/data/backups/
```

Avec un second nom (`TOKEN2="LE_JETON_PARTAGE:awa"`), on doit obtenir `404`
sur `GET /` : les deux dossiers sont bien indépendants.

## 6. Configuration dans AKIBA

Profil → Sauvegarde → Serveur local (Home Lab) :

| Champ | Valeur |
| --- | --- |
| Adresse | `http://192.168.1.20:8080` (IP du serveur sur le même Wi-Fi) |
| Jeton | `LE_JETON_PARTAGE:mamadou` (le jeton, puis `:` puis votre nom) |

L'application ajoute `http://` automatiquement si vous saisissez seulement
`192.168.1.20:8080`. En onboarding, l'écran « Restaurer depuis mon serveur »
ne demande que ces deux champs : la sauvegarde est cherchée puis restaurée
automatiquement.

Le serveur doit être joignable depuis le téléphone : même réseau Wi-Fi, pas de
VLAN isolé, pas de VPN actif sur le téléphone. Android autorise déjà le HTTP
local (`usesCleartextTraffic="true"`).

## 7. Dépannage

| Symptôme | Cause probable | Correction |
| --- | --- | --- |
| `401` | jeton refusé par le serveur (voir ci-dessous) | corriger le jeton, puis **recréer** le conteneur (`docker compose up -d`) |
| `404` sur `GET /` | aucune sauvegarde pour ce nom | lancer une sauvegarde depuis AKIBA avec le même `JETON:nom` |
| Les deux personnes voient la même sauvegarde | même nom après le jeton, ou aucun nom (`default`) | un nom différent par personne |
| `400 Ce JSON n'est pas une enveloppe…` | corps envoyé par un autre outil | utiliser AKIBA (ou l'exemple ci-dessus) |
| `connexion refusée` | conteneur arrêté ou port fermé | `docker compose ps`, `ufw allow 8080/tcp` |

### 401 : « Lecture impossible (HTTP 401) »

AKIBA affiche désormais le motif envoyé par le serveur — il suffit de le lire :

| Motif affiché | Cause | Correction |
| --- | --- | --- |
| `Jeton manquant` | le champ jeton est vide dans AKIBA | le saisir à l'étape 2, puis « Enregistrer et activer » |
| `Jeton invalide` | la valeur ne correspond pas au `SHARED_TOKEN` du serveur | comparer les deux, sans guillemets ni espace |
| `Aucun jeton configuré` | `SHARED_TOKEN` est vide dans le conteneur | le renseigner, puis `docker compose up -d` |

Les trois pièges rencontrés en pratique :

1. **Le conteneur n'a pas été recréé.** `docker restart` ne relit pas
   `docker-compose.yml` : les variables restent celles du lancement
   précédent. Utilisez `sudo docker compose up -d` (il recrée le conteneur
   quand l'environnement change).
2. **Le jeton a été changé côté serveur et pas dans AKIBA** (ou
   l'inverse). Le serveur ne stocke aucun jeton : seule la variable
   d'environnement compte.
3. **Le nom après `:` a été oublié ou diffère** en mode partagé :
   `JETON:awa` et `JETON:mamadou` ouvrent deux dossiers. Un jeton seul écrit
   dans `default`.

Le serveur tolère les guillemets collés autour du jeton (`"abc"`) et les
espaces de fin de ligne, mais pas une valeur différente.

## 8. Sauvegarde du serveur lui-même

Les données sont dans `/DATA/AppData/akiba-backup/data`. Copiez ce dossier
(ou incluez-le dans la sauvegarde CasaOS) : il contient les enveloppes déjà
chiffrées, inutilisables sans la clé de l'appareil ou le compte Google.

## 7 bis. Code à 4 chiffres de l'application

Depuis la version 4 des enveloppes, une sauvegarde envoyée à ce serveur n'est
plus liée au compte Google : AKIBA demande un **code à 4 chiffres** lors de la
configuration de la sauvegarde, puis le même code pour la restaurer sur un autre
appareil. Le serveur n'a rien à configurer : il ne reçoit que l'enveloppe
chiffrée `PBKDF2-CODE` et ne connaît ni le code ni la clé.

- Le code n'est jamais écrit dans `latest.json` ni dans les journaux.
- Un `PUT` remplace `latest.json` du dossier concerné ; l'historique
  `backup_*.json` est conservé tel quel.
- Code oublié : il n'existe aucun moyen de rouvrir l'enveloppe. L'application
  crée une nouvelle sauvegarde avec un nouveau code, qui remplace `latest.json` :
  la personne repart de zéro, comme demandé.
- Les anciennes enveloppes (clé d'appareil ou compte Google) restent lisibles
  par leur ancien chemin, sans code.
