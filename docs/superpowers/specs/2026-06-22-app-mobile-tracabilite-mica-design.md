# Design — Application Mobile de Traçabilité du Mica Artisanal

- **Date**: 2026-06-22
- **Projet**: RADORAN — traçabilité digitale du mica artisanal
- **Composant**: Application mobile Android (collecte terrain)
- **Périmètre de ce spec**: Phases 1 + 2 (Phase 3 sécurité avancée hors périmètre)
- **Spec source**: `CDC_Application_Mobile_Tracabilite_Mica.docx`

## 1. Objectif

Application Android offline-first qui accompagne le fournisseur depuis le chargement à
la mine jusqu'à l'arrivée au dépôt. Elle capture des preuves géolocalisées
infalsifiables (photo + GPS + hash), gère les chargements multi-mines, le
transbordement et la validation d'arrivée, pré-contrôle l'éligibilité au score, puis
synchronise les données vers Odoo via une API REST custom.

Le calcul **définitif et immuable** du score et du bonus reste côté Odoo. L'application
ne fait qu'un **pré-calcul indicatif** (cohérent avec le CDC §9).

## 2. Décisions d'architecture

| Sujet | Choix | Raison |
|---|---|---|
| State management | **Riverpod** | DI + state testable, scale offline-first |
| Architecture | **Clean Architecture** feature-first (domain / data / presentation) | Isolation, testabilité |
| DB locale | **Drift + SQLCipher** | SQLite typé relationnel chiffré, requêtes file de sync/score |
| HTTP | **dio**, abstrait derrière `RemoteDataSource` | Branchement Odoo découplé, mockable |
| API Odoo | **Module REST custom** (auth token, upload multipart, batch sync) | Adapté mobile offline |
| Caméra | `camera` | Overlay guidé, capture in-app stricte |
| GPS | `geolocator` | Position + précision (HDOP) |
| OCR plaque | `google_mlkit_text_recognition` | On-device, offline |
| Hash | `crypto` (SHA-256) | Photo infalsifiable |
| Cartes | `flutter_map` | Affichage mines / trajets |
| Anti-fraude GPS | Canal natif Android (`isFromMockProvider`) | Détection mock-location (critère éliminatoire) |
| Modèle fonctionnel | `Either<Failure, T>` (dartz) | Pas d'exceptions remontant à l'UI |
| Langue | Français | Conforme CDC |

## 3. Structure du projet

```
lib/
  core/        # erreurs, network, db (Drift), di (Riverpod), utils GPS/hash, theme
  features/
    auth/            # login offline, session fournisseur
    loading/         # chargement mine + multi-mines (≤3)
    transport/       # transbordement GPS
    depot/           # arrivée dépôt + validation (Phase 2)
    scoring/         # pré-calcul score local (éligibilité + estimation)
    sync/            # file d'attente + synchronisation Odoo
    mines/           # référentiel mines (GPS + rayon)
  shared/      # widgets caméra / capture GPS réutilisables
```

Chaque feature : `domain/` (entities, repositories abstraits, usecases) +
`data/` (models, datasources local/remote, repo impl) +
`presentation/` (providers, screens, widgets).

## 4. Modules fonctionnels (unités isolées)

| Module | Responsabilité | Dépend de | Phase |
|---|---|---|---|
| **AuthModule** | Login identifiant fournisseur unique, session cache offline, accès cloisonné | DB locale | 1 |
| **CaptureService** | Photo in-app (import galerie interdit) + GPS + hash SHA-256 + overlay guidé | camera, geolocator, crypto | 1 |
| **PlateOcrService** | OCR plaque + fallback saisie manuelle | mlkit | 1 |
| **MockLocationGuard** | Détecte GPS falsifié → flag éliminatoire bloquant | canal natif | 1 |
| **MineRepository** | Référentiel mines (GPS + rayon) synchronisé d'Odoo, lu offline | Sync, DB | 1 |
| **LoadingModule** | Créer chargement, ajouter mines (≤3), générer ID `MICA-YYYY-XXXX`, saisie réf/couleur/quantité | Capture, OCR, Mine, DB | 1 |
| **SyncModule** | File d'attente persistante, upload photos multipart, retry backoff, anti-doublon | RemoteDataSource, DB | 1 |
| **TransportModule** | Transbordement : photo déchargement + rechargement, nouvelle plaque, contrôle rayon GPS | Capture, DB | 2 |
| **DepotModule** | Arrivée : chauffeur / n° permis / photo permis (opt) / n° lot, détection dépôt, validation GPS zone | Capture, DB | 2 |
| **ScoringEngine** | Pré-calcul local : Niveau 1 éligibilité (Pass/Fail) + estimation indicative Niveau 2 | DB | 2 |
| **DelaisModule** | Suivi délais d'acheminement, rappels/alertes locaux | DB | 2 |

## 5. Modèle de données (entités principales)

- **Fournisseur**: id, nom, statut actif, session.
- **Mine**: id, nom carrière, lat, lon, rayon autorisé, district, commune, région, statut.
- **Chargement**: id `MICA-YYYY-XXXX`, fournisseurId, dateCreation, statutSync, scoreEstime, mines (1–3).
- **MineChargement** (jointure): chargementId, mineId, référence, couleur, quantitéEstimée, photoId, gps, dateHeure, plaqueOcr.
- **Photo**: id, chemin fichier, hashSha256, lat, lon, précision, orientation, horodatage, type (mine/déchargement/rechargement/arrivée/permis).
- **Transbordement**: chargementId, gpsDechargement, gpsRechargement, nouvellePlaque, photos, distanceM, conforme.
- **ArriveeDepot**: chargementId, depotId, chauffeur, numPermis, photoPermisId, numLot, gps, statutGpsArrivee, photoArriveeId.
- **SyncQueue**: id, entité, payload, statut (en_attente / en_cours / synchronise / erreur), tentatives, dernièreErreur.

## 6. Flux de données (offline-first)

```
Action terrain → écriture DB locale (source de vérité) → SyncQueue (en_attente)
                                                              │
                          réseau dispo ──► SyncModule ──► REST Odoo ──► synchronise
                                                              │ échec
                                                              └─► retry backoff exponentiel
```

- Toute action écrit **d'abord** en DB locale ; l'UI lit la DB → fonctionne sans réseau.
- ID unique généré localement → dédoublonnage côté Odoo.
- Photos : fichiers sur disque + hash en DB ; upload multipart différé.
- Référentiel mines : tiré d'Odoo quand réseau dispo, consultable offline.

## 7. Règles métier critiques (à tester en priorité)

### Niveau 1 — Éligibilité (Pass / Fail) — un seul échec ⇒ rejeté
- GPS mine dans le rayon autorisé.
- Photo mine valide (in-app, claire, camion + mica).
- Fournisseur identifié et actif.
- Mine autorisée et active.
- Données complètes.
- ≤ 3 mines par chargement.
- Dépôt reconnu et actif.
- GPS non falsifié (pas de mock-location).

### Niveau 2 — Estimation indicative (sur 100)
- A. GPS (20) : ≤20 m=20 ; ≤50 m=15 ; ≤100 m=10 ; >100 m=0.
- B. Délais (25) : respecté=25 ; +10%=18 ; +25%=12 ; +50%+=0.
- C. Cohérence transport (20) : plaque cohérente + chronologie=20 ; sinon 0.
- D. Quantité (20) : écart ≤2%=20 ; ≤5%=15 ; ≤10%=10 ; >10%=0.
- E. Historique (15) : ≥95%=15 ; ≥90%=12 ; ≥80%=7 ; <80%=0.

### Validation GPS
- Distance Haversine entre point capturé et point autorisé.
- Transbordement : distance déchargement↔rechargement ≤ rayon paramétré ⇒ conforme.
- Arrivée : position dans rayon dépôt ⇒ validée ; détection auto du dépôt concerné.

## 8. Gestion des erreurs

- `Either<Failure, T>` dans tous les usecases — aucune exception ne remonte à l'UI.
- Sync : file persistante, retry exponentiel, écriture avant toute tentative réseau ⇒ aucune perte.
- GPS faible / HDOP élevé ⇒ avertissement non bloquant + score réduit.
- Mock-location détecté ⇒ blocage (critère éliminatoire).
- OCR échoué ⇒ fallback saisie manuelle de la plaque.

## 9. Stratégie de tests

- **Unit** : usecases, `ScoringEngine` (règles Niveau 1 et 2), `MockLocationGuard`, calcul distance Haversine, génération ID `MICA-YYYY-XXXX`.
- **Repository** : DB Drift in-memory + `RemoteDataSource` mocké.
- **Widget** : écrans capture, chargement, ajout mine, arrivée dépôt.
- **TDD** sur toute la logique métier déterministe (scoring, validation GPS) — critique anti-fraude.

## 10. Hors périmètre (Phase 3, plus tard)

- Journal immuable / blockchain.
- Audits terrain aléatoires automatisés.
- Analytique prédictive avancée.

## 11. Dépendances vers d'autres composants

- **Module Odoo Cartographie (RADORAN)** : fournit le référentiel mines (GPS + rayon + géométrie).
- **Module Odoo Traçabilité** : reçoit les chargements, calcule le score/bonus définitif, crée le bon de commande brouillon.
- **Portail Fournisseur** : consulte les données synchronisées (lecture).
