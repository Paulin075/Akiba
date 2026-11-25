# Activer la connexion Google sur le téléphone (Android)

Procédure de référence pour que le bouton « Se connecter avec Google » d'AKIBA
fonctionne sur Android, avec un téléphone réel. Elle complète
`regles_themes_et_identifiants_google.md` §2 et l'Étape 20 de
`RESTE_A_FAIRE.md` ; en cas de contradiction, c'est **ce document** qui décrit
les gestes exacts.

Sur Android, AKIBA ne passe plus par la boucle locale PKCE (dépréciée par Google
pour les applications mobiles) mais par `google_sign_in`, qui exige **deux**
clients OAuth dans le **même projet** Google Cloud :

| Client OAuth | Sert à | Où il va |
| --- | --- | --- |
| **Android** — package `com.akiba.app` + empreinte SHA-1 de la clé de signature | faire reconnaître l'APK par Google Play services | nulle part : il ne produit aucun identifiant à copier |
| **Application Web** | être le `serverClientId` transmis par `google_sign_in`, c'est-à-dire l'audience du jeton | `AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID` dans `secrets/google_oauth.json` |

Le client « Application de bureau » existant (`AKIBA_GOOGLE_CLIENT_ID`) reste
utile pour l'ordinateur ; il ne sert **à rien** sur Android et ne doit pas être
mis dans `AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID`.

---

## Étape 1 — Obtenir l'empreinte SHA-1

```bash
dart run tool/debug_sha1.dart
```

Sortie attendue (l'empreinte est propre à chaque poste) :

```
AKIBA · empreinte de signature de l’APK debug
Source  : C:\Users\<vous>\.android\debug.keystore
SHA-1   : F7:4C:18:3B:E1:DC:DA:4D:4A:81:F3:E7:88:9D:FE:64:8E:F5:DB:80
Package : com.akiba.app
```

Recopiez la ligne `SHA-1` **telle quelle, avec les deux-points**.

| Cas | Commande |
| --- | --- |
| Clé debug de ce poste (cas normal) | `dart run tool/debug_sha1.dart` |
| `keytool` introuvable | `dart run tool/debug_sha1.dart --keytool "<chemin>/keytool"` |
| Magasin de clés créé avec un autre mot de passe | `… --keystore <fichier> --storepass <mot de passe> --alias <alias>` |
| APK **déjà signé** par une autre clé (`android/key.properties`, Play App Signing) | `"$LOCALAPPDATA/Android/sdk/build-tools/<version>/apksigner.bat" verify --print-certs build/app/outputs/flutter-apk/app-debug.apk` puis la ligne `SHA-1 certificate SHA-1 digest` |

Points à retenir :

1. L'empreinte est celle du **certificat**, pas du fichier `debug.keystore` : elle
   ne change pas si la clé est recopiée ailleurs.
2. Elle est **propre au poste** : une autre machine de développement a une autre
   clé debug, donc un autre client Android (ou le même client avec une seconde
   empreinte ajoutée).
3. Elle n'est pas un secret : elle est publique et lisible dans n'importe quel
   APK. Aucune précaution particulière au-delà de ne pas publier de valeurs
   d'identifiants.
4. Si `~/.android/debug.keystore` manque, lancez d'abord une build debug
   (`flutter build apk --debug`) : Gradle le crée.

---

## Étape 2 — Projet Google Cloud et API Drive

1. <https://console.cloud.google.com/> → sélecteur de projet → **Nouveau
   projet** (par exemple `akiba-mobile`), puis sélectionnez-le. Utilisez **le
   même projet** que celui du client de bureau existant, ou un projet neuf :
   l'essentiel est que le client Android et le client Web soient dans un seul
   projet.
2. **APIs et services → Bibliothèque** → « Google Drive API » → **Activer**.
   Sans elle, la connexion réussit mais la sauvegarde Drive échoue ensuite.

---

## Étape 3 — Écran de consentement (Google Auth Platform)

1. **Google Auth Platform → Branding** (ancien « Écran de consentement OAuth »).
   Si « Google Auth Platform not configured yet » s'affiche : **Get started**
   (`App name` = `AKIBA`, e-mail d'assistance, e-mail de contact, accord sur la
   politique).
2. **Audience** → type d'utilisateur **Externe**, état **Testing**.
3. Toujours dans **Audience → Test users → Add users** : ajoutez **l'adresse
   Google du téléphone** (celle qui servira à la connexion) et validez. En mode
   Testing, tout compte absent de cette liste est refusé (`access_denied`).
4. **Data Access → Add or remove scopes** : ajoutez
   `https://www.googleapis.com/auth/drive.appdata`
   (« Voir et gérer les fichiers de configuration de son propre compte
   Google Drive »), puis **Save**. C'est la seule portée demandée par AKIBA.

> Un projet en mode Testing n'exige aucune validation Google. La limite est de
> 100 utilisateurs test et les jetons de rafraîchissement expirent au bout de
> 7 jours ; cela suffit pour la recette. Une publication (mode « In production »)
> demanderait une vérification de la portée Drive.

---

## Étape 4 — Client OAuth « Android »

1. **Google Auth Platform → Clients → Create client** (ancien « APIs et services
   → Identifiants → Créer des identifiants → ID client OAuth »).
2. Type d'application : **Android**.
3. Nom : `AKIBA Android (debug)`.
4. **Package name** : `com.akiba.app` — exactement, en minuscules, tel que dans
   `android/app/build.gradle.kts` (`applicationId`). Le `namespace` Gradle
   `com.example.akiba` ne doit **pas** être utilisé ici.
5. **SHA-1 certificate fingerprint** : l'empreinte de l'étape 1.
6. **Create**. La fenêtre affiche le nom du client et un simple rappel :
   **aucun fichier à télécharger, aucun identifiant à copier dans AKIBA**. C'est
   Play services qui reconnaît l'APK grâce à ce couple package + SHA-1.

Répétez l'opération (même package) pour chaque autre empreinte : autre poste de
développement, clé de release, clé de Play App Signing.

---

## Étape 5 — Client OAuth « Application Web » et fiche `secrets/`

1. **Clients → Create client** → type **Web application**.
2. Nom : `AKIBA Android server`.
3. Ne remplissez **ni** « Authorized JavaScript origins » **ni** « Authorized
   redirect URIs » : `google_sign_in` ne s'en sert pas sur Android (le client
   Web sert uniquement d'audience pour le jeton).
4. **Create**, puis copiez l'**ID client** affiché (il se termine par
   `.apps.googleusercontent.com`). Le **secret** affiché à côté est inutile :
   ne le copiez nulle part.
5. Ouvrez ou créez `secrets/google_oauth.json` (ignoré par Git) et complétez la
   troisième clé, en conservant les deux premières :

   ```json
   {
     "AKIBA_GOOGLE_CLIENT_ID": "<client Application de bureau existant>",
     "AKIBA_GOOGLE_CLIENT_SECRET": "",
     "AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID": "<ID du client Application Web>"
   }
   ```

Règles :

- `AKIBA_GOOGLE_CLIENT_SECRET` reste **vide** : AKIBA n'a aucun secret, et un
  secret écrit là finirait dans l'APK.
- Ne mettez **jamais** le client Android (il n'a pas d'identifiant copiable) ni
  le client de bureau dans `AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID`.
- `secrets/` et `assets/config/google_oauth.json` sont dans `.gitignore` ; ne
  les forcez pas dans Git (`git add -f` interdit ici).

---

## Étape 6 — Copie embarquée et reconstruction

La copie `assets/config/google_oauth.json` est produite **sans commande** par la
tâche Gradle `syncOAuthSecrets`, avant chaque build Android. Pour la forcer ou
vérifier la lecture du fichier :

```bash
dart run tool/sync_oauth_secrets.dart
```

Sortie attendue : `AKIBA : assets/config/google_oauth.json déjà à jour (…)` ou
`identifiants Google OAuth copiés…`. Un identifiant vide ou mal formé supprime
la copie : l'application reste alors hors ligne, sans blocage.

Reconstruisez et installez **après** avoir enregistré le SHA-1 (Play services
met parfois quelques minutes à propager un nouveau client OAuth) :

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Si `adb install` répond `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, l'application
installée est signée par une autre clé : `adb uninstall com.akiba.app` puis
réinstallez (les données locales de l'application sont perdues).

---

## Étape 7 — Essai réel sur le téléphone

1. Lancez AKIBA → **Profil → Sauvegarde** (ou l'étape Google de l'onboarding) →
   « Se connecter avec Google ».
2. Choisissez le compte **ajouté comme utilisateur test** ; l'écran Google doit
   demander l'accès à l'espace applicatif du Drive.
3. Attendu : retour dans AKIBA, adresse du compte affichée, sauvegarde Drive
   possible. Vérifiez dans Drive (menu « Paramètres → Gérer les applications »
   ou dossier masqué `appDataFolder`) qu'une sauvegarde existe.
4. Coupez les données mobiles et le Wi-Fi : l'application doit rester utilisable
   avec le repli « dossier Google Drive synchronisé », sans message d'erreur
   bloquant.

---

## Dépannage

| Message / symptôme | Cause probable | Correctif |
| --- | --- | --- |
| « Google refuse la connexion Android… » (`clientConfigurationError`, code 10 `DEVELOPER_ERROR`) | package ou SHA-1 différent de l'APK installé ; client Android dans un autre projet que le client Web ; propagation en cours | revérifier `com.akiba.app` + empreinte de l'étape 1, attendre quelques minutes, réinstaller |
| `DEVELOPER_ERROR` alors que le SHA-1 est juste | l'APK du téléphone est signé par une autre clé (release, Play App Signing, autre poste) | relever l'empreinte avec `apksigner verify --print-certs` sur **cet** APK et l'ajouter au client Android |
| `access_denied` / « Accès bloqué : cette application n'a pas terminé la vérification » | compte absent des utilisateurs test | Étape 3, point 3 |
| Connexion réussie mais sauvegarde refusée (403/insufficient scope) | portée `drive.appdata` non déclarée, ou Drive API désactivée | Étape 2 et Étape 3, point 4 ; reconnectez-vous pour réaccorder |
| Rien ne se passe, message « identifiants prêts » absent | `canSignIn` faux : `AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID` vide ou ne finissant pas par `.apps.googleusercontent.com` | Étape 5, puis reconstruction |
| « Un autre compte Google est déjà connecté sur cet appareil » | compte différent de celui mémorisé par Play services | déconnecter l'autre compte du téléphone, ou utiliser celui-là |
| Erreur toujours identique après correction | ancienne copie embarquée dans l'APK | `flutter clean` puis `flutter build apk --debug`, réinstaller |

---

## Sécurité — ce qui ne doit jamais arriver

- Aucun identifiant ni secret dans `lib/`, `android/`, `test/` ou un fichier
  versionné : uniquement `secrets/google_oauth.json` (local) et la copie
  ignorée `assets/config/google_oauth.json`.
- Le secret du client Web n'est **pas** nécessaire : s'il apparaissait dans
  `secrets/`, il serait embarqué dans l'APK.
- Aucun jeton dans les journaux : le jeton d'accès reste en mémoire, le jeton de
  rafraîchissement dans le coffre système (ordinateur uniquement).
- La sauvegarde déposée sur Drive reste l'enveloppe **AES-256-GCM** : Google ne
  reçoit que du chiffré.
