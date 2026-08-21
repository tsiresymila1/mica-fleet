# Contrat API complet — MICA Fleet ↔ Radoran/Odoo

Référence unique pour l’application Flutter Android et le backend.

**Version du contrat : 3 — 14 août 2026.**

## Conventions

- Base URL configurée par `MICA_ODOO_URL`, sans `/api` final.
- JSON, sauf `POST /api/attachments` en `multipart/form-data`.
- `Authorization: Bearer <token>` sur tous les endpoints hors login.
- Dates UTC : `YYYY-MM-DD HH:mm:ss`.
- Succès : `{ "status": "ok|created|already_synced", "data": ... }`.
- Erreur : HTTP approprié et `{ "status": "error", "message": "..." }`.
- `payload.id`, `session_id` et `device_uuid` sont des UUID v4 stables.
- Le backend déduplique les submits sur `device_uuid` et les photos sur
  `payload_id + key + hash`.

## Endpoints

| Méthode | Endpoint | Usage |
|---|---|---|
| `POST` | `/api/login` | Connexion |
| `POST` | `/api/password/change` | Modifier le mot de passe |
| `GET` | `/api/mine` | Mines validées |
| `GET` | `/api/commune` | Référentiel des communes (hors proposition de mine) |
| `GET` | `/api/storage` | Dépôts, affichage informatif |
| `POST` | `/api/mine` | Proposer une mine |
| `POST` | `/api/tracking/submit` | Envoyer un lot complet |
| `POST` | `/api/attachments` | Envoyer une photo |
| `GET` | `/api/tracking/lots` | Restaurer/actualiser les lots |
| `GET` | `/api/app/version` | Vérifier une version Android |
| `POST` | `/api/logout` | Fermer la session |

## Authentification

### `POST /api/login`

```json
{ "login": "rakoto", "password": "secret" }
```

```json
{
  "status": "ok",
  "data": {
    "token": "token",
    "agent": { "id": 1, "login": "rakoto", "name": "Rakoto" }
  }
}
```

Après une connexion distante réussie, l’application mémorise un vérificateur
non réversible du mot de passe dans le stockage chiffré Android. Le login hors
ligne exige alors le même identifiant et le même mot de passe.

### `POST /api/password/change`

```json
{
  "current_password": "ancien-secret",
  "new_password": "nouveau-secret"
}
```

Réponse :

```json
{ "status": "ok", "data": { "password_changed": true } }
```

Erreurs métier : `400`, `401`, `403` ou `422`, avec un `message` lisible.
Sans réseau, l’application modifie son accès hors ligne et conserve la demande
dans le stockage chiffré. Elle rejoue automatiquement cet endpoint à la
prochaine synchronisation, puis efface les deux mots de passe temporaires.
Plusieurs changements hors ligne sont regroupés : mot de passe serveur initial
vers dernier mot de passe choisi.

## Référentiels

### `GET /api/mine`

Retourne uniquement les mines validées et visibles par l’utilisateur :

```json
{
  "status": "ok",
  "data": {
    "mines": [
      {
        "id": 42,
        "name": "Mine Andilana",
        "reference": "REF-MINE-42",
        "created_at": "2026-08-14 07:30:00",
        "fokontany": "Andilana",
        "commune": "Ambohidratrimo",
        "district": "Ambohidratrimo",
        "region": "Analamanga",
        "lat": -18.91,
        "lon": 47.52,
        "radius_m": 20,
        "active": true
      }
    ]
  }
}
```

Le cache est remplacé sans doublon à chaque synchronisation. La présence de
l’identifiant serveur d’une proposition dans cette liste valide la proposition.
`reference` et `created_at` sont affichés dans la fiche mine du compte. La note
canonique est fournie par `mine.note` dans `GET /api/tracking/lots`.

Quand l'id Odoo d'une proposition apparaît dans ce référentiel, l'application
affiche uniquement cette mine canonique dans le compte et les sélecteurs. Le
placeholder local reste invisible en base jusqu'à la fin des éventuels lots
hors ligne qui le référencent, afin d'éviter toute rupture de relation locale.

Dès que `POST /api/mine` renvoie `data.id`, le mobile utilise cet identifiant
comme mine serveur dans les listes, même si la validation n'est pas encore
visible dans `GET /api/mine`. Si l'agent supprime ensuite la fiche locale, une
correspondance technique invisible est conservée : la mine serveur reste donc
sélectionnable et un refetch ne la fait pas disparaître.

### `GET /api/commune`

Retourne les communes actives. L'application remplace ce cache sans doublon
après la connexion et à chaque synchronisation ; la recherche reste donc
disponible hors ligne.

```json
{
  "status": "ok",
  "data": {
    "communes": [
      {
        "id": 24091,
        "name": "Andilana",
        "district": "Ambohidratrimo",
        "active": true
      }
    ]
  }
}
```

### `GET /api/storage`

```json
{
  "status": "ok",
  "data": {
    "depots": [
      {
        "id": 2,
        "name": "Dépôt Tana",
        "lat": -18.879,
        "lon": 47.508,
        "radius_m": 20,
        "active": true
      }
    ]
  }
}
```

Le dépôt n’est jamais choisi dans un lot v3. Le backend l’identifie depuis le
GPS d’arrivée. Ce référentiel reste disponible pour affichage informatif.

## Proposition de mine

### `POST /api/mine`

L'application ne demande aucune commune à l'agent et n'envoie pas de
`commune_id`. Le backend détermine le fokontany, la commune, le district et la
région à partir des positions GPS de la proposition.

```json
{
  "device_uuid": "8e24d116-c6f2-438f-aa08-9fb1fed1c75f",
  "agent_login": "rakoto",
  "collected_at": "2026-08-14 07:30:00",
  "payload": {
    "id": "af266f45-f338-4d48-b4fc-a9a86bc62546",
    "name": "Nouvelle mine",
    "positions": [
      {
        "key": "position_1",
        "hash": "sha256-hex",
        "lat": -18.91001,
        "lon": 47.52001,
        "gps_accuracy": 4.2,
        "heading_deg": 126.4,
        "heading_accuracy": 8.0,
        "heading_reference": "magnetic",
        "captured_at": "2026-08-14 07:20:00"
      }
    ]
  }
}
```

- `positions` contient au moins 5 éléments.
- Chaque `key` et `hash` correspond ensuite à un upload unitaire.
- La réponse contient l’id de la mine proposée dans `data.id`.
- Après les photos, la proposition reste `pending_validation` jusqu’à ce que
  son id apparaisse dans `GET /api/mine`.

### Dépendance d'un lot à une proposition locale

Une proposition non synchronisée peut être choisie pour créer un lot hors
ligne. Le mobile n'envoie toutefois jamais son UUID local dans
`payload.mine.mine_id`. Avant `POST /api/tracking/submit`, il exécute :

1. `POST /api/mine` ;
2. la sauvegarde locale de `data.id` renvoyé par Odoo ;
3. le remplacement de `payload.mine.mine_id` par cet id numérique ;
4. `POST /api/tracking/submit` dans la même synchronisation.

Les photos de position sont synchronisées indépendamment et ne bloquent pas le
lot. Seul l'échec de `POST /api/mine`, donc l'absence de `data.id`, maintient le
lot `pending` sans consommer de tentative d'envoi. Une mine rejetée bloque
définitivement le lot avec le motif du rejet.

## Envoi d’un lot v3

### `POST /api/tracking/submit`

Un submit représente exactement un lot. La référence de traçabilité et le
dépôt sont calculés côté backend.

```json
{
  "device_uuid": "83a793d5-1a27-47db-b444-538fe6b21d85",
  "agent_login": "rakoto",
  "collected_at": "2026-08-14 08:00:00",
  "collect_type": "chargement",
  "gps_lat": -18.91,
  "gps_lon": 47.52,
  "gps_accuracy": 5.0,
  "payload": {
    "id": "84a0de8e-450c-46f9-a8b6-1d216f306677",
    "session_id": "bfc1487b-9e8a-4944-aa28-e19573b7dc02",
    "supplier_id": "rakoto",
    "photo_schema_version": 3,
    "status": "arrive",
    "created_at": "2026-08-14 08:00:00",
    "mine": {
      "mine_id": 42,
      "reference": null,
      "color": "Blanc",
      "estimated_quantity": 120.0,
      "plate": "1234 TBR",
      "lat": -18.91,
      "lon": 47.52,
      "gps_accuracy": 5.0,
      "captured_at": "2026-08-14 08:00:00",
      "photos": {
        "plate": { "key": "mine_plate", "hash": "sha256-hex" },
        "truck_with_mica": {
          "key": "mine_truck_with_mica",
          "hash": "sha256-hex"
        }
      }
    },
    "transloads": [
      {
        "order": 1,
        "plate_before": "1234 TBR",
        "plate_after": "5678 ABC",
        "gps_unload": [-18.92, 47.53],
        "gps_reload": [-18.9201, 47.5301],
        "distance_m": 15.7,
        "compliant": true,
        "photos_unload": {
          "plate": {
            "key": "transload_1_unload_plate",
            "hash": "sha256-hex"
          },
          "truck_with_mica": {
            "key": "transload_1_unload_truck_with_mica",
            "hash": "sha256-hex"
          }
        },
        "photos_reload": {
          "plate": {
            "key": "transload_1_reload_plate",
            "hash": "sha256-hex"
          },
          "truck_with_mica": {
            "key": "transload_1_reload_truck_with_mica",
            "hash": "sha256-hex"
          }
        }
      }
    ],
    "arrival": {
      "driver": "Rakoto",
      "license_number": "P-123",
      "gps": [-18.879, 47.508],
      "gps_status": "pending_server",
      "plate_arrival": "5678 ABC",
      "plate_consistent": true,
      "traceability_score": 80,
      "photos_unload": {
        "plate": { "key": "depot_unload_plate", "hash": "sha256-hex" },
        "truck_with_mica": {
          "key": "depot_unload_truck_with_mica",
          "hash": "sha256-hex"
        }
      },
      "photo_license": null
    },
    "track": [
      [-18.91, 47.52, "2026-08-14 08:00:00"],
      [-18.879, 47.508, "2026-08-14 10:30:00"]
    ],
    "traceability_score": 80
  }
}
```

Absents volontairement en v3 : `payload.lot_reference`, `arrival.depot_id`,
`arrival.lot_number`, `arrival.lots`, `commune_id` et le rôle photo `mica`.
Le score envoyé par le mobile est provisoire ; le backend retourne le score
final après attribution du dépôt et contrôle métier.

Réponse :

```json
{
  "status": "created",
    "data": {
    "id": 987,
    "payload_id": "84a0de8e-450c-46f9-a8b6-1d216f306677",
    "validation_status": "pending",
    "required_attachments": 8,
    "received_attachments": 0
  }
}
```

Nombre obligatoire : 2 pour la mine + 4 par transbordement + 2 à l’arrivée.
La photo du permis reste optionnelle. Les anciens schémas v1/v2 restent
acceptés par le backend pour les données déjà enregistrées.

## Photos

### `POST /api/attachments`

Une requête par fichier, pour un lot comme pour une proposition de mine :

```text
Content-Type: multipart/form-data

payload_id = 84a0de8e-450c-46f9-a8b6-1d216f306677
device_uuid = 83a793d5-1a27-47db-b444-538fe6b21d85
key = mine_plate
hash = <sha256 hex>
file = <JPEG>
```

Il n’y a pas de champ `entity_type`. `payload_id` identifie l’objet parent.
Le fichier est envoyé seulement après le submit parent. Le serveur vérifie le
SHA-256 et accepte le rejeu idempotent du même fichier.

## Restauration et validation des lots

### `GET /api/tracking/lots`

Paramètres optionnels : `updated_since` UTC et pagination standard backend.
Le backend retourne tous les lots accessibles à l’utilisateur connecté, y
compris ceux créés sur un autre téléphone.

Chaque élément de `data.lots` reprend l'objet `payload` envoyé dans
`POST /api/tracking/submit`. Le backend ajoute ou actualise les informations
canoniques suivantes :

- `traceability_reference` : référence définitive créée par le backend ;
- `validation_status` : `pending`, `validated` ou `rejected` ;
- `validation_reason` : motif du rejet, sinon `null`.
- `mine.note` : note de la mine affichée par le mobile ;
- `traceability_score` : score final calculé par le serveur.

Il ne faut donc pas renommer `payload.id` en `payload_id` dans cette réponse.

```json
{
  "status": "ok",
  "data": {
    "lots": [
      {
        "id": "84a0de8e-450c-46f9-a8b6-1d216f306677",
        "session_id": "bfc1487b-9e8a-4944-aa28-e19573b7dc02",
        "supplier_id": "rakoto",
        "photo_schema_version": 3,
        "status": "arrive",
        "created_at": "2026-08-14 08:00:00",
        "mine": {
          "mine_id": 42,
          "reference": null,
          "note": "Observation issue de la traçabilité",
          "color": "Blanc",
          "estimated_quantity": 120.0,
          "plate": "1234 TBR",
          "lat": -18.91,
          "lon": 47.52,
          "gps_accuracy": 5.0,
          "captured_at": "2026-08-14 08:00:00",
          "photos": {
            "plate": { "key": "mine_plate", "hash": "sha256-hex" },
            "truck_with_mica": {
              "key": "mine_truck_with_mica",
              "hash": "sha256-hex"
            }
          }
        },
        "transloads": [],
        "arrival": {
          "driver": "Rakoto",
          "license_number": "P-123",
          "gps": [-18.879, 47.508],
          "gps_status": "valide",
          "plate_arrival": "1234 TBR",
          "plate_consistent": true,
          "traceability_score": 96,
          "photos_unload": {
            "plate": {
              "key": "depot_unload_plate",
              "hash": "sha256-hex"
            },
            "truck_with_mica": {
              "key": "depot_unload_truck_with_mica",
              "hash": "sha256-hex"
            }
          },
          "photo_license": null
        },
        "track": [
          [-18.91, 47.52, "2026-08-14 08:00:00"],
          [-18.879, 47.508, "2026-08-14 10:30:00"]
        ],
        "traceability_score": 96,
        "traceability_reference": "MICA-2026-0042",
        "validation_status": "validated",
        "validation_reason": null
      }
    ]
  }
}
```

Valeurs canoniques de `validation_status` :

- `pending` : en attente / en cours de validation ;
- `validated` : validé ;
- `rejected` : rejeté, avec `validation_reason`.

L’état « envoyé/synchronisé » reste un état technique calculé par le mobile,
distinct de la validation métier. Le mobile fusionne sur `payload.id`, met à
jour référence/statut/score sans doublon, et crée une ligne de cache distante
si le lot n’existe pas sur l’appareil.

La note affichée dans les fiches mine provient exclusivement de `mine.note`
dans cette réponse. Le score visible sur les cartes et dans le détail d'un lot
provient exclusivement de `traceability_score` retourné ici. Le score calculé
sur le mobile à l'arrivée reste provisoire et n'est pas affiché comme score
final.

Dans l'écran du compte, une mine affiche son nom, sa référence, sa date de
création et cette note, sans coordonnées GPS. Un appui ouvre un sheet contenant
les lots dont `payload.mine.mine_id` correspond à l'id de la mine.

## Mise à jour Android

### `GET /api/app/version`

Requête :

```text
/api/app/version?platform=android&current_build=114
```

```json
{
  "status": "ok",
  "data": {
    "available": true,
    "version": "1.2.7",
    "build": 115,
    "apk_url": "https://staging.radoran.net/releases/mica-fleet-115.apk",
    "sha256": "sha256-hex-du-fichier",
    "mandatory": false,
    "release_notes": "Corrections et améliorations"
  }
}
```

Si aucune version plus récente n’existe :

```json
{ "status": "ok", "data": { "available": false } }
```

L’URL doit être HTTPS et l’APK signé avec la même clé que l’application
installée. Le mobile télécharge dans son cache privé, vérifie `sha256`, puis
ouvre l’installateur Android. Sur un appareil standard, Android demande à
l’utilisateur d’autoriser la source puis de confirmer l’installation ; une
installation réellement silencieuse exige une gestion d’appareil dédiée.

## Synchronisation au démarrage

Quand une connexion est disponible, puis à chaque retour du réseau et action
manuelle, l’application exécute dans cet ordre :

1. changement de mot de passe en attente ;
2. envoi des propositions requises par les lots ;
3. envoi immédiat des lots avec le `mine_id` Odoo résolu ;
4. upload unitaire des photos de lots et de mines ;
5. `GET /api/mine` ;
6. `GET /api/storage` ;
7. `GET /api/commune` ;
8. `GET /api/tracking/lots`.

Chaque endpoint est indépendant : un échec conserve le cache et sera rejoué.
