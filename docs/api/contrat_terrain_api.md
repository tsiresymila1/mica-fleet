# Contrat API — Application Mica ↔ Module Odoo `terrain_api`

Document de référence pour l'équipe Odoo (Technarea) et l'équipe mobile.
Décrit les endpoints appelés par l'app Android, les données envoyées et les
réponses attendues.

- **Base URL** : `https://<odoo>/` (configurée côté app via `MICA_ODOO_URL`)
- **Format** : JSON (sauf upload photos = `multipart/form-data`)
- **Auth** : `Authorization: Bearer <token>` sur tous les endpoints **sauf** `/login`
- **Réponse uniforme** : toujours un champ `status` (`ok` / `created` / `error`).
  L'app lit `status`, **pas uniquement le code HTTP**.
- **Idempotence** : chaque chargement porte un `device_uuid` **stable** (UUID v4
  généré une fois). Un même `device_uuid` renvoyé plusieurs fois ne doit **jamais
  créer de doublon** (upsert).

---

## 1. `POST /api/terrain/login`

Authentifie l'agent et renvoie le token + le référentiel (mines, dépôts).
Appelé sans token (c'est lui qui le fournit).

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
    "agent": { "login": "F001", "nom": "Fournisseur X" },
    "mines": [
      {
        "id": "M001", "nom": "Carrière Andilana",
        "lat": -18.91000, "lon": 47.52000, "rayon_metres": 20,
        "district": "Ambohidratrimo", "commune": "Andilana",
        "region": "Analamanga", "actif": true
      }
    ],
    "depots": [
      { "id": "D001", "nom": "Dépôt Antananarivo",
        "lat": -18.87900, "lon": 47.50800, "rayon_metres": 20, "actif": true }
    ]
  }
}
```

### Erreur (401)
```json
{ "status": "error", "message": "Identifiant ou mot de passe incorrect" }
```

> L'app stocke le `token` (chiffré, Android Keystore) et **remplace** le
> référentiel mines/dépôts local. Connexions suivantes possibles hors ligne
> (session + référentiel en cache).

---

## 2. `POST /api/terrain/submit`

Envoie **un chargement complet** (mines + transbordements + arrivée). Un seul
submit par chargement — pas un par étape. Les **photos ne sont pas dans le JSON**
(voir §3), seules leurs **clés + hash** y figurent.

### Enveloppe
```json
{
  "device_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "agent_login": "F001",
  "collected_at": "2026-06-22 08:00:00",
  "collecte_type": "chargement",
  "gps_lat": -18.91000, "gps_lon": 47.52000, "gps_accuracy": 5.0,
  "payload": { /* voir ci-dessous */ }
}
```

### `payload` (chargement complet)
```json
{
  "id": "MICA-2026-0007",
  "fournisseur_id": "F001",
  "statut": "valide",
  "date_creation": "2026-06-22 08:00:00",

  "mines": [
    {
      "mine_id": "M001",
      "reference": "REF-1",
      "couleur": "Blanc",
      "quantite_estimee": 120,
      "plaque": "1234 TBR",
      "lat": -18.91000, "lon": 47.52000, "gps_accuracy": 5.0,
      "date_heure": "2026-06-22 08:00:00",
      "photo": { "key": "mine_M001", "hash": "9f2c...e7" }
    }
  ],

  "transbordements": [
    {
      "ordre": 1,
      "plaque_avant": "1234 TBR", "plaque_apres": "5678 ABC",
      "gps_decharge": [-18.92000, 47.53000],
      "gps_recharge": [-18.92010, 47.53000],
      "distance_m": 11.4, "conforme": true,
      "photo_decharge": { "key": "transb_1_decharge", "hash": "a1..." },
      "photo_recharge": { "key": "transb_1_recharge", "hash": "b2..." }
    }
  ],

  "arrivee": {
    "depot_id": "D001",
    "chauffeur": "Rakoto",
    "num_permis": "P-123",
    "num_lot": "Blanc: LOT-1",
    "gps": [-18.87900, 47.50800],
    "statut_gps": "valide",
    "plaque_arrivee": "5678 ABC",
    "plaque_coherente": true,
    "lots": { "Blanc": "LOT-1" },
    "photo_arrivee": { "key": "arrivee", "hash": "c3..." },
    "photo_permis":  { "key": "permis",  "hash": "d4..." }
  },

  "trajet": [
    [-18.91000, 47.52000, "2026-06-22 08:00:00"],
    [-18.92000, 47.53000, "2026-06-22 08:20:00"],
    [-18.87900, 47.50800, "2026-06-22 10:30:00"]
  ],

  "score_tracabilite": 100
}
```

### Réponses attendues
```json
// Création (201)
{ "status": "created", "data": { "id": 42, "state": "draft" } }
// Rejeu même device_uuid (200) — mise à jour du record existant (upsert)
{ "status": "ok", "message": "already_synced", "data": { "id": 42 } }
// Erreur validation (400) / métier (422)
{ "status": "error", "message": "Champ requis manquant : device_uuid" }
```

> L'app enregistre `data.id` comme `odoo_id`. `created` (201) **et**
> `already_synced` (200) = **succès**.

---

## 3. `POST /api/terrain/upload` — photos en un seul batch

Envoyé **après** un submit réussi. **Toutes les photos du chargement en une
seule requête** `multipart/form-data`. Chaque photo est identifiée par sa
`photo_key` (celle déclarée dans le payload).

### Requête (multipart/form-data)
```
device_uuid       : 550e8400-e29b-41d4-a716-446655440000
photos[0][key]    : mine_M001
photos[0][hash]   : 9f2c...e7
photos[0][file]   : <binaire JPEG>
photos[1][key]    : transb_1_decharge
photos[1][hash]   : a1...
photos[1][file]   : <binaire JPEG>
photos[2][key]    : arrivee
photos[2][hash]   : c3...
photos[2][file]   : <binaire JPEG>
```

### Réponse attendue (200)
```json
{
  "status": "ok",
  "data": {
    "uploaded": [
      { "photo_key": "mine_M001",        "attachment_id": 812 },
      { "photo_key": "transb_1_decharge","attachment_id": 813 },
      { "photo_key": "arrivee",          "attachment_id": 814 }
    ]
  }
}
```

- Le serveur rattache chaque fichier au record (via `device_uuid`) sous le champ
  correspondant à `photo_key`.
- **Idempotence photo** : si le `hash` est déjà connu pour cette clé, ignorer
  (ne pas recréer). Permet de rejouer le batch sans doublon.
- L'app purge le fichier local après confirmation (le `hash` reste comme preuve).

### Schéma des `photo_key`
| Photo | `photo_key` |
|---|---|
| Mine `<id>` | `mine_<mineId>` |
| Transbordement bloc `<n>` décharge | `transb_<n>_decharge` |
| Transbordement bloc `<n>` recharge | `transb_<n>_recharge` |
| Arrivée dépôt | `arrivee` |
| Photo du permis | `permis` |

---

## 4. `GET /api/terrain/status/<id>`

Vérifie l'état d'une collecte côté Odoo (optionnel, pour diagnostic).

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

## 6. Points à confirmer par Technarea

1. **`/login`** : chemin et champs exacts ? La réponse contient bien
   `token` + `agent` + `mines` + `depots` ? Durée de vie / refresh du token ?
2. **`/submit`** en mode **upsert** (update si `device_uuid` déjà connu) — accepté ?
   Ou faut-il un endpoint `PUT` séparé pour les mises à jour ?
3. **`/upload`** : accepte-t-il le **batch** (`photos[i][file]`) en une requête,
   ou un fichier par requête ? Corrélation par `device_uuid` ou `odoo_id` ?
4. Le référentiel **mines/dépôts** vient-il bien de `/login` (et non `/config`) ?
5. Rattachement transbordement/arrivée au chargement : par `payload.id`
   (`MICA-…`) ou par le record Odoo créé au submit ?
