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

