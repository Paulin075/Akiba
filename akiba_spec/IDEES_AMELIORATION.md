# IDEES_AMELIORATION — Pistes AKIBA

Dernière mise à jour : **25/11/2026**. Depuis l'Étape 18, l'idée **110**
(rappel d'échéance par dette, sans montant ni nom) est **appliquée**, ainsi qu'un
reclassement direct depuis le détail d'un mouvement. Depuis l'Étape 17, les idées **71**
(limitation des essais de PIN), **53** (date d'atteinte dynamique) et la lecture
des **nombres en lettres** dans la dictée sont **appliquées**. Les idées 19 (vues SQL agrégées) et 26
(libellés lecteur d'écran) sont **partiellement appliquées** depuis les Étapes
1.2 et 1.3 : vue `v_account_balances` et libellés complets sur les lignes de
mouvement. Depuis l'Étape 15, les idées 79 (dictée réelle + analyse automatique)
et 118 (test Google sans dépôt, ici étendu au Home Lab) sont **appliquées** ;
les idées 92 (rendu à deux largeurs) et 70 (Analyses sur 360 px) ont leur
premier test automatisé à 320 px. Les autres restent à arbitrer par le porteur.

---

## 1. Expérience de saisie

1. **Pavé numérique intégré à la feuille de saisie** plutôt que le clavier système :
   une sortie en 3 touches (montant → catégorie → valider) devient réalisable même
   sur petit écran.
2. **Raccourcis appris** : mémoriser les 3 catégories et le support les plus utilisés
   par créneau horaire et les proposer en tête de liste.
3. **Saisie par copier-coller d'un SMS** en complément de la lecture automatique,
   pour les téléphones où la permission SMS est refusée.
4. **Annulation à 5 s** déjà prévue : ajouter un raccourci `Ctrl+Z` sur Windows.
5. **Mode « dépense rapide »** : montant seul, la catégorie « À classer » est
   proposée, avec un rappel de reclassement le soir.

## 2. Clarté des chiffres

6. **Micro-explication au toucher du Solde disponible** : « 42 853 = 165 500 de
   comptes − 122 647 d'argent de tiers », pour éviter toute ambiguïté.
7. **Historique du solde (sparkline 7 jours)** sous le montant héros, sans
   surcharger la carte.
8. **Arrondi pédagogique** sur les jauges : afficher « 3 200 / 4 000 » en plus du
   pourcentage, la couleur ne devant jamais porter seule l'information.
9. **Comparaison mois précédent** exprimée en FCFA et en pourcentage, jamais en
   pourcentage seul.

## 3. Épargne et objectifs

10. **Arrondi automatique** : arrondir chaque sortie au millier supérieur et verser
    la différence dans le coffre épargne (désactivable).
11. **Défi 52 semaines adapté au FCFA** (paliers de 500 FCFA) comme objectif
    pré-rempli.
12. **Simulateur « et si »** : « si j'épargne 2 000 FCFA/semaine, j'atteins mon
    objectif le … » avec date recalculée en direct.

## 4. Argent de tiers

13. **Étiquettes de tiers** (nom du client) pour retrouver rapidement ce qui doit
    être reversé, avec total par personne.
14. **Alerte de reversement** : une entrée neutre non soldée depuis plus de 7 jours
    apparaît dans les rappels du soir.
15. **Reçu texte partageable** d'un reversement, sans donnée sensible.

## 5. Notifications

16. **Heures intelligentes** : apprendre l'heure habituelle de saisie et décaler
    le rappel de 30 minutes plutôt que de multiplier les notifications.
17. **Rappel unique groupé** si les trois créneaux n'ont pas été ouverts, pour
    éviter le harcèlement.
18. **Widget Android 2×1** : solde masqué + bouton d'ajout, sans ouvrir l'app.

## 6. Performance

19. **Requêtes agrégées préparées** (vues SQLite `solde_par_compte`,
    `depenses_par_categorie`) plutôt que des calculs Dart sur toute la table.
    → *fait* pour les soldes (`v_account_balances`) ; la ventilation par catégorie
    viendra avec M16.
20. **Pagination des mouvements** (50 lignes par page) et recherche indexée.
21. **Chargement différé des graphiques** : ne calculer que la période visible.
22. **Images de logos en cache** (`precacheImage`) pour éviter un scintillement
    à l'ouverture des listes de comptes.

## 7. Accessibilité et confort

23. **Mode « gros caractères »** dédié, au-delà du réglage système, avec montants
    en 44 pt.
24. **Retour haptique réglable** (aucun / léger / marqué) séparément des animations.
25. **Contraste renforcé** optionnel pour l'usage en plein soleil.
26. **Libellés lecteur d'écran enrichis** : « 15 000 francs CFA, sortie, transport,
    aujourd'hui à 07 h 42 ». → *partiellement fait* sur les lignes de mouvement.

## 8. Données et confiance

27. **Export CSV / JSON** de toutes les données, pour ne jamais être captif de l'app.
28. **Journal des modifications** local (qui/quoi/quand) limité à 90 jours.
29. **Test de restauration guidé** après la première sauvegarde Drive, pour vérifier
    que la phrase secrète fonctionne avant d'en dépendre.
30. **Indicateur de fraîcheur de sauvegarde** dans la pastille de synchronisation
    (« sauvegardé il y a 2 h »).

## 9. Design system

31. **Embarquer Poppins et Inter** (graisses 400/600/700) pour supprimer le repli
    système (planifié en Étape 1.6).
32. **Frise de triangles paramétrable** (hauteur, opacité) pour la réutiliser sur
    les états vides sans dupliquer le peintre. → *fait* : `TriangleFringe`.
33. **Jeu de tuiles `MosaicTile` documenté** en variantes 1×1 / 2×1 / 2×2 pour que
    l'écran Paramètres reste cohérent quand de nouveaux réglages arrivent.

---

## 10. Nouvelles pistes issues des Étapes 1.2 et 1.3

34. **Jeu de données de démonstration réversible** (mode simulation, base isolée) :
    l'accueil vide ne montre ni frise animée ni tendance ; un jeu fictif
    désactivable permettrait au porteur de valider le rendu visuel avant la
    Phase 4.
35. **Aperçu du solde au toucher** : une feuille expliquant la composition
    (comptes, épargne, tiers) avec la même règle que `BalanceSummary`, sans
    dupliquer le calcul.
36. **Message explicite si la base ne peut pas s'ouvrir** (Phase 2.4) : le repli
    actuel est silencieux dans l'interface, ce qui peut faire croire à une perte
    de données.
37. **Contrôle de santé de la base après ouverture** : exécuter un
    `PRAGMA integrity_check` en arrière-plan au démarrage (jamais bloquant) et
    proposer une restauration si le résultat n'est pas `ok`.
38. **Regroupement des mouvements par jour** dans « Dernières transactions »
    (en-têtes « Aujourd'hui », « Hier ») dès que la liste dépassera 5 lignes.
39. **Compteur de mouvements neutres non soldés** dans la carte Argent de tiers,
    pour rendre visible ce qui doit être reversé sans ouvrir un écran.
40. **Tests d'interface sur deux largeurs** (360 px et 1 280 px) pour verrouiller
    la mise en page deux colonnes avant le rail Windows de l'Étape 1.7.
41. **Fermeture propre de la base** : checkpoint WAL et `close()` à la fermeture
    de l'application, aujourd'hui laissée ouverte pour toute la durée de vie du
    processus.
---

## 11. Nouvelles pistes issues de l'Étape 4 (saisie rapide)

42. **Saisie vocale courte** : « 5 000 taxi » depuis un appui long sur le
    cochon, avec carte de compréhension éditable (module M12, Phase 6).
43. **Catégories apprises** : proposer en tête les trois catégories les plus
    utilisées par créneau horaire, et la dernière note saisie.
44. **Pavé numérique interne** à la feuille, pour éviter le clavier système et
    tenir les 3 touches sur les petits écrans.
45. **Détection de doublon** : avertir doucement si un montant identique, même
    compte et même catégorie a été saisi dans les 5 dernières minutes.
46. **Retour haptique** à l'enregistrement (léger, désactivable) et vibration
    d'avertissement quand le solde devient négatif.
47. **Annulation plus longue** (10 s) pour les transferts, qui touchent deux
    comptes, ou confirmation par glissement complet.
48. **Saisie en lot** : enchaîner plusieurs sorties sans refermer la feuille
    (« Enregistrer et continuer »).
49. **Mémoriser le dernier compte utilisé** par mode pour préremplir la feuille.
50. **Budget suggéré** : à partir des trois derniers mois, proposer un plafond
    par catégorie au lieu de le saisir à la main (préparation de l'Étape 6).
---

## 12. Nouvelles pistes issues de l'Étape 5 (portefeuille)

51. **Recherche de mouvement** dans l'onglet Mouvements (libellé, catégorie,
    montant) avec index SQLite dédié.
52. **Pagination** des mouvements (50 lignes), le mois courant restant chargé
    d'un bloc.
53. **Date d'atteinte dynamique** sous chaque objectif : « à 2 000 FCFA par
    semaine, atteint le 04/03/2027 » (module M10).
54. **Paliers 25/50/75/100 %** sur le fonds d'urgence, avec illumination du
    repère et retour haptique (module M11).
55. **Reversement partiel guidé** : proposer le montant détenu par défaut et
    rappeler le nom du tiers dans le libellé généré.
56. **Solde de compte en graphique** (sparkline 30 jours) dans le détail d'un
    compte.
57. **Calendrier compact** : vue semaine sur petit écran, mois sur grand écran,
    avec un résumé « 3 mouvements · 12 500 FCFA » sous chaque jour sélectionné.
58. **Filtres rapides** du calendrier : entrées seulement, sorties seulement,
    argent de tiers, épargne.
59. **Regroupement des transferts** : afficher une seule ligne « Flooz → Mixx »
    au lieu des deux écritures symétriques.
60. **Renommage et archivage de compte** sans perdre l'historique (le champ
    `is_archived` existe déjà).
---

## 13. Nouvelles pistes issues de l'Étape 6 (analyses)

61. **Comparaison de catégories** : badge « + 12 % vs mois dernier » par ligne
    de ventilation, pas seulement sur le total.
62. **Budget suggéré** à partir de la moyenne des trois derniers mois, avec
    confirmation avant création du plafond (idée 50).
63. **Seuil de besoin ajustable** : proposer « payable bientôt » à 90 % de la
    capacité pour conserver une marge, plutôt qu'à 100 %.
64. **Simulation de coup dur** : « si je dépense 25 000 FCFA aujourd'hui, il me
    reste X et mes besoins payables passent à Y » (module M11).
65. **Bilan exportable** : PDF ou texte partageable, sans montant si le masquage
    est actif.
66. **Drill-down** : toucher une barre de l'histogramme pour voir les mouvements
    du jour correspondant.
67. **Objectif d'épargne relié au bilan** : montrer la part du net mensuel
    effectivement épargnée.
68. **Besoins récurrents** : marquer un besoin comme mensuel (loyer) pour le
    recréer automatiquement au changement de mois.
69. **Notification de seuil** : alerte locale à 80 % d'un plafond, sans montant
    si le masquage est actif.
70. **Test d'interface à deux largeurs** sur l'écran Analyses pour verrouiller
    l'histogramme (31 barres) sur 360 px.
## 14. Nouvelles pistes issues de l'Étape 7 (profil)

71. **Limitation des essais de PIN** : compteur persistant, verrouillage
    progressif (30 s, 1 min, 5 min) et message neutre, sans révéler le nombre
    d'essais restants.
72. **Dérivation de la clé de base depuis le PIN** : le PIN protège alors la base
    elle-même, pas seulement l'écran ; garder un filet de secours documenté.
73. **Aperçu des rappels** : bouton « M’envoyer un exemple dans 10 secondes »
    depuis le Profil, pour vérifier le ton et l'absence de montant sans attendre
    7 h 30.
74. **Reprogrammation au démarrage** : recalculer les rappels à l'ouverture de
    l'application pour survivre aux mises à jour du système.
75. **Jeton masqué** : afficher `••••` et un bouton « Remplacer » pour les jetons
    du serveur maître et du Home Lab.
76. **Bento réorganisable** : mémoriser un ordre de tuiles par personne, avec
    deux ou trois tuiles « épinglées ».
77. **Bilan de confidentialité** : une tuile qui liste ce qui est stocké, où, et
    ce qui n'est jamais envoyé (aucune télémétrie).
78. **Import / export des réglages** seuls, sans données financières, pour
    retrouver son environnement sur un second appareil.

## 15. Nouvelles pistes issues de l'Étape 8 (IA, SMS, sauvegardes)

79. **Reconnaissance vocale locale** : remplacer le halo par une vraie dictée
    (greffon `speech_to_text` ou modèle embarqué), avec repli clavier assumé.
    → *fait depuis l'Étape 15* : dictée `onDevice`, et **analyse automatique dès
    la fin de la phrase** (aucun bouton « Analyser » à cliquer).
80. **Apprentissage des corrections** : quand une catégorie proposée par l'IA est
    corrigée trois fois pour le même mot, la mémoriser localement.
81. **Revue SMS par lot** : sélectionner plusieurs messages et appliquer le même
    compte ou la même catégorie d'un geste.
82. **Détection des doublons SMS** : comparer la référence de transaction pour
    éviter de saisir deux fois le même mouvement.
83. **Sauvegarde automatique** : une sauvegarde chiffrée hebdomadaire silencieuse
    vers la cible choisie, avec mention dans le Profil (jamais de montant).
84. **Historique des sauvegardes** : conserver les trois dernières enveloppes avec
    date, appareil et compteurs, et permettre une restauration ciblée.
85. **Test de restauration guidé** : un bouton « Vérifier ma sauvegarde » qui
    déchiffre et affiche les compteurs sans rien écrire.
86. **Synchronisation conflictuelle assistée** : montrer les deux versions
    (locale / distante) et laisser choisir par catégorie plutôt qu'en bloc.

## 16. Nouvelles pistes issues de l'Étape 9 (onboarding, animations)

87. **Visite guidée 4 bulles** après E11 : solde, cochon, IA, profil — chacune
    fermable et rejouable depuis le Profil.
88. **Reprise visuelle** : au retour, afficher « Vous étiez à l'étape 6 sur 11 »
    avec un bouton « Reprendre ».
89. **Onboarding sans clavier** : tout le parcours doit rester utilisable avec un
    lecteur d'écran et sans saisie obligatoire avant E3.
90. **Mode découverte** : après E11, proposer deux ou trois exemples fictifs
    clairement étiquetés, effaçables d'un geste.
91. **Réduction des animations affinée** : trois niveaux (complet, atténué,
    minimal) plutôt qu'un interrupteur, en suivant le réglage système par défaut.
92. **Test d'écran automatisé** : deux tests de rendu (360 px et 1 280 px) sur
    l'onboarding et le profil pour verrouiller les grilles Bento.
93. **Message de fin plus utile** : rappeler les trois gestes de la première
    semaine (noter une dépense, ouvrir un coffre, vérifier les rappels).
## 17. Nouvelles pistes issues de l'Étape 10 (release, dettes, devises)

94. **Devises 100 % locales** : embarquer les quatre logos (PNG de quelques Ko)
    et n'utiliser le CDN que pour les rafraîchir, afin de supprimer l'appel
    réseau et la métadonnée qu'il révèle.
95. **Taux de change optionnel** : si un jour la valeur doit suivre la devise,
    stocker la devise d'origine de chaque transaction et convertir à
    l'affichage, jamais dans la base.
96. **Multi-devises par compte** : un compte Flooz en FCFA, un compte bancaire
    en EUR, avec un total « équivalent FCFA » explicitement calculé.
97. **Créances et dettes reliées aux comptes** : proposer « encaisser sur
    Flooz » ou « payer depuis Orabank » en créant le mouvement correspondant,
    tout en gardant le suivi séparé du solde disponible.
98. **Échéancier des dettes** : vue calendrier des échéances avec rappel local,
    sans montant si le masquage est actif.
99. **Signature automatisée** : script de release qui vérifie la présence de
    `key.properties`, refuse le repli debug et archive l'APK/AAB signé.
100. **Fiche de recette release** : huit vérifications sur appareil (icône,
     permissions, notifications, biométrie, sauvegarde, restauration, mode
     avion, désinstallation/réinstallation).
101. **Icône adaptative Android** : couche avant/arrière séparée (`mipmap-anydpi-v26`)
     pour que le masque rond garde le cochon entier.
102. **Windows signé** : certificat de signature et installeur (MSIX) pour
     éviter l'avertissement SmartScreen.
103. **Vérification visuelle finale** : capture des quatre onglets, du profil
     Bento et de l'onboarding en clair et en sombre, à 360 px et 1 280 px.

## 18. Nouvelles pistes issues de l'Étape 11 (clé IA, cascade, dettes)

104. **Journal local des appels IA** : garder les 20 dernières tentatives
     (modèle, motif, durée) sans aucune donnée financière, pour expliquer les
     ralentissements sans exposer de contenu.
105. **Test de clé hors ligne impossible** : afficher clairement « test
     impossible sans réseau » au lieu d'un message d'échec ambigu.
106. **Veille persistante** : enregistrer la mise en veille des modèles dans les
     réglages pour qu'un redémarrage ne les réessaie pas immédiatement.
107. **Quota local réel** : brancher `ai_quota_per_day` avec un compteur daté,
     pour ne pas dépendre uniquement du plafond du fournisseur.
108. **Cascade adaptative** : apprendre la latence observée par modèle et
     remonter automatiquement le plus rapide dans l'ordre affiché.
109. **Clé partagée par appareil** : proposer un import de la clé depuis le
     gestionnaire de mots de passe du système plutôt qu'un copier-coller.
110. **Rappel d'échéance par dette** : notification locale sans montant (nom du
     contact masqué ou remplacé par « un contact »), reprogrammable.
111. **Historique d'un contact** : fiche contact regroupant créances, dettes,
     prêts et remboursements, avec solde net et dernière interaction.
112. **Échéancier des dettes** : vue calendrier des échéances à venir, avec les
     mêmes règles de masquage que le portefeuille.
113. **Annulation étendue** : proposer « Annuler » 5 s également sur la
     suppression d'un mouvement lié à une dette, en conservant le lien.

## 19. Nouvelles pistes issues de l'Étape 12 (quota, photo, Google, Home Lab)

114. **Recadrage de la photo** : cercle de recadrage avant enregistrement, pour
     éviter un avatar étiré ; rester 100 % local, sans service distant.
115. **Photo par appareil** : garder l'identité commune mais une photo différente
     sur le téléphone et sur le poste, sans synchronisation d'image.
116. **Quota visible discrètement** : pastille « n essais IA aujourd'hui » dans
     les réglages de l'assistant, jamais sur l'accueil au milieu des montants.
117. **Quota par tâche** : plafond distinct pour la saisie rapide (fréquente) et
     pour l'analyse ou le coaching (plus coûteux).
118. **Test Google sans dépôt** : bouton « Tester la connexion » qui appelle
     seulement les métadonnées du compte, sans créer de fichier.
     → *fait pour Home Lab à l'Étape 15* : `BackupService.probeRemote` + bouton
     « Tester la connexion » (GET en lecture seule, jeton Bearer), avec retour
     précis sur le jeton refusé, le certificat ou l'injoignabilité. Pour Google,
     l'appel de métadonnées reste à faire.
119. **Choix de la version Drive** : lister les cinq sauvegardes datées et
     laisser restaurer celle que l'on veut, plutôt que la plus récente.
120. **Journal des connexions** : conserver localement date, appareil et
     résultat des connexions Google, sans jeton ni adresse complète.
121. **Découverte du Home Lab** : repérer le serveur sur le Wi-Fi par mDNS
     (`akiba.local`) pour éviter de ressaisir une IP qui change.
122. **Certificat local épinglé** : accepter le certificat auto-signé du Home Lab
     en comparant son empreinte SHA-256, plutôt qu'en désactivant TLS.
123. **Rotation de la phrase secrète** : ré-envelopper la sauvegarde avec une
     nouvelle phrase, en gardant l'ancienne version jusqu'à confirmation.
124. **Recette de restauration** : un bouton « Vérifier ma sauvegarde » qui
     déchiffre et affiche les compteurs sur les trois cibles, sans rien écrire.

## 20. Nouvelles pistes issues de l'Étape 13 (thèmes, OAuth)

125. **Thème automatique par heure** : passer de Blanc à Sombre le soir sans
     casser le choix explicite du Profil (le thème manuel reste prioritaire).
126. **Thème par support** : teinter légèrement la tuile d'un compte selon son
     opérateur (Flooz, Mixx by Yas, Orabank) sans jamais dégrader le logo.
127. **Aperçu sur maquette réduite** : montrer une mini-carte de solde et une
     mini-barre basse dans le sélecteur, plutôt que des pastilles seules.
128. **Contraste vérifié à l'exécution** : test d'accessibilité qui mesure le
     rapport réel sur l'écran rendu (texte sur dégradé compris).
129. **Import du JSON OAuth par l'interface** : choisir le fichier téléchargé
     depuis le Profil, l'écrire dans le stockage privé de l'app et relancer la
     connexion, sans passer par un fichier de définitions.
130. **Comptes Google multiples** : garder un jeton par adresse et proposer le
     choix au moment de la sauvegarde, avec la même portée `appDataFolder`.
131. **Rappel de recette Google** : bannière « connexion jamais testée » après
     30 jours sans dépôt, pour éviter une sauvegarde fantôme.
132. **Mode démonstration des thèmes** : parcourir les cinq palettes sans
     enregistrer, puis confirmer, pour comparer sereinement.

## Étape 14 — Rectification

Les mentions historiques de phrases secrètes, serveur maître et dictée vocale sont supersédées : sauvegarde AES-256-GCM sans phrase, Google Drive/Home Lab uniquement et reconnaissance `onDevice`. À prioriser comme recette : OAuth sur compte test autorisé, Workmanager/permissions sur appareil, restauration réelle et captures des cinq thèmes. Multi-comptes Google et choix d’une version Drive restent des pistes futures.

Le flux Android utilise désormais une URL d’autorisation minimale du client Desktop (loopback racine, PKCE, `state`). Si cette méthode n’est pas acceptée par Google pour l’environnement Android, la piste correcte est l’intégration Google Identity Services native (client Android avec empreinte SHA-1), et non l’ajout d’autres paramètres à l’URL.

Le splash étant désormais blanc, vérifier sur appareil que le contraste du logo et du cauri animé reste satisfaisant dans les conditions réelles.

## 21. Nouvelles pistes issues de l'Étape 15 (vitesse, PIN, vocal, sauvegardes)

133. **Ouverture sans splash** : proposer « Ne plus afficher l'animation » après
     dix lancements, tout en gardant le geste cochon + cauri pour les versements.
134. **Animation adaptative** : 3 s complètes au premier lancement, 1,2 s aux
     suivants, jamais en dessous de 400 ms.
135. **Cauri par coffre** : teinter légèrement le cauri selon le coffre visé
     (urgence, objectif, libre) sans jamais changer la forme du geste.
136. **Verrouillage progressif** : après trois codes faux, délai croissant et
     message neutre, sans révéler le nombre d'essais restants (idée 71).
137. **Verrou de prévisualisation** : flouter la liste des tâches récentes du
     système quand le PIN est actif (protection contre l'aperçu Android).
138. **Résumé de dictée** : afficher la phrase entendue au-dessus de la carte
     pour que l'utilisateur voie immédiatement une mauvaise transcription.
139. **Contacts appris** : mémoriser les noms déjà utilisés en créance / dette
     pour les proposer en autocomplétion sur la carte de compréhension.
140. **Créance sans montant** : accepter « Koffi me doit de l'argent » en
     demandant le montant dans la carte plutôt qu'en refusant la phrase.
141. **Teinte d'absence** : si le Home Lab ne répond pas au test, proposer de
     mémoriser le dernier échec avec son horodatage, sans montant.
142. **Diagnostic Google en un écran** : afficher les trois causes les plus
     probables (client Web au lieu de Desktop, identifiant avec espace, portée
     non déclarée) plutôt qu'un seul message d'erreur.
143. **Plan de repli visible** : quand la connexion Google échoue, mettre le
     dossier synchronisé en avant (bouton « Utiliser le dossier ») au lieu de
     laisser l'utilisateur chercher le champ.
144. **Icônes de catégorie personnalisables** : laisser choisir une icône par
     catégorie dans les réglages, les noms restant la clé de correspondance.
145. **Catégories traduites** : la table `categories` paramétrable (M06) doit
     réutiliser `LabelIcons.forCategory`, y compris pour les libellés anglais.
146. **Test de charge du splash** : mesurer le temps jusqu'à la première image
     sur un appareil bas de gamme et le consigner dans `DEJA_FAIT.md`.

## 22. Pistes issues de l'Étape 16 (visuels, ouverture, IA multi-fournisseurs)

147. **Choix guidé du fournisseur** : proposer un test de connexion au moment
     du choix, avec le modèle et la latence mesurés, plutôt qu'un simple OK/échec.
148. **Modèles Ollama détectés** : lister les modèles réellement installés sur
     l'instance (`/api/tags`) et proposer le plus petit pour la saisie rapide.
149. **Comparateur de fournisseurs** : rejouer les dix dernières phrases sur deux
     fournisseurs et garder celui qui répond le mieux, sans jamais envoyer de
     montants en mode masqué.
150. **Coût par appel** : afficher le nombre d'unités consommées par fournisseur
     dans le quota du jour, sans montant financier.
151. **Détourage à la demande** : un petit outil dans `tool/` pour vérifier
     qu'aucun nouveau visuel n'a de frange blanche sur fond crème.
152. **Ouverture mémorisée** : ne plus montrer l'animation après dix lancements,
     tout en gardant le geste cochon + cauri pour les versements (idée 133).

## 23. Pistes issues de l'Étape 19 (configuration Google automatique)

153. **Fraîcheur de la copie embarquée** : comparer l'horodatage de
     `secrets/google_oauth.json` et de `assets/config/google_oauth.json` au
     démarrage (mode développement) et afficher un rappel discret « relancez
     tool/sync_oauth_secrets.dart » plutôt que de découvrir un identifiant
     périmé au moment de la connexion.
154. **Test de configuration en un appui** : dans le centre de sauvegarde,
     valider l'identifiant (format, suffixe, en-tête de l'URL d'autorisation)
     sans ouvrir le navigateur, et afficher la cause précise avant l'erreur
     Google.
155. **Pré-vol Android** : détecter que la redirection de boucle locale est
     utilisée depuis Android et proposer directement le repli « dossier
     synchronisé » avec un bouton, au lieu d'attendre le refus de Google.

## 24. Pistes issues de l'Étape 20 (Android natif et copie automatique)

156. **Test de bout en bout sur appareil** : un scénario instrumenté qui connecte
     un compte testeur, dépose une sauvegarde et la restaure, avec les deux voies
     (Android natif et ordinateur) et un refus volontaire pour vérifier le repli.
157. **Diagnostic SHA-1 intégré** : dans le Profil (mode développeur), afficher
     l'empreinte de signature de l'APK installé et la comparer au client Android
     déclaré, pour éviter de chercher l'erreur 28444 dans les journaux.
158. **Détection de copie périmée dans l'APK** : embarquer l'empreinte courte de
     l'identifiant dans les métadonnées de build et la comparer à `secrets/` au
     démarrage sur ordinateur, afin de signaler un APK construit avant une
     rotation d'identifiant.
159. **Second compte Google** : `google_sign_in` ne gère qu'un compte à la fois ;
     proposer « Changer de compte » en enchaînant `signOut` puis `authenticate`
     depuis l'écran de sauvegarde.

## 25. Pistes issues de l'Étape 22 (langue, permissions, règlements, déconnexion)

160. **Règlement partiel guidé** : proposer 25 / 50 / 75 / 100 % du reste dû en
     un appui, avec le compte mémorisé par contact, au lieu de ressaisir le
     montant à chaque fois.
161. **Reçu de règlement** : après un encaissement ou un paiement, afficher une
     ligne récapitulative (compte, nouveau solde, reste dû) dans l'historique
     des mouvements, sans jamais exposer le montant si le masquage est actif.
162. **Rapprochement créance/dette** : détecter qu'une entrée de compte
     correspond à une créance ouverte du même contact et proposer le règlement,
     au lieu de laisser deux lignes indépendantes.
163. **Langue par écran** : mémoriser le dernier écran d'onboarding pour que la
     bascule français/anglais reprenne exactement au même endroit.
164. **Diagnostic réseau Home Lab** : afficher l'adresse réellement testée
     (schéma compris), le temps de réponse et la cause du refus de connexion
     dans une petite carte, plutôt qu'une seule ligne de texte.
165. **Déconnexion multi-comptes** : « Changer de compte Google » enchaînant
     `signOut` puis `signIn`, avec le choix du compte, sans toucher aux données
     locales.
166. **Journal des déconnexions** : conserver localement date et appareil de la
     dernière déconnexion Google, sans jeton ni adresse.
167. **Vérification de l'autorisation avant planification** : exposer dans le
     Profil un état lisible « autorisé / refusé / refusé définitivement » relu
     au retour des réglages système.

## 26. Pistes issues de l'Étape 23 (SMS arrière-plan, bienvenue)

168. **Notification avec montant masqué intelligent** : afficher « +•••• FCFA »
     quand le masquage est actif et « +25 000 FCFA » sinon, en stockant le
     drapeau de masquage dans une préférence native non sensible (jamais de
     montant en clair).
169. **Rapprochement de SMS en double** : ignorer un SMS déjà transformé en
     écriture (référence d'opérateur conservée localement, chiffrée).
170. **Réglage fin des expéditeurs** : laisser ajouter un nom de banque ou un
     numéro court aux sources reconnues, sans changer le code.
171. **Notification groupée** : regrouper plusieurs SMS financiers reçus dans la
     même heure en une seule notification « 3 opérations à vérifier ».
172. **Bienvenue contextuelle** : proposer dans la notification un premier pas
     concret (premier compte, premier versement) et mesurer le retour dans
     l'application sans télémétrie distante.
173. **Test instrumenté du récepteur** : un test Android (`androidTest`) qui
     injecte un SMS Flooz, Mixx et Orabank et vérifie la notification et
     l'ouverture de la fiche, sans passer par un second téléphone.
174. **Confirmation rapide depuis la notification** : action « Ouvrir la fiche »
     et « Ignorer » directement dans la notification, en gardant la validation
     manuelle obligatoire.

## 27. Pistes issues du rapport mensuel (Étape 24)

175. **Rapport sur une page** : compacter les blocs et passer en deux colonnes pour
     éviter la deuxième page A4.
176. **Graphique en anneau** des catégories, dessiné nativement dans le PDF.
177. **Comparaison mois précédent** : variation en pourcentage sur chaque
     indicateur, avec une flèche discrète.
178. **Rapport annuel** agrégé, même moteur, avec sélection d'exercice.
179. **Envoi planifié** vers le Home Lab à une heure choisie (toujours local).
180. **Signature locale** du PDF (empreinte SHA-256 affichée) pour vérifier
     qu'il n'a pas été modifié après génération.
181. **Modèles d'avis** : laisser choisir entre « bienveillant », « direct » et
     « taquin » avant l'analyse IA.

## 28. Pistes issues des messages d'épargne (Étape 25)

182. **Ton réglable** : catalogue sérieux / taquin / très taquin, mémorisé.
183. **Messages liés à l'objectif** : célébrer les paliers (25 %, 50 %, 75 %)
     sans jamais afficher de montant.
184. **Taquineries contextuelles** : distinguer un retrait d'urgence d'un
     retrait d'impulsion à partir de la catégorie, sans jugement.
185. **Voix** : lire le message à voix haute si la synthèse vocale de
     l'appareil est disponible et si la personne l'active.
186. **Historique local** des messages déjà vus, pour éviter les répétitions
     au-delà de la seule fois précédente.

## 29. Suites possibles après l’Étape 26

187. **Récupération du compte Google perdu** : documenter une procédure de migration si l’utilisateur change de compte Google, sans exposer de clé dans l’interface.
188. **Préférence de son d’épargne** : interrupteur indépendant et choix entre clic discret / vibration, en respectant le mode silencieux et « Réduire les animations ».
189. **Test Android des permissions** : automatiser la demande POST_NOTIFICATIONS, l’aller-retour vers Paramètres et la relecture à la reprise.
190. **Aperçu du PDF avec avatar** : vérifier sur appareil le recadrage circulaire et les noms très longs dans l’en-tête.

## 30. Suites possibles après l’Étape 27

191. **Diagnostic des canaux de notification** : distinguer la permission POST_NOTIFICATIONS, le canal AKIBA désactivé et les restrictions de planification Android. Le test instrumenté API 33+ figure déjà en idée 189.

## 31. Suites possibles après l’Étape 28

192. **Canaux désactivés par application** : distinguer, dans le diagnostic de reprogrammation, POST_NOTIFICATIONS accordée d’un canal de bienvenue ou de rappels désactivé dans Android. → *partiellement fait* : le faux négatif venait de l’icône d’initialisation (voir Étape 29), pas du canal ; le Profil lit désormais l’importance de `akiba_rappels`. Reste à constater sur appareil le canal `akiba_accueil` et les deux cas désactivés.

## 32. Suites possibles après l’Étape 29

193. **Garde-fou d’icône de notification** : vérifier par un test instrumenté que l’icône par défaut (`drawable/ic_stat_akiba`) se résout avant la première planification, pour qu’un renommage de ressource ne réintroduise pas un faux négatif silencieux « non autorisé ».
194. **Diagnostic visible en cas d’échec d’initialisation** : afficher `LocalNotifications.lastError` (code `invalid_icon`, canal introuvable) dans le Profil plutôt qu’un simple refus, afin de distinguer une panne du greffon d’une vraie révocation système.
