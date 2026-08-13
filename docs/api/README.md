# Contrat API complet — Mica Fleet ↔ Radoran/Odoo

Ce fichier est la référence unique pour l’intégration entre l’application
Flutter Android et l’API Radoran/Odoo. Il couvre l’authentification, les
référentiels, la traçabilité des lots, les pièces jointes et la proposition
manuelle d’une mine.

**Version du contrat photo : 2 — mise à jour du 13 août 2026.** Cette version
remplace la photo unique des étapes de traçabilité par trois preuves
obligatoires : plaque, mica et camion contenant le mica.

## 1. Conventions générales

- Base URL : `https://<serveur>` configurée par `MICA_ODOO_URL`.
- Tous les chemins commencent par `/api/`.
- Corps métier : JSON, sauf les photos en `multipart/form-data`.
- Authentification : `Authorization: Bearer <token>` sur tous les endpoints
  protégés.
- Dates : UTC au format Odoo `YYYY-MM-DD HH:mm:ss`.
- Toutes les clés JSON sont en anglais.
- Réponse réussie : `status` vaut `ok` ou `created`.
- Réponse en erreur : `status` vaut `error` et `message` doit être lisible.

### Identifiants

| Champ | Format | Rôle |
|---|---|---|
| `payload.id` | UUID v4 | Identifiant stable d’un lot ou d’une proposition |
| `session_id` | UUID v4 | Regroupe les lots partis dans la même session |
| `device_uuid` | UUID v4 | Clé d’idempotence stable d’un submit |
| `payload_id` | UUID v4 | Référence `payload.id` pendant l’upload photo |
| `key` | string | Type/position unique de la photo dans le payload |
| `hash` | SHA-256 | Contrôle d’intégrité et déduplication de la photo |

Le rejeu du même `device_uuid` ne doit jamais créer un deuxième objet. Le
rejeu du même triplet `payload_id + key + hash` ne doit jamais créer une
deuxième pièce jointe.

## 2. Liste des endpoints

| Méthode | Endpoint | Auth | Usage |
|---|---|---|---|
| `POST` | `/api/login` | Non | Authentifier l’agent |
| `GET` | `/api/mine` | Bearer | Charger les mines autorisées |
| `GET` | `/api/storage` | Bearer | Charger les dépôts autorisés |
| `GET` | `/api/commune` | Non | Charger les communes |
| `POST` | `/api/tracking/submit` | Bearer | Envoyer un lot complet |
| `POST` | `/api/mine` | Bearer | Proposer une nouvelle mine |
| `POST` | `/api/attachments` | Bearer | Envoyer une photo, une requête par fichier |
| `POST` | `/api/logout` | Bearer | Invalider une session côté serveur |

## 3. Authentification

### `POST /api/login`

Requête sans Bearer token :

```json
{
  "login": "eddy",
  "password": "secret"
}
```

Réponse HTTP 200 :

```json
{
  "status": "ok",
  "data": {
    "token": "72cad47ff9ba4a6dacf61dc3631abddd",
    "agent": {
      "id": 1,
      "login": "eddy",
      "name": "Fournisseur X"
    }
  }
}
```

Erreur HTTP 401 :

```json
{
  "status": "error",
  "message": "Identifiant ou mot de passe incorrect"
}
```

Après un login réussi, l’application charge `/api/mine`, `/api/storage` et
`/api/commune`. Ces référentiels sont conservés dans SQLite pour permettre le
travail hors ligne. L’indisponibilité temporaire d’un référentiel ne doit pas
annuler le login ; le dernier cache local reste utilisable.

## 4. Référentiels

Les trois endpoints acceptent une liste nue, `{ "data": [...] }`, ou un objet
`data` contenant la liste nommée.

### `GET /api/mine`

```json
{
  "status": "ok",
  "data": [
    {
      "id": 1,
      "name": "Carrière Andilana",
      "lat": -18.91000,
      "lon": 47.52000,
      "radius_m": 20,
      "district": "Ambohidratrimo",
      "commune": "Andilana",
      "region": "Analamanga",
      "active": true
    }
  ]
}
```

`radius_m` est utilisé pour le contrôle GPS. En son absence, l’application
applique 20 mètres. Une mine avec `active: false` n’est plus sélectionnable.

### `GET /api/storage`

```json
{
  "status": "ok",
  "data": [
    {
      "id": 2,
      "name": "Dépôt Antananarivo",
      "lat": -18.87900,
      "lon": 47.50800,
      "radius_m": 20,
      "active": true
    }
  ]
}
```

### `GET /api/commune`

```json
{
  "status": "ok",
  "data": [
    {
      "id": 24091,
      "name": "Andilana",
      "district": "Ambohidratrimo",
      "active": true
    }
  ]
}
```

`id` et `name` sont obligatoires. `district` sert uniquement à faciliter la
recherche dans l’interface. Une commune inactive est masquée. La proposition
d’une nouvelle mine envoie uniquement son identifiant dans `commune_id`.

## 5. Envoyer la traçabilité d’un lot

### `POST /api/tracking/submit`

Un payload représente exactement un lot issu d’une mine. Un camion chargé
depuis trois mines produit donc trois submits. Les trois lots peuvent partager
le même `session_id`, mais chacun possède son propre `payload.id` et son propre
`device_uuid`.

```json
{
  "device_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "agent_login": "eddy",
  "collected_at": "2026-06-22 08:00:00",
  "collect_type": "chargement",
  "gps_lat": -18.91000,
  "gps_lon": 47.52000,
  "gps_accuracy": 5.0,
  "payload": {
    "id": "de305d54-75b4-431b-adb2-eb6b9e546014",
    "session_id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
    "supplier_id": "eddy",
    "lot_reference": "LOT-A-2026-06-22",
    "photo_schema_version": 2,
    "status": "arrive",
    "created_at": "2026-06-22 08:00:00",
    "mine": {
      "mine_id": 1,
      "reference": "REF-1",
      "color": "Blanc",
      "estimated_quantity": 120,
      "plate": "1234 TBR",
      "lat": -18.91000,
      "lon": 47.52000,
      "gps_accuracy": 5.0,
      "captured_at": "2026-06-22 08:00:00",
      "photos": {
        "plate": {
          "key": "mine_plate",
          "hash": "9f2c...e7",
          "lat": -18.91001,
          "lon": 47.52001,
          "gps_accuracy": 4.2,
          "captured_at": "2026-06-22 07:58:00",
          "heading_deg": 15.0,
          "heading_accuracy": 1.5,
          "heading_reference": "magnetic"
        },
        "mica": {
          "key": "mine_mica",
          "hash": "82ad...11",
          "lat": -18.91002,
          "lon": 47.52002,
          "gps_accuracy": 4.6,
          "captured_at": "2026-06-22 07:59:00",
          "heading_deg": 25.0,
          "heading_accuracy": 2.0,
          "heading_reference": "magnetic"
        },
        "truck_with_mica": {
          "key": "mine_truck_with_mica",
          "hash": "35bc...a9",
          "lat": -18.91000,
          "lon": 47.52000,
          "gps_accuracy": 5.0,
          "captured_at": "2026-06-22 08:00:00",
          "heading_deg": 35.0,
          "heading_accuracy": 2.5,
          "heading_reference": "magnetic"
        }
      }
    },
    "transloads": [
      {
        "order": 1,
        "plate_before": "1234 TBR",
        "plate_after": "5678 ABC",
        "gps_unload": [-18.92000, 47.53000],
        "gps_reload": [-18.92010, 47.53000],
        "distance_m": 11.4,
        "compliant": true,
        "photos_unload": {
          "plate": {
            "key": "transload_1_unload_plate",
            "hash": "44bd...10",
            "lat": -18.92000,
            "lon": 47.53000,
            "gps_accuracy": 5.1,
            "captured_at": "2026-06-22 08:20:00",
            "heading_deg": 90.0,
            "heading_accuracy": 2.0,
            "heading_reference": "magnetic"
          },
          "mica": {
            "key": "transload_1_unload_mica",
            "hash": "55ce...21",
            "lat": -18.92001,
            "lon": 47.53001,
            "gps_accuracy": 5.0,
            "captured_at": "2026-06-22 08:21:00",
            "heading_deg": 100.0,
            "heading_accuracy": 2.2,
            "heading_reference": "magnetic"
          },
          "truck_with_mica": {
            "key": "transload_1_unload_truck_with_mica",
            "hash": "66df...32",
            "lat": -18.92002,
            "lon": 47.53002,
            "gps_accuracy": 5.3,
            "captured_at": "2026-06-22 08:22:00",
            "heading_deg": 110.0,
            "heading_accuracy": 2.4,
            "heading_reference": "magnetic"
          }
        },
        "photos_reload": {
          "plate": {
            "key": "transload_1_reload_plate",
            "hash": "77e0...43",
            "lat": -18.92010,
            "lon": 47.53000,
            "gps_accuracy": 4.8,
            "captured_at": "2026-06-22 08:30:00",
            "heading_deg": 180.0,
            "heading_accuracy": 3.0,
            "heading_reference": "magnetic"
          },
          "mica": {
            "key": "transload_1_reload_mica",
            "hash": "88f1...54",
            "lat": -18.92011,
            "lon": 47.53001,
            "gps_accuracy": 4.9,
            "captured_at": "2026-06-22 08:31:00",
            "heading_deg": 190.0,
            "heading_accuracy": 3.1,
            "heading_reference": "magnetic"
          },
          "truck_with_mica": {
            "key": "transload_1_reload_truck_with_mica",
            "hash": "99a2...65",
            "lat": -18.92012,
            "lon": 47.53002,
            "gps_accuracy": 5.0,
            "captured_at": "2026-06-22 08:32:00",
            "heading_deg": 200.0,
            "heading_accuracy": 3.2,
            "heading_reference": "magnetic"
          }
        }
      }
    ],
    "arrival": {
      "depot_id": 2,
      "driver": "Rakoto",
      "license_number": "P-123",
      "lot_number": "LOT-2026-0042",
      "lots": { "Blanc": "LOT-2026-0042" },
      "gps": [-18.87900, 47.50800],
      "gps_status": "valide",
      "plate_arrival": "5678 ABC",
      "plate_consistent": true,
      "traceability_score": 100,
      "photos_unload": {
        "plate": {
          "key": "depot_unload_plate",
          "hash": "aab3...76",
          "lat": -18.87900,
          "lon": 47.50800,
          "gps_accuracy": 4.0,
          "captured_at": "2026-06-22 10:30:00",
          "heading_deg": 270.0,
          "heading_accuracy": 4.0,
          "heading_reference": "magnetic"
        },
        "mica": {
          "key": "depot_unload_mica",
          "hash": "bbc4...87",
          "lat": -18.87901,
          "lon": 47.50801,
          "gps_accuracy": 4.2,
          "captured_at": "2026-06-22 10:31:00",
          "heading_deg": 280.0,
          "heading_accuracy": 4.1,
          "heading_reference": "magnetic"
        },
        "truck_with_mica": {
          "key": "depot_unload_truck_with_mica",
          "hash": "ccd5...98",
          "lat": -18.87902,
          "lon": 47.50802,
          "gps_accuracy": 4.3,
          "captured_at": "2026-06-22 10:32:00",
          "heading_deg": 290.0,
          "heading_accuracy": 4.2,
          "heading_reference": "magnetic"
        }
      },
      "photo_license": {
        "key": "license",
        "heading_deg": 315.0,
        "heading_accuracy": 5.0,
        "heading_reference": "magnetic"
      }
    },
    "track": [
      [-18.91000, 47.52000, "2026-06-22 08:00:00"],
      [-18.87900, 47.50800, "2026-06-22 10:30:00"]
    ],
    "traceability_score": 100
  }
}
```

Les valeurs de `hash` sont abrégées dans cet exemple pour rester lisibles. Une
requête réelle transmet toujours les 64 caractères hexadécimaux du SHA-256.

Règles métier principales :

- `mine` est un objet unique, jamais une liste.
- Un lot ne peut pas être divisé.
- `estimated_quantity` est figée au départ.
- La chaîne des plaques doit rester cohérente entre départ, transbordements et
  arrivée.
- `mine_id` et `depot_id` sont les identifiants renvoyés par les référentiels.
- `traceability_score` est calculé par lot.
- `photo_schema_version=2` rend obligatoires les trois rôles photo à chaque
  étape opérationnelle : `plate`, `mica` et `truck_with_mica`.
- Un transbordement comprend deux étapes distinctes, déchargement et
  rechargement : il exige donc six photos au total.
- La photo `plate` est la seule source destinée à la reconnaissance OCR. Le
  résultat OCR reste transmis dans `mine.plate`, `plate_before`, `plate_after`
  ou `arrival.plate_arrival` selon l’étape.
- `photo_license` reste une preuve administrative distincte. Elle ne remplace
  aucune des trois photos de déchargement au dépôt.
- Les photos binaires ne sont pas intégrées au JSON ; elles sont envoyées
  après le submit.

Réponse de création HTTP 201 :

```json
{
  "status": "created",
  "data": {
    "id": 42,
    "state": "draft",
    "photo_schema_version": 2,
    "required_attachments": 13,
    "received_attachments": 0
  }
}
```

Dans cet exemple avec un transbordement, 12 photos métier sont obligatoires et
la photo de permis déclarée porte le total à 13. `required_attachments` doit
être calculé depuis le payload, et non fixé à une constante.

Rejeu idempotent HTTP 200 :

```json
{
  "status": "ok",
  "message": "already_synced",
  "data": { "id": 42 }
}
```

L’application conserve `data.id` comme identifiant technique Odoo.

## 6. Métadonnées des photos de traçabilité

Chaque étape contient exactement trois rôles dans un objet `photos`,
`photos_unload` ou `photos_reload` :

| Rôle | Requis | Usage backend |
|---|---|---|
| `plate` | Oui | Reconnaissance et contrôle de la plaque du camion |
| `mica` | Oui | Preuve visuelle rapprochée du mica |
| `truck_with_mica` | Oui | Vue d’ensemble montrant le camion et son chargement |

Chaque objet des trois rôles métier utilise le même schéma :

| Champ | Type | Requis | Description |
|---|---|---|---|
| `key` | string | Oui | Clé identique à l’upload multipart |
| `hash` | string | Oui | SHA-256 en hexadécimal, 64 caractères |
| `lat` | number | Oui | Latitude GPS propre à cette capture |
| `lon` | number | Oui | Longitude GPS propre à cette capture |
| `gps_accuracy` | number | Oui | Précision GPS de la capture, en mètres |
| `captured_at` | string | Oui | Date UTC `YYYY-MM-DD HH:mm:ss` |
| `heading_deg` | number | Non | Cap visé, compris entre 0 et moins de 360 |
| `heading_accuracy` | number | Non | Incertitude du cap en degrés |
| `heading_reference` | string | Non | `magnetic` dans l’application actuelle |

`0°` indique le nord magnétique, `90°` l’est, `180°` le sud et `270°`
l’ouest. Les champs `heading_*` sont absents si l’appareil ne possède pas de
magnétomètre. Leur absence ne doit jamais invalider un submit.

Les coordonnées générales de l’étape (`mine.lat/lon`, `gps_unload`,
`gps_reload`, `arrival.gps`) sont conservées pour les règles métier. Elles ne
remplacent pas les coordonnées de chaque photo, car les trois captures peuvent
être prises à quelques mètres et quelques secondes d’intervalle.

Correspondance entre la photo OCR et la plaque attendue :

| Photo OCR | Champ texte associé |
|---|---|
| `mine.photos.plate` | `mine.plate` |
| `transloads[n].photos_unload.plate` | `transloads[n].plate_before` |
| `transloads[n].photos_reload.plate` | `transloads[n].plate_after` |
| `arrival.photos_unload.plate` | `arrival.plate_arrival` |

Le backend peut recalculer la plaque depuis l’image, mais doit conserver la
valeur envoyée et le résultat OCR séparément afin de permettre un audit des
écarts. Une mauvaise reconnaissance ne doit pas modifier silencieusement le
payload original.

### Nombre de photos obligatoires par lot

Pour `T` transbordements, le nombre minimal de photos de traçabilité est :

```text
3 au chargement mine + (T × 6) aux transbordements + 3 au dépôt
= 6 × T + 6 photos
```

La photo de permis éventuelle s’ajoute à ce total. Exemples :

| Transbordements | Photos métier requises | Avec permis |
|---:|---:|---:|
| 0 | 6 | 7 |
| 1 | 12 | 13 |
| 2 | 18 | 19 |

## 7. Envoyer les photos d’un lot

### `POST /api/attachments`

Une requête multipart est envoyée par photo, après le succès de
`/api/tracking/submit`.

```text
payload_id        : de305d54-75b4-431b-adb2-eb6b9e546014
device_uuid       : 550e8400-e29b-41d4-a716-446655440000
key               : mine_plate
hash              : 9f2c...e7
file              : <binaire JPEG>
```

Clés admises pour un lot en `photo_schema_version=2` :

| Étape | Rôle | `key` |
|---|---|---|
| Chargement mine | Plaque | `mine_plate` |
| Chargement mine | Mica | `mine_mica` |
| Chargement mine | Camion avec mica | `mine_truck_with_mica` |
| Déchargement transbordement N | Plaque | `transload_<n>_unload_plate` |
| Déchargement transbordement N | Mica | `transload_<n>_unload_mica` |
| Déchargement transbordement N | Camion avec mica | `transload_<n>_unload_truck_with_mica` |
| Rechargement transbordement N | Plaque | `transload_<n>_reload_plate` |
| Rechargement transbordement N | Mica | `transload_<n>_reload_mica` |
| Rechargement transbordement N | Camion avec mica | `transload_<n>_reload_truck_with_mica` |
| Déchargement dépôt | Plaque | `depot_unload_plate` |
| Déchargement dépôt | Mica | `depot_unload_mica` |
| Déchargement dépôt | Camion avec mica | `depot_unload_truck_with_mica` |
| Permis du chauffeur | Preuve administrative séparée | `license` |

`<n>` reprend la valeur entière de `transloads[].order`, à partir de 1.

Le serveur doit vérifier avant de considérer les pièces jointes complètes :

1. que chaque clé multipart est déclarée une seule fois dans le JSON ;
2. que le SHA-256 recalculé du fichier correspond au `hash` déclaré ;
3. que les trois rôles sont présents pour chaque étape ;
4. que seules les images `*_plate` alimentent la reconnaissance de plaque ;
5. que le rejeu de `payload_id + key + hash` ne crée aucun doublon.

Les métadonnées GPS, date et orientation ne sont pas répétées dans le
multipart. Le backend les retrouve dans le payload JSON grâce à `key` et doit
refuser un fichier dont la clé ou le hash n’a pas été déclaré au submit.

Réponse HTTP 200 :

```json
{
  "status": "ok",
  "data": {
    "payload_id": "de305d54-75b4-431b-adb2-eb6b9e546014",
    "photo_key": "mine_plate",
    "attachment_id": 812,
    "required_attachments": 13,
    "received_attachments": 1,
    "attachments_complete": false
  }
}
```

Quand `received_attachments == required_attachments`, la réponse renvoie
`attachments_complete: true`. Le comptage porte sur les clés uniques reçues,
pas sur le nombre brut de requêtes, afin qu’un rejeu idempotent n’augmente pas
le compteur.

Exemple d’erreur HTTP 422 si le JSON v2 ne déclare pas les trois rôles :

```json
{
  "status": "error",
  "message": "Trois photos sont requises pour chaque étape",
  "errors": {
    "payload.mine.photos.mica": ["required"],
    "payload.transloads.0.photos_reload.truck_with_mica": ["required"]
  }
}
```

Le fichier local est conservé après confirmation pour rester consultable dans
le détail du lot. L’application mémorise la clé confirmée et ne la renvoie pas.

### Compatibilité avec les payloads photo v1

Des lots créés hors ligne avant la mise à jour peuvent encore contenir les
anciennes clés `mine`, `transload_<n>_unload`,
`transload_<n>_reload` et `arrival`. Pour ne pas perdre ces envois en attente :

- `photo_schema_version` absent ou égal à `1` : accepter l’ancien format ;
- `photo_schema_version=2` : exiger strictement les trois rôles de chaque
  étape et les nouvelles clés ;
- ne jamais mélanger les clés v1 et v2 dans un même payload ;
- conserver le support v1 jusqu’à confirmation qu’aucune file mobile ancienne
  ne reste à synchroniser.

Cette compatibilité concerne uniquement les données déjà capturées. Toute
nouvelle capture effectuée par la version mobile correspondante utilisera v2.

## 8. Proposer une nouvelle mine

### `POST /api/mine`

La proposition reste inutilisable dans un chargement tant qu’Odoo ne l’a pas
validée. Elle comporte un nom, une commune et au moins cinq preuves
photographiques géolocalisées.

```json
{
  "device_uuid": "83a793d5-1a27-47db-b444-538fe6b21d85",
  "agent_login": "eddy",
  "collected_at": "2026-07-30 08:00:00",
  "payload": {
    "id": "23ae4cc8-e017-46ca-8606-d93a39ae5684",
    "name": "Mine Antsahabe",
    "commune_id": 24091,
    "created_at": "2026-07-30 08:00:00",
    "positions": [
      {
        "key": "position_1",
        "hash": "9f2c...e7",
        "lat": -18.91001,
        "lon": 47.52001,
        "gps_accuracy": 4.2,
        "heading_deg": 125.4,
        "heading_accuracy": 3.0,
        "heading_reference": "magnetic",
        "captured_at": "2026-07-30 07:55:00"
      },
      {
        "key": "position_2",
        "hash": "82ad...11",
        "lat": -18.91012,
        "lon": 47.52015,
        "gps_accuracy": 5.1,
        "captured_at": "2026-07-30 07:56:00"
      },
      {
        "key": "position_3",
        "hash": "35bc...a9",
        "lat": -18.91022,
        "lon": 47.52025,
        "gps_accuracy": 3.9,
        "captured_at": "2026-07-30 07:57:00"
      },
      {
        "key": "position_4",
        "hash": "a71e...42",
        "lat": -18.91031,
        "lon": 47.52009,
        "gps_accuracy": 4.7,
        "captured_at": "2026-07-30 07:58:00"
      },
      {
        "key": "position_5",
        "hash": "f06d...8c",
        "lat": -18.91018,
        "lon": 47.51996,
        "gps_accuracy": 4.4,
        "captured_at": "2026-07-30 07:59:00"
      }
    ]
  }
}
```

Validation attendue :

- `device_uuid`, `payload.id`, `name`, `commune_id` et `positions` sont requis.
- `commune_id` référence une commune connue et active.
- Le district est déduit par Odoo et n’est pas envoyé dans le payload.
- `positions` contient au minimum cinq entrées avec des `key` uniques.
- Chaque position contient `key`, `hash`, `lat`, `lon`, `gps_accuracy` et
  `captured_at`.
- Le serveur recalcule le hash et détermine la position/rayon canoniques lors
  de la validation.

Réponse HTTP 201 :

```json
{
  "status": "created",
  "data": {
    "id": 84,
    "payload_id": "23ae4cc8-e017-46ca-8606-d93a39ae5684",
    "state": "draft",
    "required_attachments": 5,
    "received_attachments": 0
  }
}
```

## 9. Envoyer les photos d’une proposition de mine

### `POST /api/attachments`

Le même endpoint est utilisé avec `entity_type=mine`. Une requête est envoyée
par fichier.

```text
entity_type       : mine
payload_id        : 23ae4cc8-e017-46ca-8606-d93a39ae5684
device_uuid       : 83a793d5-1a27-47db-b444-538fe6b21d85
key               : position_1
hash              : 9f2c...e7
file              : <binaire JPEG>
```

Le `payload_id` et le `device_uuid` sont strictement identiques à ceux de
`POST /api/mine`. `key` et `hash` correspondent à une entrée de
`payload.positions`. Après cinq fichiers valides, Odoo peut faire passer la
proposition de `draft` à `waiting_validation`.

```json
{
  "status": "ok",
  "data": {
    "payload_id": "23ae4cc8-e017-46ca-8606-d93a39ae5684",
    "key": "position_1",
    "attachment_id": 813,
    "state": "draft",
    "required_attachments": 5,
    "received_attachments": 1
  }
}
```

## 10. Détecter la validation d’une mine

Aucun endpoint de statut supplémentaire n’est requis. `POST /api/mine`
renvoie `data.id`, que l’application conserve comme `serverId` de la
proposition locale.

À chaque ouverture, retour au premier plan, retour du réseau et
synchronisation périodique, l’application recharge :

1. `GET /api/mine` ;
2. `GET /api/storage` ;
3. `GET /api/commune`.

Les lignes sont mises à jour par leur clé primaire : relancer ces GET ne crée
aucun doublon. Les anciennes références absentes de la nouvelle réponse sont
conservées mais rendues inactives afin de préserver l’historique hors ligne.

`GET /api/mine` ne renvoie que les mines validées. Quand une mine distante
possède le même `id` que le `serverId` d’une proposition mobile, l’application :

- marque la proposition locale comme approuvée ;
- lie `approvedMineId` à cet identifiant ;
- rend la mine sélectionnable dans un nouveau chargement.

Si l’identifiant n’apparaît pas, la proposition reste en attente. Sans champ
supplémentaire dans `GET /api/mine`, l’application ne peut pas distinguer une
proposition rejetée d’une proposition encore en cours de validation.

## 11. Déconnexion

### `POST /api/logout`

```json
{
  "id": 1
}
```

L’identifiant numérique correspond à `data.agent.id` renvoyé par le login.
Dans le client actuel, la déconnexion efface d’abord la session locale ;
l’invalidation distante reste à confirmer avec le backend.

## 12. Erreurs

Le serveur doit toujours retourner un corps exploitable, notamment pour les
HTTP 500 affichés dans le rapport de synchronisation.

```json
{
  "status": "error",
  "message": "Au moins 5 positions sont requises",
  "errors": {
    "payload.positions": ["minimum_5_required"]
  }
}
```

| HTTP | Signification |
|---|---|
| `200` | Succès ou rejeu `already_synced` |
| `201` | Objet créé |
| `400` | Requête ou champ invalide |
| `401` | Token absent, expiré ou identifiants incorrects |
| `403` | Accès interdit |
| `404` | Objet ou `payload_id` inconnu |
| `409` | Même clé photo avec un hash différent |
| `422` | Règle métier non respectée |
| `500` | Erreur interne avec `message` et, si possible, `errors` |

L’application conserve dans son rapport le code HTTP, la route, `message` et
le corps JSON borné. Le backend ne doit donc pas répondre avec une page HTML
ou un corps vide en cas d’erreur métier.

## 13. Points à confirmer avec le backend

1. Confirmer les formes exactes de `/api/mine`, `/api/storage` et
   `/api/commune`.
2. Confirmer que `/api/attachments` accepte `entity_type=mine`.
3. Confirmer l’identifiant attendu par `/api/logout`.
4. Confirmer la durée de vie du token et le comportement attendu après HTTP
   401.
5. Confirmer la conservation de `session_id` et `lot_reference`.
6. Confirmer les champs optionnels `heading_deg`, `heading_accuracy` et
   `heading_reference=magnetic`.
7. Définir le nombre maximal et la durée de conservation des photos d’une
   proposition rejetée.
8. Confirmer `photo_schema_version=2`, les objets `photos`, `photos_unload` et
   `photos_reload`, ainsi que les douze familles de clés décrites au §7.
9. Confirmer que le backend calcule `required_attachments` selon le nombre de
   transbordements et la présence éventuelle de `photo_license`.
10. Confirmer que l’OCR utilise uniquement les clés terminées par `_plate` et
    conserve séparément la plaque déclarée et la plaque reconnue.
11. Confirmer la période de compatibilité pendant laquelle les payloads photo
    v1 déjà stockés hors ligne restent acceptés.
