# Contrat API complet — Mica Fleet ↔ Radoran/Odoo

Ce fichier est la référence unique pour l’intégration entre l’application
Flutter Android et l’API Radoran/Odoo. Il couvre l’authentification, les
référentiels, la traçabilité des lots, les pièces jointes et la proposition
manuelle d’une mine.

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
| `GET` | `/api/commune` | Bearer | Charger les communes |
| `POST` | `/api/tracking/submit` | Bearer | Envoyer un lot complet |
| `POST` | `/api/mine` | Bearer | Proposer une nouvelle mine |
| `POST` | `/api/attachments` | Bearer | Envoyer une photo, une requête par fichier |
| `GET` | `/api/mine/submissions/{payload_id}` | Bearer | Lire la validation d’une mine |
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
      "photo": {
        "key": "mine",
        "hash": "9f2c...e7",
        "heading_deg": 15.0,
        "heading_accuracy": 1.5,
        "heading_reference": "magnetic"
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
        "photo_unload": {
          "key": "transload_1_unload",
          "heading_deg": 90.0,
          "heading_accuracy": 2.0,
          "heading_reference": "magnetic"
        },
        "photo_reload": {
          "key": "transload_1_reload",
          "heading_deg": 180.0,
          "heading_accuracy": 3.0,
          "heading_reference": "magnetic"
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
      "photo_arrival": {
        "key": "arrival",
        "heading_deg": 270.0,
        "heading_accuracy": 4.0,
        "heading_reference": "magnetic"
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

Règles métier principales :

- `mine` est un objet unique, jamais une liste.
- Un lot ne peut pas être divisé.
- `estimated_quantity` est figée au départ.
- La chaîne des plaques doit rester cohérente entre départ, transbordements et
  arrivée.
- `mine_id` et `depot_id` sont les identifiants renvoyés par les référentiels.
- `traceability_score` est calculé par lot.
- Les photos binaires ne sont pas intégrées au JSON ; elles sont envoyées
  après le submit.

Réponse de création HTTP 201 :

```json
{
  "status": "created",
  "data": { "id": 42, "state": "draft" }
}
```

Rejeu idempotent HTTP 200 :

```json
{
  "status": "ok",
  "message": "already_synced",
  "data": { "id": 42 }
}
```

L’application conserve `data.id` comme identifiant technique Odoo.

## 6. Orientation des photos

Tous les objets photo utilisent les mêmes métadonnées :

| Champ | Type | Requis | Description |
|---|---|---|---|
| `key` | string | Oui | Clé identique à l’upload multipart |
| `hash` | string | Non | SHA-256 si déjà calculé |
| `heading_deg` | number | Non | Cap visé, compris entre 0 et moins de 360 |
| `heading_accuracy` | number | Non | Incertitude du cap en degrés |
| `heading_reference` | string | Non | `magnetic` dans l’application actuelle |

`0°` indique le nord magnétique, `90°` l’est, `180°` le sud et `270°`
l’ouest. Les champs `heading_*` sont absents si l’appareil ne possède pas de
magnétomètre. Leur absence ne doit jamais invalider un submit.

## 7. Envoyer les photos d’un lot

### `POST /api/attachments`

Une requête multipart est envoyée par photo, après le succès de
`/api/tracking/submit`.

```text
payload_id        : de305d54-75b4-431b-adb2-eb6b9e546014
device_uuid       : 550e8400-e29b-41d4-a716-446655440000
key               : mine
hash              : 9f2c...e7
file              : <binaire JPEG>
```

Clés admises pour un lot :

| Photo | `key` |
|---|---|
| Mine d’origine | `mine` |
| Décharge du transbordement N | `transload_<n>_unload` |
| Recharge du transbordement N | `transload_<n>_reload` |
| Arrivée au dépôt | `arrival` |
| Permis du chauffeur | `license` |

Réponse HTTP 200 :

```json
{
  "status": "ok",
  "data": {
    "payload_id": "de305d54-75b4-431b-adb2-eb6b9e546014",
    "photo_key": "mine",
    "attachment_id": 812
  }
}
```

Le fichier local est conservé après confirmation pour rester consultable dans
le détail du lot. L’application mémorise la clé confirmée et ne la renvoie pas.

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
    "state": "awaiting_attachments",
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
`payload.positions`. Après cinq fichiers valides, la proposition passe de
`awaiting_attachments` à `pending_validation`.

```json
{
  "status": "ok",
  "data": {
    "payload_id": "23ae4cc8-e017-46ca-8606-d93a39ae5684",
    "key": "position_1",
    "attachment_id": 813,
    "state": "awaiting_attachments",
    "required_attachments": 5,
    "received_attachments": 1
  }
}
```

## 10. Lire la validation d’une mine

### `GET /api/mine/submissions/{payload_id}`

En attente :

```json
{
  "status": "ok",
  "data": {
    "payload_id": "23ae4cc8-e017-46ca-8606-d93a39ae5684",
    "state": "pending_validation",
    "required_attachments": 5,
    "received_attachments": 5,
    "rejection_reason": null,
    "mine": null
  }
}
```

Validée :

```json
{
  "status": "ok",
  "data": {
    "payload_id": "23ae4cc8-e017-46ca-8606-d93a39ae5684",
    "state": "approved",
    "required_attachments": 5,
    "received_attachments": 5,
    "rejection_reason": null,
    "mine": {
      "id": 42,
      "name": "Mine Antsahabe",
      "lat": -18.91017,
      "lon": 47.52009,
      "radius_m": 20,
      "district": "Ambohidratrimo",
      "commune": "Andilana",
      "region": "Analamanga",
      "active": true
    }
  }
}
```

Rejetée :

```json
{
  "status": "ok",
  "data": {
    "payload_id": "23ae4cc8-e017-46ca-8606-d93a39ae5684",
    "state": "rejected",
    "required_attachments": 5,
    "received_attachments": 5,
    "rejection_reason": "Les positions sont trop éloignées",
    "mine": null
  }
}
```

| État | Utilisable dans l’application |
|---|---|
| `awaiting_attachments` | Non |
| `pending_validation` | Non |
| `approved` | Oui |
| `rejected` | Non |

Après approbation, `data.mine` est ajouté au référentiel local. La mine doit
également apparaître dans les prochains résultats de `GET /api/mine`.

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
