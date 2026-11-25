# Règles des thèmes et des identifiants Google (Étape 13)

Annexe de référence, au même titre que `regles_profil_ia_et_sauvegardes.md`.
Elle fixe ce qui ne doit plus bouger dans les étapes suivantes.

---

## 1. Les cinq thèmes

| Ordre | Identifiant | Libellé | Fond | Action | Texte principal |
| --- | --- | --- | --- | --- | --- |
| 1 | `blanc` | Blanc (**défaut**) | `#FAF4E6` | `#C7673D` | `#1A1816` |
| 2 | `sombre` | Sombre | `#0E0D0C` | `#C7673D` | `#F3EEE2` |
| 3 | `bleu` | Bleu | `#EAF1FA` | `#1E5FA8` | `#14202E` |
| 4 | `vert` | Vert | `#EDF6EE` | `#1F6B3A` | `#102315` |
| 5 | `or` | Jaune Or | `#FBF6E4` | `#8A6414` | `#241C08` |

Règles :

1. **Cinq thèmes, pas six.** L'ancien réglage « Système » disparaît : le thème
   est toujours un choix explicite de la personne, enregistré dans
   `settings.akiba_theme` (base chiffrée). Toute valeur inconnue retombe sur
   **Blanc**.
2. **Persistance immédiate.** L'appui sur une pastille écrit le réglage ; la
   racine (`MaterialApp`) se reconstruit avec `AkibaTheme.forId(...)`, donc
   l'aperçu est instantané et identique après redémarrage.
3. **Aucun thème système superposé** : `darkTheme` et `themeMode` ne sont plus
   utilisés, sinon le mode sombre du téléphone écraserait Bleu, Vert ou Or.
4. **Contraste élevé**, vérifié par test sur les cinq palettes :
   - titres sur le fond et sur les cartes : **≥ 10:1** ;
   - textes secondaires sur cartes et fond : **≥ 4.5:1** ;
   - texte clair sur la couleur d'action et sur le bas du dégradé : **≥ 3:1**
     (montant héros 36 pt, seuil « grand texte »).
5. **Logos Flooz / Mixx by Yas / Orabank** : toujours dans leur tuile blanche,
   jamais teintés ni posés directement sur le fond du thème. Un test visuel
   reste à faire sur appareil, mais la règle de rendu est inchangée.
6. **Barre basse** : pleine largeur, ancrée, sans marge, sans bord arrondi,
   **jamais flottante**, dans les cinq thèmes ; seule sa couleur de surface
   change.
7. **Boutons latéraux** : cochon en bas à droite, **icône Assistant IA juste
   au-dessus**, même taille, même position, même ordre dans les cinq thèmes.
   Le cochon reste l'emblème AKIBA dans un cercle de surface.
8. **Accessibilité** : pastilles de 46 px avec libellé, sémantique
   « Thème <nom> », état sélectionné annoncé, cible tactile ≥ 48 dp avec le
   rembourrage.

---

## 2. Identifiants OAuth Google

1. Le JSON téléchargé depuis Google Cloud Console (`client_secret_*.json`)
   reste **hors du dépôt** : `client_secret_*.json` et `secrets/` sont dans
   `.gitignore`.
2. `secrets/google_oauth.json` ne contient que les définitions de compilation :

   ```json
   {
     "AKIBA_GOOGLE_CLIENT_ID": "…apps.googleusercontent.com",
     "AKIBA_GOOGLE_CLIENT_SECRET": "",
     "AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID": "…apps.googleusercontent.com"
   }
   ```

   Le client AKIBA est de type **Application de bureau** : il n'a pas de
   secret, la chaîne vide est la valeur correcte. La troisième clé est le client
   **Application Web** (Android uniquement, voir point 7).
3. L'application lit l'identifiant par `String.fromEnvironment` (essais
   ponctuels), puis `secrets/google_oauth.json`, puis la copie embarquée
   `assets/config/google_oauth.json` — écrite **sans commande** par la tâche
   Gradle `syncOAuthSecrets` avant chaque build Android. La lecture ne modifie
   jamais ces fichiers. Aucune constante d'identifiant n'est écrite dans `lib/`.
4. Sans identifiant, `GoogleOAuthConfig.isConfigured` et `isAndroidReady` sont
   faux : l'application reste **100 % hors ligne** et propose le dossier Drive
   synchronisé. Aucune erreur, aucun écran bloqué.
5. Sur Android (Étape 20), la connexion passe par `google_sign_in` : client OAuth
   **Android** pour `applicationId` `com.akiba.app` + empreinte SHA-1, et client
   **Application Web** fourni comme `AKIBA_GOOGLE_ANDROID_SERVER_CLIENT_ID`
   (jamais un secret). Le flux boucle locale + PKCE reste réservé à l'ordinateur.
   L'empreinte se relève avec `dart run tool/debug_sha1.dart` ; la procédure
   exacte (projet, consentement, utilisateurs test, deux clients) est dans
   `akiba_spec/activer_connexion_google_android.md`.
6. La sauvegarde déposée sur Drive reste l'enveloppe **AES-256-GCM** existante
   (phrase secrète locale, PBKDF2 120 000 tours) dans `appDataFolder` ; Google
   ne reçoit que du chiffré. Les cinq dernières sauvegardes sont conservées.
7. Aucun jeton n'est écrit dans le code, la base ou les journaux : jeton
   d'accès en mémoire, jeton de rafraîchissement dans le coffre système.
