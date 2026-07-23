## v1.2.0 - 2026-07-23


## v1.1.0 - 2026-07-23

- chore(release): v1.1.0
- feat(detail): afficher les photos des transbordements et de l'arrivée
- feat(loading): masquer le champ référence de lot au nouveau chargement
- feat(sync): détail d'un envoi + masquer la référence à la mine
- feat(sync): page historique de synchronisation
- feat(detail): carte du trajet GPS + badge sync dans la liste des lots
- feat(sync): statut de sync par lot + envoi manuel, sans double envoi
- feat(scoring): ne plus bloquer sur coords serveur cassées, refléter le GPS dans le score
- feat(detail): éditer/supprimer un transbordement tant que le lot est en cours
- feat(profile): carte OpenStreetMap au clic sur une mine ou un dépôt
- fix(auth): lire data.depots dans la réponse /api/storage
- fix(auth): le login ne dépend plus du référentiel + messages d'erreur précis
- feat(profile): page compte listant mines et dépôts du fournisseur
- feat(auth): bouton voir/cacher le mot de passe
- fix(auth): erreur de connexion en dialog modal + masquage du clavier
- fix(ui): icônes des barres système lisibles sur l'écran de connexion
- chore(net): rendre le mode réel testable contre un Odoo local
- chore(release): v1.1.0
- feat(api): aligner sur la collection Postman RADORAN
- refactor(lot): chaque lot suit son propre camion — zéro partage entre lots
- docs(api): 1 payload = 1 LOT (mine objet, submit+upload par lot)
- wip(lot): UI refactorée pour le modèle LOT
- wip(lot): refactor — LOT = unité de traçabilité (données/domaine/sync)
- feat(loading): référence de lot optionnelle (regroupement Odoo multi-camions)
- docs(api): 2 éléments par tableau (mines, transloads) + note mines vs transloads
- chore(api): endpoints /api/terrain/* → /api/geospatial/*
- feat(sync): upload photos rattaché au load_id (payload id) + doc en français
- refactor(api): clés JSON en anglais + doc mise à jour
- feat(sync): upload photos en batch après submit + purge locale (stage 3)
- feat(sync): envoi unique par chargement — snapshot complet à l'arrivée (stage 2)
- docs(api): contrat endpoints terrain_api (login, submit, upload batch, status)
- feat(auth): login distant (identifiant + mot de passe → token + référentiel)
- feat(sync): conformité au contrat Odoo terrain_api (Technarea)
- docs: documentation + diagramme ER de la base (schema v7, mermaid)
- feat(sync): WorkManager background + odoo_id + cutoff 5 tentatives + batch 10
- chore(release): choix du remote (origin par défaut, ex. radoran)

## v1.0.1 - 2026-07-08

- fix(trip): sim — plaques transbordement chaînées (camion qui tourne)
- feat(trip): sim — plaques aléatoires réalistes cohérentes, remplies après la photo
- feat(trip): simulation guidée du trajet (étape 3)
- feat(trip): carte du parcours dans le détail (étape 2)
- feat(trip): suivi de parcours GPS en arrière-plan (étape 1)
- chore: ignore local keystore and jks files in git
- fix(android): démo en applicationId .demo + signature release stable (keystore optionnel)

## v0.1.0 - 2026-07-02

- chore: remove obsolete v0.1.0 changelog file
- chore(release): script met à jour CHANGELOG.md + re-tag + push
- chore(release): v0.1.0
- ci: APK universel (sans split ABI) en release — prod + démo
- ci: build APK démo + prod paramétrés (--dart-define, MICA_ODOO_URL variable repo)
- refactor(config): mode démo via flag --dart-define (MICA_DEMO / MICA_ODOO_URL)
- fix(sync): robustesse — pull au démarrage, backoff respecté, reset syncing, anti-double
- feat(dev): menu Scénarios (debug) pour tester sur vrai appareil
- feat(ui): confirmation déconnexion + suppression chargements non finalisés
- feat(ui): drawer compte connecté + déconnexion sur l'accueil
- feat(nav): migration vers go_router (routes centralisées, garde auth, deep-link notif)
- style: fix lint underscores wildcard (photo_view)
- style(ui): animation zoom (Hero) à l'ouverture des photos
- feat(ui): détail enrichi — badge statut, photos cliquables (viewer zoom), sections repliables
- style(ui): réduit les border radius (boutons, cards, inputs, dialogs)
- style(ui): polices Montserrat + ABeeZee, tailles réduites mobile
- ci: script release + workflow build APK (artifact + release, changelog)
- feat(ui): écran détail d'un chargement (lecture seule)
- feat(ui): écran d'accueil — historique des chargements + nouveau
- feat(ui): remplace les SnackBars par des dialogs modaux
- refactor: replace SnackBars with custom modal showAppMessage dialogs across features
- fix(db): stratégie de migration drift (recréation destructive en pré-prod)
- feat: add empty AppBar to login screen to prevent back navigation
- fix(android): active core library desugaring (flutter_local_notifications)

