# Contrat API — Application Mica ↔ Module Odoo `terrain_api`

Document de référence pour l'équipe Odoo (Technarea) et l'équipe mobile. Décrit
les endpoints appelés par l'app Android, les données envoyées et les réponses
attendues.

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

## 1. `POST /api/geospatial/login`

Authentifie l'agent et renvoie le token + le référentiel (mines, dépôts). Appelé
sans token (c'est lui qui le fournit).

### Requête
```json
{ "login": "F001", "password": "••••••" }
```

### Réponse attendue (200)
```json
{
  "status": "ok",
  "data": {
    "token": "a1b2c3...",
    "agent": { "login": "F001", "name": "Fournisseur X" },
    "mines": [
      {
        "id": "M001", "name": "Carrière Andilana",
        "lat": -18.91000, "lon": 47.52000, "radius_m": 20,
        "district": "Ambohidratrimo", "commune": "Andilana",
        "region": "Analamanga", "active": true
      }
    ],
    "depots": [
      { "id": "D001", "name": "Dépôt Antananarivo",
        "lat": -18.87900, "lon": 47.50800, "radius_m": 20, "active": true }
    ]
  }
}
```

### Erreur (401)
```json
{ "status": "error", "message": "Identifiant ou mot de passe incorrect" }
```

> L'app stocke le `token` (chiffré, Android Keystore) et **remplace** le
> référentiel mines/dépôts local. Les connexions suivantes fonctionnent hors
> ligne (session + référentiel en cache).

---

## 2. `POST /api/geospatial/submit`

Envoie **un chargement complet** (mines + transbordements + arrivée). Un seul
submit par chargement — pas un par étape. Les **photos ne sont pas dans le JSON**
(voir §3) : seules leurs **clés + hash** y figurent.

### Enveloppe
```json
{
  "device_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "agent_login": "F001",
  "collected_at": "2026-06-22 08:00:00",
  "collect_type": "chargement",
  "gps_lat": -18.91000, "gps_lon": 47.52000, "gps_accuracy": 5.0,
  "payload": { /* voir ci-dessous */ }
}
```

### `payload` (chargement complet)
```json
{
  "id": "MICA-2026-0007",
  "supplier_id": "F001",
  "status": "valide",
  "created_at": "2026-06-22 08:00:00",

  "mines": [
    {
      "mine_id": "M001",
      "reference": "REF-1",
      "color": "Blanc",
      "estimated_quantity": 120,
      "plate": "1234 TBR",
      "lat": -18.91000, "lon": 47.52000, "gps_accuracy": 5.0,
      "captured_at": "2026-06-22 08:00:00",
      "photo": { "key": "mine_M001", "hash": "9f2c...e7" }
    },
    {
      "mine_id": "M002",
      "reference": "REF-2",
      "color": "Doré",
      "estimated_quantity": 80,
      "plate": "1234 TBR",
      "lat": -18.92500, "lon": 47.53500, "gps_accuracy": 6.0,
      "captured_at": "2026-06-22 08:15:00",
      "photo": { "key": "mine_M002", "hash": "3b71...aa" }
    }
  ],

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
    "depot_id": "D001",
    "driver": "Rakoto",
    "license_number": "P-123",
    "lot_number": "Blanc: LOT-1",
    "gps": [-18.87900, 47.50800],
    "gps_status": "valide",
    "plate_arrival": "9012 DEF",
    "plate_consistent": true,
    "lots": { "Blanc": "LOT-1" },
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

> **`mines` et `transloads` sont indépendants.**
> - `mines` = les sources (1 à 3 carrières) chargées sur le **camion de départ**.
>   Plusieurs mines = plusieurs carrières sur le **même camion** (même `plate`).
> - `transloads` = les **changements de camion** pendant le trajet (A→B→C). Ils
>   concernent **toute la cargaison** (toutes les mines ensemble), pas une mine
>   en particulier. Il n'y a **pas de mapping 1:1** mine ↔ transbordement.
>
> Chaîne des plaques : `mines[].plate` = camion A ; `transloads[0]` = A→B ;
> `transloads[1]` = B→C ; `arrival.plate_arrival` = dernier camion. La cohérence
> se vérifie sur cette chaîne (`plate_after[i] == plate_before[i+1]`).

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

## 3. `POST /api/geospatial/upload` — toutes les photos en un batch

Envoyé **après** un submit réussi. **Toutes les photos du chargement en une seule
requête** `multipart/form-data`. Chaque photo est identifiée par sa `key` (celle
déclarée dans le payload).

Le chargement est identifié par **DEUX champs** :
- **`load_id`** = l'id du chargement (`MICA-…`, = `payload.id`) → savoir **à quel
  payload** ces fichiers appartiennent.
- **`device_uuid`** = clé d'idempotence stable.

**Un seul upload = un chargement complet.**

### Requête (multipart/form-data)
```
load_id           : MICA-2026-0007
device_uuid       : 550e8400-e29b-41d4-a716-446655440000
photos[0][key]    : mine_M001
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
    "load_id": "MICA-2026-0007",
    "uploaded": [
      { "photo_key": "mine_M001",          "attachment_id": 812 },
      { "photo_key": "transload_1_unload", "attachment_id": 813 },
      { "photo_key": "arrival",            "attachment_id": 814 }
    ]
  }
}
```

- Le serveur rattache chaque fichier au chargement (via `load_id` / `device_uuid`)
  sous le champ correspondant à `photo_key`.
- **Idempotence photo** : si le `hash` est déjà connu pour cette clé, ignorer
  (ne pas recréer). Permet de rejouer le batch sans doublon.
- L'app supprime le fichier local après confirmation (le `hash` reste comme preuve).

### Schéma des `photo_key`
| Photo | `photo_key` |
|---|---|
| Mine `<id>` | `mine_<mineId>` |
| Transbordement bloc `<n>` décharge | `transload_<n>_unload` |
| Transbordement bloc `<n>` recharge | `transload_<n>_reload` |
| Arrivée dépôt | `arrival` |
| Permis chauffeur | `license` |

---

## 4. `GET /api/geospatial/status/<id>`

Vérifie l'état d'un record côté Odoo (optionnel, pour diagnostic).

### Réponse
```json
{ "status": "ok", "data": { "id": 42, "state": "done", "device_uuid": "550e..." } }
```
404 si l'id n'existe pas.

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

1. **`/login`** : chemin et champs exacts ? La réponse contient bien
   `token` + `agent` + `mines` + `depots` ? Durée de vie / refresh du token ?
2. **`/submit`** : envoyé **une seule fois** quand le chargement est complet
   (pas d'upsert requis). Confirmer que ça correspond au module.
3. **`/upload`** : accepte-t-il le **batch** (`photos[i][file]`) en une requête ?
   Rattachement par `load_id` (`MICA-…`) **et/ou** `device_uuid` — le quel faites-vous foi ?
4. Le référentiel **mines/dépôts** vient-il bien de `/login` (et non `/config`) ?
5. Rattachement transbordements/arrivée au chargement : par `payload.id`
   (`MICA-…`) ou par le record Odoo créé au submit ?

> Note : quelques **valeurs** enum restent en français dans le payload
> (`status: "valide"`, `gps_status: "valide"`, `collect_type: "chargement"`).
> Dites-nous si vous voulez les normaliser en anglais aussi.
