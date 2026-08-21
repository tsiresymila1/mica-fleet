# Contrat API — Proposition et validation d'une mine

Ce document décrit le flux permettant à un agent terrain de proposer une mine
depuis l'application mobile. Une proposition peut être créée hors ligne et
sélectionnée immédiatement dans un lot local. Ce lot ne sera envoyé qu'après
la création de la mine côté Odoo et l'obtention de son `data.id`. L'upload des
preuves de la mine continue indépendamment et ne bloque pas le lot.

## Principes

- Une proposition contient une commune, un nom et au moins **5 photos prises
  dans l'app**.
- Chaque photo possède sa position GPS, sa précision, son horodatage et son
  hash SHA-256. Son cap magnétique est ajouté lorsque le capteur est disponible.
- Les métadonnées sont envoyées avant les fichiers binaires.
- Les photos sont envoyées **une par une** et peuvent être rejouées sans doublon.
- `payload.id` est un UUID stable propre à la proposition.
- `device_uuid` est un UUID stable d'idempotence, identique pour le submit et
  tous les uploads de cette proposition.
- Une proposition `awaiting_attachments`, `pending_validation` ou `rejected`
  ne doit jamais être renvoyée comme mine active par `GET /api/mine`.
- Un lot local dépendant utilise l'UUID de proposition uniquement comme lien
  local. Son `payload.mine.mine_id` utilise toujours l'id numérique renvoyé
  dans `data.id` par `POST /api/mine`.

---

## 1. `POST /api/mine`

Crée ou rejoue une proposition de mine. L'endpoint exige un Bearer token.

### Requête JSON

```json
{
  "device_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "agent_login": "eddy",
  "collected_at": "2026-07-30 08:00:00",
  "payload": {
    "id": "de305d54-75b4-431b-adb2-eb6b9e546014",
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
        "heading_deg": 125.4,
        "heading_accuracy": 3.0,
        "heading_reference": "magnetic",
        "captured_at": "2026-07-30 07:56:00"
      },
      {
        "key": "position_3",
        "hash": "35bc...a9",
        "lat": -18.91022,
        "lon": 47.52025,
        "gps_accuracy": 3.9,
        "heading_deg": 125.4,
        "heading_accuracy": 3.0,
        "heading_reference": "magnetic",
        "captured_at": "2026-07-30 07:57:00"
      },
      {
        "key": "position_4",
        "hash": "a71e...42",
        "lat": -18.91031,
        "lon": 47.52009,
        "gps_accuracy": 4.7,
        "heading_deg": 125.4,
        "heading_accuracy": 3.0,
        "heading_reference": "magnetic",
        "captured_at": "2026-07-30 07:58:00"
      },
      {
        "key": "position_5",
        "hash": "f06d...8c",
        "lat": -18.91018,
        "lon": 47.51996,
        "gps_accuracy": 4.4,
        "heading_deg": 125.4,
        "heading_accuracy": 3.0,
        "heading_reference": "magnetic",
        "captured_at": "2026-07-30 07:59:00"
      }
    ]
  }
}
```

### Validation serveur

- `device_uuid`, `payload.id`, `name`, `commune_id` et `positions` sont
  obligatoires.
- `device_uuid` et `payload.id` doivent être des UUID valides.
- `commune_id` doit référencer une commune connue et active. Le district est
  déduit de cette commune par Odoo et n'est pas envoyé dans le payload.
- `positions` doit contenir au moins 5 entrées.
- Les `key` doivent être uniques dans le payload.
- Chaque position doit contenir `key`, `hash`, `lat`, `lon`, `gps_accuracy` et
  `captured_at`. Quand l'appareil possède une boussole, elle contient aussi
  `heading_deg`, `heading_accuracy` et `heading_reference=magnetic`.
- Le serveur ne fait pas confiance à une coordonnée centrale calculée par le
  mobile. La position canonique et le rayon de la mine sont définis lors de la
  validation Odoo à partir des preuves reçues.

### Réponse de création — HTTP 201

```json
{
  "status": "created",
  "data": {
    "id": 84,
    "payload_id": "de305d54-75b4-431b-adb2-eb6b9e546014",
    "state": "awaiting_attachments",
    "required_attachments": 5,
    "received_attachments": 0
  }
}
```

### Rejeu idempotent — HTTP 200

```json
{
  "status": "ok",
  "message": "already_synced",
  "data": {
    "id": 84,
    "payload_id": "de305d54-75b4-431b-adb2-eb6b9e546014",
    "state": "awaiting_attachments",
    "required_attachments": 5,
    "received_attachments": 2
  }
}
```

Le serveur déduplique sur `device_uuid`. Un même `device_uuid` ne doit jamais
créer deux propositions.

---

## 2. `POST /api/attachments` — une photo par requête

Option recommandée : généraliser l'endpoint existant en ajoutant
`entity_type=mine`. L'appel exige le même Bearer token que le submit.

### Requête `multipart/form-data`

```text
entity_type       : mine
payload_id        : de305d54-75b4-431b-adb2-eb6b9e546014
device_uuid       : 550e8400-e29b-41d4-a716-446655440000
key               : position_1
hash              : 9f2c...e7
file              : <binaire JPEG>
```

Règles serveur :

- `payload_id` doit correspondre à `payload.id` du submit.
- `device_uuid` doit être identique à celui du submit.
- `key` et `hash` doivent correspondre à une entrée de `payload.positions`.
- Le serveur recalcule le SHA-256 du fichier et refuse un hash différent.
- Le triplet `payload_id + key + hash` est idempotent.
- Après réception d'au moins 5 fichiers valides déclarés dans le payload, la
  proposition passe automatiquement de `awaiting_attachments` à
  `pending_validation`.

### Réponse — HTTP 200

```json
{
  "status": "ok",
  "data": {
    "payload_id": "de305d54-75b4-431b-adb2-eb6b9e546014",
    "key": "position_1",
    "attachment_id": 812,
    "state": "awaiting_attachments",
    "required_attachments": 5,
    "received_attachments": 1
  }
}
```

Si `/api/attachments` ne peut pas cibler plusieurs modèles Odoo, utiliser
`POST /api/mine/attachments` avec exactement les mêmes champs, sans
`entity_type`.

---

## 3. `GET /api/mine/submissions/{payload_id}`

Permet au mobile de connaître le résultat de la validation. L'endpoint exige
un Bearer token et ne retourne que les propositions accessibles à l'agent.

### En attente — HTTP 200

```json
{
  "status": "ok",
  "data": {
    "payload_id": "de305d54-75b4-431b-adb2-eb6b9e546014",
    "state": "pending_validation",
    "required_attachments": 5,
    "received_attachments": 5,
    "rejection_reason": null,
    "mine": null
  }
}
```

### Validée — HTTP 200

```json
{
  "status": "ok",
  "data": {
    "payload_id": "de305d54-75b4-431b-adb2-eb6b9e546014",
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
      "district": null,
      "commune": null,
      "region": null,
      "active": true
    }
  }
}
```

### Rejetée — HTTP 200

```json
{
  "status": "ok",
  "data": {
    "payload_id": "de305d54-75b4-431b-adb2-eb6b9e546014",
    "state": "rejected",
    "required_attachments": 5,
    "received_attachments": 5,
    "rejection_reason": "Les positions sont trop éloignées les unes des autres",
    "mine": null
  }
}
```

Valeurs possibles de `state` :

| État | Signification | Utilisable dans l'app |
|---|---|---|
| `awaiting_attachments` | Submit reçu, photos incomplètes | Non |
| `pending_validation` | Photos reçues, validation Odoo requise | Non |
| `approved` | Mine validée et créée dans le référentiel | Oui |
| `rejected` | Proposition refusée avec motif | Non |

Après `approved`, le mobile insère ou met à jour `data.mine` dans son
référentiel local. `GET /api/mine` doit également renvoyer cette mine comme
toute autre mine validée.

---

## 4. Erreurs attendues

```json
{
  "status": "error",
  "message": "Au moins 5 positions sont requises",
  "errors": {
    "payload.positions": ["minimum_5_required"]
  }
}
```

| HTTP | Cas |
|---|---|
| 400 | JSON ou multipart invalide |
| 401 | Bearer token absent ou invalide |
| 403 | Proposition appartenant à un autre agent |
| 404 | `payload_id` inconnu |
| 409 | Clé déjà reçue avec un hash différent |
| 422 | Règle métier non respectée |
| 500 | Erreur interne Odoo |

Le corps d'erreur doit toujours contenir `status=error` et un `message`
exploitable dans le rapport de synchronisation mobile.

---

## 5. Points à confirmer avec le backend

1. Peut-on généraliser `POST /api/attachments` avec `entity_type=mine` ?
2. L'administrateur qui valide la proposition peut-il définir/corriger le
   centre GPS, le rayon, le district, la commune et la région ?
3. Faut-il limiter le nombre maximal de photos ? Le mobile prévoit un minimum
   de 5 ; une limite de 10 est recommandée pour maîtriser le stockage.
4. Une proposition rejetée peut-elle être corrigée et renvoyée avec le même
   `payload.id`, ou faut-il créer un nouveau payload ?
5. Quelle durée de conservation appliquer aux photos des propositions rejetées ?
