# MICA Fleet

Application Flutter Android de collecte terrain et de traçabilité des lots de
mica entre une mine et un dépôt Radoran/Odoo.

## Fonctionnement

L'application est offline-first : les comptes déjà authentifiés, mines, lots,
photos et opérations de synchronisation sont conservés dans une base Drift
locale. Dès que le réseau revient, les mutations sont envoyées dans l'ordre,
puis les référentiels serveur sont rechargés sans doublon.

Fonctions principales :

- authentification en ligne avec reconnexion hors ligne par agent ;
- proposition géolocalisée d'une mine avec au moins cinq photos ;
- création d'un lot depuis une mine validée ou une proposition locale ;
- capture de la plaque et du camion chargé, avec GPS, hash et cap magnétique ;
- suivi des transbordements et de l'arrivée au dépôt ;
- synchronisation idempotente des payloads et upload des photos une par une ;
- récupération des mines, dépôts et lots validés depuis Odoo ;
- mise à jour Android depuis l'écran du compte.

## Configuration

La configuration est injectée à la compilation avec `--dart-define`.

| Variable | Défaut | Rôle |
|---|---|---|
| `MICA_DEMO` | mode debug | Utilise le backend simulé et les données de démonstration |
| `MICA_ODOO_URL` | `https://staging.radoran.net` | URL Odoo sans suffixe `/api` |
| `MICA_ODOO_TOKEN` | vide | Token de repli ; le token de connexion est stocké de façon sécurisée |

Lancement connecté au staging :

```bash
flutter run --release \
  --dart-define=MICA_DEMO=false \
  --dart-define=MICA_ODOO_URL=https://staging.radoran.net
```

## Développement

Prérequis : Flutter 3.41.9, Dart compatible avec le SDK `^3.11.5`, JDK 17 et
un appareil ou émulateur Android.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

Après une modification des tables Drift, modèles Freezed ou interfaces
Retrofit, relancer `build_runner` avant l'analyse.

## Build Android

APK connecté :

```bash
flutter build apk --release \
  --dart-define=MICA_DEMO=false \
  --dart-define=MICA_ODOO_URL=https://staging.radoran.net
```

APK de démonstration installable à côté de la production :

```bash
flutter build apk --release -Pdemo=true \
  --dart-define=MICA_DEMO=true
```

La GitHub Action [release.yml](.github/workflows/release.yml) exécute la
génération, les tests, l'analyse et construit les deux APK. Elle exige les
secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, ainsi que la variable optionnelle
`MICA_ODOO_URL`.

## Synchronisation mine et lot

Une proposition locale peut être sélectionnée immédiatement dans un lot. Au
moment de synchroniser, l'application :

1. envoie la proposition avec `POST /api/mine` ;
2. conserve l'identifiant numérique renvoyé dans `data.id` ;
3. remplace l'UUID local dans `payload.mine.mine_id` ;
4. envoie le lot sans attendre l'upload des photos de la mine ;
5. recharge mines, dépôts et lots depuis le serveur.

Le backend détermine fokontany, commune, district et région depuis les preuves
GPS. L'agent ne choisit pas la commune dans le formulaire.

## Documentation

- [Contrat API complet](docs/api/README.md)
- [Création et validation d'une mine](docs/api/contrat_creation_mine.md)
- [Schéma de la base locale](docs/database.md)
