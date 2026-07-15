# API Contract — Mica App ↔ Odoo `terrain_api` Module

Reference for the Odoo team (Technarea) and the mobile team. Describes the
endpoints called by the Android app, the data sent, and the expected responses.

- **Base URL**: `https://<odoo>/` (set in the app via `MICA_ODOO_URL`)
- **Format**: JSON (except photo upload = `multipart/form-data`)
- **Auth**: `Authorization: Bearer <token>` on every endpoint **except** `/login`
- **Uniform response**: always a `status` field (`ok` / `created` / `error`).
  The app reads `status`, **not only the HTTP code**.
- **Idempotency**: each load carries a **stable `device_uuid`** (UUID v4 generated
  once). The same `device_uuid` sent again must **never create a duplicate**.
- **All JSON keys are in English.**

---

## 1. `POST /api/terrain/login`

Authenticates the agent and returns the token + the reference data (mines, depots).
Called without a token (it provides one).

### Request
```json
{ "login": "F001", "password": "••••••" }
```

### Expected response (200)
```json
{
  "status": "ok",
  "data": {
    "token": "a1b2c3...",
    "agent": { "login": "F001", "name": "Supplier X" },
    "mines": [
      {
        "id": "M001", "name": "Andilana Quarry",
        "lat": -18.91000, "lon": 47.52000, "radius_m": 20,
        "district": "Ambohidratrimo", "commune": "Andilana",
        "region": "Analamanga", "active": true
      }
    ],
    "depots": [
      { "id": "D001", "name": "Antananarivo Depot",
        "lat": -18.87900, "lon": 47.50800, "radius_m": 20, "active": true }
    ]
  }
}
```

### Error (401)
```json
{ "status": "error", "message": "Invalid credentials" }
```

> The app stores the `token` (encrypted, Android Keystore) and **replaces** the
> local mines/depots reference data. Later logins work offline (cached session +
> reference data).

---

## 2. `POST /api/terrain/submit`

Sends **one complete load** (mines + transloads + arrival). One submit per load —
not one per step. **Photos are not in the JSON** (see §3): only their **keys +
hash** appear here.

### Envelope
```json
{
  "device_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "agent_login": "F001",
  "collected_at": "2026-06-22 08:00:00",
  "collect_type": "chargement",
  "gps_lat": -18.91000, "gps_lon": 47.52000, "gps_accuracy": 5.0,
  "payload": { /* see below */ }
}
```

### `payload` (complete load)
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
      "color": "White",
      "estimated_quantity": 120,
      "plate": "1234 TBR",
      "lat": -18.91000, "lon": 47.52000, "gps_accuracy": 5.0,
      "captured_at": "2026-06-22 08:00:00",
      "photo": { "key": "mine_M001", "hash": "9f2c...e7" }
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
    }
  ],

  "arrival": {
    "depot_id": "D001",
    "driver": "Rakoto",
    "license_number": "P-123",
    "lot_number": "White: LOT-1",
    "gps": [-18.87900, 47.50800],
    "gps_status": "valide",
    "plate_arrival": "5678 ABC",
    "plate_consistent": true,
    "lots": { "White": "LOT-1" },
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

### Expected responses
```json
// Created (201)
{ "status": "created", "data": { "id": 42, "state": "draft" } }
// Same device_uuid replayed (200)
{ "status": "ok", "message": "already_synced", "data": { "id": 42 } }
// Validation error (400) / business error (422)
{ "status": "error", "message": "Missing required field: device_uuid" }
```

> The app stores `data.id` as `odoo_id`. Both `created` (201) **and**
> `already_synced` (200) = **success**.

---

## 3. `POST /api/terrain/upload` — all photos in one batch

Sent **after** a successful submit. **All photos of the load in a single**
`multipart/form-data` request. Each photo is identified by its `key` (the same
one declared in the payload).

### Request (multipart/form-data)
```
device_uuid       : 550e8400-e29b-41d4-a716-446655440000
photos[0][key]    : mine_M001
photos[0][hash]   : 9f2c...e7
photos[0][file]   : <JPEG binary>
photos[1][key]    : transload_1_unload
photos[1][file]   : <JPEG binary>
photos[2][key]    : arrival
photos[2][file]   : <JPEG binary>
```

### Expected response (200)
```json
{
  "status": "ok",
  "data": {
    "uploaded": [
      { "photo_key": "mine_M001",          "attachment_id": 812 },
      { "photo_key": "transload_1_unload", "attachment_id": 813 },
      { "photo_key": "arrival",            "attachment_id": 814 }
    ]
  }
}
```

- The server attaches each file to the record (via `device_uuid`) under the field
  matching `photo_key`.
- **Photo idempotency**: if the `hash` is already known for that key, ignore it
  (do not recreate). Allows replaying the batch without duplicates.
- The app deletes the local file after confirmation (the `hash` remains as proof).

### `photo_key` scheme
| Photo | `photo_key` |
|---|---|
| Mine `<id>` | `mine_<mineId>` |
| Transload block `<n>` unload | `transload_<n>_unload` |
| Transload block `<n>` reload | `transload_<n>_reload` |
| Depot arrival | `arrival` |
| Driver license | `license` |

---

## 4. `GET /api/terrain/status/<id>`

Checks the state of a record on the Odoo side (optional, for diagnostics).

### Response
```json
{ "status": "ok", "data": { "id": 42, "state": "done", "device_uuid": "550e..." } }
```
404 if the id does not exist.

---

## 5. HTTP codes

| Code | Case |
|---|---|
| 200 | success / `already_synced` |
| 201 | record created |
| 400 | missing / invalid parameter |
| 401 | missing or invalid token |
| 403 | insufficient rights |
| 404 | record not found |
| 422 | business rule violated |
| 500 | server error |

---

## 6. To confirm with Technarea

1. **`/login`**: exact path and fields? Response contains `token` + `agent` +
   `mines` + `depots`? Token lifetime / refresh?
2. **`/submit`**: sent **once** when the load is complete (no upsert needed).
   Confirm this matches the module.
3. **`/upload`**: does it accept the **batch** (`photos[i][file]`) in one request,
   or one file per request? Correlation by `device_uuid` or `odoo_id`?
4. Do the mines/depots come from **`/login`** (and not `/config`)?
5. Linking transloads/arrival to the load: by `payload.id` (`MICA-…`) or by the
   Odoo record created at submit?

> Note: a few enum-like string **values** are still French inside the payload
> (`status: "valide"`, `gps_status: "valide"`, `collect_type: "chargement"`). Tell
> us if you want those normalized to English too.
