# Contrat API — Application Mica ↔ API Radoran (Odoo)

Document de référence pour l'équipe Odoo (Technarea) et l'équipe mobile. Décrit
les endpoints appelés par l'app Android, les données envoyées et les réponses
attendues. Aligné sur la collection Postman **RADORAN API**.

- **Base URL** : `https://<odoo>/` (configurée dans l'app via `MICA_ODOO_URL`)
- **Format** : JSON (sauf upload photos = `multipart/form-data`)
- **Auth** : `Authorization: Bearer <token>` sur tous les endpoints **sauf** `/login`
- **Réponse uniforme** : toujours un champ `status` (`ok` / `created` / `error`).
  L'app lit `status`, **pas uniquement le code HTTP**.
- **Idempotence** : chaque chargement porte un **`device_uuid` stable** (UUID v4
  généré une fois). Un même `device_uuid` renvoyé plusieurs fois ne doit **jamais
  créer de doublon**.
- **Toutes les clés JSON sont en anglais.**

---

## 1. `POST /api/login`

Authentifie l'agent et renvoie le token. Appelé sans token (c'est lui qui le
fournit).

### Requête
```json
{ "login": "eddy", "password": "••••••" }
```

### Réponse attendue (200)
```json
{
  "status": "ok",
  "data": {
    "token": "72cad47ff9ba4a6dacf61dc3631abddd",
    "agent": { "id": 1, "login": "eddy", "name": "Fournisseur X" }
  }
}
```

### Erreur (401)
```json
{ "status": "error", "message": "Identifiant ou mot de passe incorrect" }
```

> L'app stocke le `token` (chiffré, Android Keystore) puis appelle
> immédiatement `/api/mine` et `/api/storage` pour **remplacer** le référentiel
> local. Les connexions suivantes fonctionnent hors ligne (session +
> référentiel en cache).

---

## 1bis. `GET /api/mine` et `GET /api/storage`

Référentiel de l'agent connecté (`Authorization: Bearer <token>`), rechargé à
chaque login et à chaque synchronisation.

### Réponse attendue (200)
```json
{
  "status": "ok",
  "data": [
    {
      "id": 1, "name": "Carrière Andilana",
      "lat": -18.91000, "lon": 47.52000, "radius_m": 20,
      "district": "Ambohidratrimo", "commune": "Andilana",
      "region": "Analamanga", "active": true
    }
  ]
}
```

`/api/storage` renvoie la même forme pour les dépôts (`id`, `name`, `lat`,
`lon`, `radius_m`, `active`).

- **`radius_m`** est indispensable : l'app refuse une photo prise hors du rayon
  de la mine ou du dépôt. Sans lui, elle applique 20 m par défaut.
- **`active: false`** masque l'entrée sans casser les chargements passés.

---

## 2. `POST /api/tracking/submit`

Envoie **UN LOT complet**. Un lot = le **chargement d'UNE mine**, indivisible :
c'est l'**unité de traçabilité, de numéro de lot et de score**.

> **1 payload = 1 lot.** Si un camion part avec 3 mines, l'app envoie **3 submits**
> (3 lots), chacun avec son `device_uuid`, son numéro de lot et son score. Les
> lots partis ensemble partagent le même `session_id` (et éventuellement le même
> `lot_reference`).

Les **photos ne sont pas dans le JSON** (voir §3) : seules leurs **clés + hash**
y figurent.

### Enveloppe
```json
{
  "device_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "agent_login": "eddy",
  "collected_at": "2026-06-22 08:00:00",
  "collect_type": "chargement",
  "gps_lat": -18.91000, "gps_lon": 47.52000, "gps_accuracy": 5.0,
  "payload": { /* voir ci-dessous */ }
}
```

### `payload` (UN lot complet)
```json
{
  "id": "MICA-2026-0007-L1",
  "session_id": "MICA-2026-0007",
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
    "lat": -18.91000, "lon": 47.52000, "gps_accuracy": 5.0,
    "captured_at": "2026-06-22 08:00:00",
    "photo": { "key": "mine", "hash": "9f2c...e7" }
  },

  "transloads": [
    {
      "order": 1,
      "plate_before": "1234 TBR", "plate_after": "5678 ABC",
      "gps_unload": [-18.92000, 47.53000],
      "gps_reload": [-18.92010, 47.53000],
      "distance_m": 11.4, "compliant": true,
      "photo_unload": { "key": "transload_1_unload" },
      "photo_reload": { "key": "transload_1_reload" }
    },
    {
      "order": 2,
      "plate_before": "5678 ABC", "plate_after": "9012 DEF",
      "gps_unload": [-18.95000, 47.55000],
      "gps_reload": [-18.95012, 47.55000],
      "distance_m": 13.1, "compliant": true,
      "photo_unload": { "key": "transload_2_unload" },
      "photo_reload": { "key": "transload_2_reload" }
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
    "plate_arrival": "9012 DEF",
    "plate_consistent": true,
    "traceability_score": 100,
    "photo_arrival": { "key": "arrival" },
    "photo_license": { "key": "license" }
  },

  "track": [
    [-18.91000, 47.52000, "2026-06-22 08:00:00"],
    [-18.92000, 47.53000, "2026-06-22 08:20:00"],
    [-18.87900, 47.50800, "2026-06-22 10:30:00"]
  ],

  "traceability_score": 100
}
```

> **Règles métier reflétées par ce format**
> - **`mine` est un objet, pas une liste** : un lot vient d'**UNE seule mine**.
>   Un camion chargé à 3 mines produit **3 lots** → **3 submits**.
> - Un lot n'est **jamais divisé** : `estimated_quantity` est **figée au départ**.
> - `transloads` = les camions successifs ayant porté **CE lot**. Lors d'un même
>   transbordement physique, d'autres lots peuvent partir sur un **autre camion** —
>   chaque lot a donc **sa propre chaîne**.
> - Chaîne des plaques : `mine.plate` = camion de départ ; `transloads[0]` = A→B ;
>   `transloads[1]` = B→C ; `arrival.plate_arrival` = dernier camion. Cohérence :
>   `plate_after[i] == plate_before[i+1]`.
> - **`lot_number`** (à l'arrivée) = numéro de lot officiel. **1 lot = 1 lot_number**.
>   `lots` reprend le même numéro indexé par couleur de mica (un seul couple,
>   puisqu'un lot n'a qu'une couleur).
> - **`traceability_score`** est calculé **par lot**. Il est répété dans
>   `arrival` et à la racine du payload (même valeur).
> - **`mine_id`** et **`depot_id`** sont les **ids Odoo numériques** renvoyés
>   par `/api/mine` et `/api/storage`.
> - **`session_id`** = les lots partis ensemble (regroupement terrain).
> - **`lot_reference`** (optionnel, `null` possible) = regroupement **commercial**
>   côté Odoo (plusieurs lots/camions d'une même opération).

### Réponses attendues
```json
// Création (201)
{ "status": "created", "data": { "id": 42, "state": "draft" } }
// Rejeu même device_uuid (200)
{ "status": "ok", "message": "already_synced", "data": { "id": 42 } }
// Erreur validation (400) / métier (422)
{ "status": "error", "message": "Champ requis manquant : device_uuid" }
```

> L'app enregistre `data.id` comme `odoo_id`. `created` (201) **et**
> `already_synced` (200) = **succès**.

---

## 3. `POST /api/tracking/upload` — toutes les photos en un batch

> ⚠️ **Endpoint non encore présent dans la collection Postman.** Forme proposée
> par l'équipe mobile, déjà implémentée côté app — **à confirmer par Technarea**.

Envoyé **après** un submit réussi. **Toutes les photos DU LOT en une seule
requête** `multipart/form-data`. Chaque photo est identifiée par sa `key` (celle
déclarée dans le payload).

Le lot est identifié par **DEUX champs** :
- **`load_id`** = l'id du **lot** (`MICA-…-L1`, = `payload.id`) → savoir **à
  quel payload** ces fichiers appartiennent.
- **`device_uuid`** = clé d'idempotence stable (celle du même lot).

**Un seul upload = un lot complet.** (3 lots → 3 submits + 3 uploads.)

### Requête (multipart/form-data)
```
load_id           : MICA-2026-0007-L1
device_uuid       : 550e8400-e29b-41d4-a716-446655440000
photos[0][key]    : mine
photos[0][hash]   : 9f2c...e7
photos[0][file]   : <binaire JPEG>
photos[1][key]    : transload_1_unload
photos[1][file]   : <binaire JPEG>
photos[2][key]    : arrival
photos[2][file]   : <binaire JPEG>
```

### Réponse attendue (200)
```json
{
  "status": "ok",
  "data": {
    "load_id": "MICA-2026-0007-L1",
    "uploaded": [
      { "photo_key": "mine",               "attachment_id": 812 },
      { "photo_key": "transload_1_unload", "attachment_id": 813 },
      { "photo_key": "arrival",            "attachment_id": 814 }
    ]
  }
}
```

- Le serveur rattache chaque fichier au **lot** (via `load_id` / `device_uuid`)
  sous le champ correspondant à `photo_key`.
- **Idempotence photo** : si le `hash` est déjà connu pour cette clé, ignorer
  (ne pas recréer). Permet de rejouer le batch sans doublon.
- L'app supprime le fichier local après confirmation (le `hash` reste comme preuve).

### Schéma des `photo_key`
Les clés sont **scopées au lot** (1 upload = 1 lot), donc simples :

| Photo | `photo_key` |
|---|---|
| Mine d'origine du lot | `mine` |
| Transbordement bloc `<n>` décharge | `transload_<n>_unload` |
| Transbordement bloc `<n>` recharge | `transload_<n>_reload` |
| Arrivée dépôt | `arrival` |
| Permis chauffeur | `license` |

---

## 4. `POST /api/logout`

Invalide le token courant. L'app l'appelle à la déconnexion explicite.

```json
{ "id": 1 }
```

> ⚠️ La collection Postman envoie un `id` numérique. **`/api/login` doit donc
> renvoyer cet id** (`data.agent.id`) — sinon l'app ne peut pas construire la
> requête. À confirmer.

---

## 5. Codes HTTP

| Code | Cas |
|---|---|
| 200 | succès / `already_synced` |
| 201 | record créé |
| 400 | paramètre manquant / invalide |
| 401 | token absent ou invalide |
| 403 | droits insuffisants |
| 404 | record inexistant |
| 422 | règle métier violée |
| 500 | erreur serveur |

---

## 6. À confirmer par Technarea

1. **`/api/tracking/upload`** — **bloquant** : absent de la collection Postman.
   Accepte-t-il le batch `photos[i][key|hash|file]` en une requête, rattaché par
   `load_id` + `device_uuid` ? Sans lui, **aucune photo ne remonte**.
2. **`/api/mine` et `/api/storage`** : forme exacte de la réponse ? L'app attend
   `data: [...]` avec `id`, `name`, `lat`, `lon`, `radius_m`, `active`.
   **`radius_m` est indispensable** (contrôle GPS anti-fraude).
3. **`/api/logout`** : l'`id` numérique attendu doit être renvoyé par `/api/login`
   (`data.agent.id`). Confirmé ?
4. **`collect_type`** : l'app envoie `"chargement"` comme dans votre exemple,
   alors qu'un payload = **un lot**. Faut-il une valeur distincte ?
5. **`photo.key` de la mine** : l'app envoie `"mine"` (clé unique dans le lot).
   Votre exemple montre `"mine_M001"`. La clé n'ayant de sens qu'entre submit et
   upload, on garde `"mine"` sauf objection.
6. **Durée de vie du token** et comportement au 401 (refresh ou re-login ?).
7. **`session_id`** et **`lot_reference`** : champs ajoutés par l'app pour
   regrouper les lots partis ensemble. Les stockez-vous ?

> Note : quelques **valeurs** enum restent en français dans le payload
> (`status: "valide"`, `gps_status: "valide"`, `collect_type: "chargement"`).
> Dites-nous si vous voulez les normaliser en anglais aussi.
