# IDEES_AMELIORATION — Pistes AKIBA

Dernière mise à jour : **20/11/2026**. Les idées 19 (vues SQL agrégées) et 26
(libellés lecteur d'écran) sont **partiellement appliquées** depuis les Étapes
1.2 et 1.3 : vue `v_account_balances` et libellés complets sur les lignes de
mouvement. Les autres restent à arbitrer par le porteur du projet.

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

