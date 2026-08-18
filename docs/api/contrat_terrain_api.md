# Contrat API — Application Mica ↔ API Radoran (Odoo)

> **Document historique (schéma photo v1).** Pour toute nouvelle intégration,
> utiliser la référence consolidée [`README.md`](README.md), notamment les
> sections 5 à 7 qui définissent `photo_schema_version=2` et les trois photos
> obligatoires par étape. Le présent fichier reste conservé uniquement pour la
> lecture des payloads mobiles déjà créés hors ligne avant cette évolution.

Ancienne version du contrat pour l'équipe Odoo (Technarea) et l'équipe mobile,
alignée sur la collection Postman **RADORAN API** d’origine.

La proposition manuelle d'une nouvelle mine et son workflow de validation sont
décrits dans [`contrat_creation_mine.md`](contrat_creation_mine.md).

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
> immédiatement `/api/mine`, `/api/storage` et `/api/commune` pour mettre à
> jour les référentiels locaux. Les connexions suivantes fonctionnent hors
> ligne (session + référentiels en cache).

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

### `GET /api/commune`

Le même Bearer token permet de charger les communes proposées lors de l'ajout
manuel d'une mine. L'app met cette réponse en cache après le login afin que le
champ de recherche reste disponible hors ligne.

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

Champs requis : `id` entier et `name`. `district` est uniquement affiché pour
aider l'agent ; `active: false` masque la commune. La création d'une mine
envoie ensuite uniquement cet identifiant sous la clé `payload.commune_id`.

---

## 2. `POST /api/tracking/submit`

Envoie **UN LOT complet**. Un lot = le **chargement d'UNE mine**, indivisible :
c'est l'**unité de traçabilité, de numéro de lot et de score**.

> **1 payload = 1 lot.** Si un camion part avec 3 mines, l'app envoie **3 submits**
> (3 lots), chacun avec son `device_uuid`, son numéro de lot et son score. Les
> lots partis ensemble partagent le même `session_id` (et éventuellement le même
> `lot_reference`).

Les **photos binaires ne sont pas dans le JSON** (voir §3). Chaque objet
photo y déclare sa clé, son hash lorsqu'il est déjà disponible et son cap
magnétique lorsqu'il a pu être mesuré.

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
    "lat": -18.91000, "lon": 47.52000, "gps_accuracy": 5.0,
    "captured_at": "2026-06-22 08:00:00",
    "photo": {
      "key": "mine", "hash": "9f2c...e7",
      "heading_deg": 15.0,
      "heading_accuracy": 1.5,
      "heading_reference": "magnetic"
    }
  },

  "transloads": [
    {
      "order": 1,
      "plate_before": "1234 TBR", "plate_after": "5678 ABC",
      "gps_unload": [-18.92000, 47.53000],
      "gps_reload": [-18.92010, 47.53000],
      "distance_m": 11.4, "compliant": true,
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
    },
    {
      "order": 2,
      "plate_before": "5678 ABC", "plate_after": "9012 DEF",
      "gps_unload": [-18.95000, 47.55000],
      "gps_reload": [-18.95012, 47.55000],
      "distance_m": 13.1, "compliant": true,
      "photo_unload": {
        "key": "transload_2_unload",
        "heading_deg": 200.0,
        "heading_accuracy": 3.0,
        "heading_reference": "magnetic"
      },
      "photo_reload": {
        "key": "transload_2_reload",
        "heading_deg": 225.0,
        "heading_accuracy": 4.0,
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
    "plate_arrival": "9012 DEF",
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
> - **`id`** = UUID stable et unique du payload (un UUID par lot). La référence
>   locale lisible `MICA-…-L<n>` n'est pas utilisée comme identifiant API.
> - **`session_id`** = UUID stable partagé par les lots partis ensemble
>   (regroupement terrain).
> - **`lot_reference`** (optionnel, `null` possible) = regroupement **commercial**
>   côté Odoo (plusieurs lots/camions d'une même opération).

### Métadonnées d'orientation des photos

Tous les objets `photo`, `photo_unload`, `photo_reload`, `photo_arrival` et
`photo_license` utilisent le même format :

| Champ | Type | Obligatoire | Description |
|---|---|---|---|
| `key` | string | oui | Clé identique à celle de l'upload multipart |
| `hash` | string | non | SHA-256 s'il est disponible lors du submit |
| `heading_deg` | number | non | Direction visée par la caméra, `0 <= x < 360` |
| `heading_accuracy` | number | non | Marge d'erreur estimée en degrés |
| `heading_reference` | string | non | Toujours `magnetic` dans l'app actuelle |

`heading_deg=0` indique le nord magnétique, `90` l'est, `180` le sud et `270`
l'ouest. Les trois champs `heading_*` sont absents pour les anciennes captures
et lorsqu'aucun magnétomètre n'est disponible. Leur absence ne doit pas faire
échouer le submit.

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

## 3. `POST /api/attachments` — une photo par requête

Envoyé **après** un submit réussi. Chaque photo du lot produit sa propre requête
`multipart/form-data` et est identifiée par sa `key` (celle déclarée dans le
payload).

Le lot est identifié par **DEUX champs** :
- **`payload_id`** = UUID du payload (`payload.id`) → savoir à quel submit le
  fichier appartient.
- **`device_uuid`** = clé d'idempotence stable (celle du même lot).

**Un upload = une photo.** Le serveur doit rendre le rejeu du triplet
`payload_id` + `key` + `hash` idempotent.

### Requête (multipart/form-data)
```
payload_id        : de305d54-75b4-431b-adb2-eb6b9e546014
device_uuid       : 550e8400-e29b-41d4-a716-446655440000
key               : mine
hash              : 9f2c...e7
file              : <binaire JPEG>
```

### Réponse attendue (200)
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

- Le serveur rattache chaque fichier au **lot** (via `payload_id` / `device_uuid`)
  sous le champ correspondant à `photo_key`.
- **Idempotence photo** : si le `hash` est déjà connu pour cette clé, ignorer
  (ne pas recréer). Permet de rejouer la requête sans doublon.
- L'app conserve le fichier local après confirmation pour permettre sa
  consultation. Elle mémorise la clé confirmée afin de ne pas la renvoyer.
  Le SHA-256 est calculé avant chaque envoi et transmis dans `hash`.

### Schéma des `photo_key`
Les clés sont **scopées au lot** (1 payload = 1 lot), donc simples :

| Photo | `photo_key` |
|---|---|
| Mine d'origine du lot | `mine` |
| Transbordement bloc `<n>` décharge | `transload_<n>_unload` |
| Transbordement bloc `<n>` recharge | `transload_<n>_reload` |
| Arrivée dépôt | `arrival` |
| Permis chauffeur | `license` |

---

## 4. `POST /api/password/change`

Changement de mot de passe agent (en ligne), puis synchronisation hors ligne
automatique si l'appel échoue temporairement.

### Requête

```json
{ "current_password": "Ancien123", "new_password": "Nouveau123" }
```

### Cas fonctionnels

- Réponse succès : 200/201/200 avec `status: "ok"` selon implémentation
- Erreur `400/401/403/422` : le changement est refusé, l'app affiche le message
  serveur.
- Erreur réseau non-application : la modification est **mise en file d’attente locale**
  et re-soumise automatiquement au prochain sync (`SyncEngine._syncPendingPassword`).

### Comportement applicatif côté mobile

Le flux mobile appelle directement `/api/password/change`. En cas
de succès immédiat :
- le nouveau mot de passe est conservé côté stockage chiffré local,
- toute file de changement pendante est nettoyée.

En cas d'échec réseau :
- la demande est persistée localement (`PendingPasswordChange`),
- elle reste visible dans le détail des syncs avec un status `pending`,
- elle est renvoyée automatiquement en tâche de sync.

> Endpoint attendu côté serveur : `POST /api/password/change` avec la forme
> {`current_password`, `new_password`}.

---

## 5. `POST /api/logout`

Invalide le token courant. L'app l'appelle à la déconnexion explicite.

```json
{ "id": 1 }
```

> ⚠️ La collection Postman envoie un `id` numérique. **`/api/login` doit donc
> renvoyer cet id** (`data.agent.id`) — sinon l'app ne peut pas construire la
> requête. À confirmer.

---

## 6. Codes HTTP

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

## 7. À confirmer par Technarea

1. **`/api/mine` et `/api/storage`** : forme exacte de la réponse ? L'app attend
   `data: [...]` avec `id`, `name`, `lat`, `lon`, `radius_m`, `active`.
   **`radius_m` est indispensable** (contrôle GPS anti-fraude).
2. **`/api/logout`** : l'`id` numérique attendu doit être renvoyé par `/api/login`
   (`data.agent.id`). Confirmé ?
3. **`collect_type`** : l'app envoie `"chargement"` comme dans votre exemple,
   alors qu'un payload = **un lot**. Faut-il une valeur distincte ?
4. **`photo.key` de la mine** : l'app envoie `"mine"` (clé unique dans le lot).
   Votre exemple montre `"mine_M001"`. La clé n'ayant de sens qu'entre submit et
   upload, on garde `"mine"` sauf objection.
5. **Durée de vie du token** et comportement au 401 (refresh ou re-login ?).
6. **`session_id`** (UUID) et **`lot_reference`** : champs ajoutés par l'app
   pour regrouper les lots partis ensemble. Les stockez-vous ?
7. **Orientation photo** : confirmez-vous que les objets photo acceptent les
   champs optionnels `heading_deg`, `heading_accuracy` et
   `heading_reference="magnetic"` ?

> Note : quelques **valeurs** enum restent en français dans le payload
> (`status: "valide"`, `gps_status: "valide"`, `collect_type: "chargement"`).
> Dites-nous si vous voulez les normaliser en anglais aussi.
