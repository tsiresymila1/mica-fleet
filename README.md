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
- vérification automatique des mises à jour Android au démarrage et au retour
  du réseau, bannière globale et téléchargement avec progression ;
- installation bloquée tant que des données locales restent à synchroniser.

## Configuration

La configuration est injectée à la compilation avec `--dart-define`.

| Variable | Défaut | Rôle |
|---|---|---|
| `MICA_DEMO` | mode debug | Utilise le backend simulé et les données de démonstration |
| `MICA_ODOO_URL` | `https://staging.radoran.net` | URL Odoo sans suffixe `/api` |
| `MICA_ODOO_TOKEN` | vide | Token de repli ; le token de connexion est stocké de façon sécurisée |

Lancement connecté à l’ERP :

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

## Saisie et suivi terrain

La mine d'origine doit être sélectionnée explicitement, sans valeur par défaut.
Les plaques sont obligatoires au chargement, au changement de camion (avant et
après) et à l'arrivée. Elles sont saisies manuellement, sans OCR. Le numéro de
permis est limité à 12 caractères.

Sur une ligne photo, un appui sur la miniature ouvre l'aperçu zoomable ; un appui
sur le reste de la ligne lance une nouvelle capture.
Les photos de plaque, du camion et de proposition de mine utilisent le premier
GPS récent disponible, sans seuil de précision, y compris si Android ne fournit
qu'une position approximative. La précision réelle reste enregistrée et envoyée ;
le GPS absent, les coordonnées invalides et les positions simulées restent refusés.
Le bouton affiche « Capture en cours… » pendant le traitement et empêche les
doubles appuis. Le cap de la boussole est collecté de la même façon pour les lots
et les propositions de mine.

Le suivi GPS enregistre les points en local même hors ligne, à partir de 8 m du
dernier point retenu, en écartant les positions invalides, simulées ou de précision
supérieure à 25 m. Le filtre anti-dérive demande deux mesures de confirmation,
ou trois avec une progression d'au moins 3 m lorsque le déplacement reste dans
la marge de précision combinée des positions. Il ignore les sauts incompatibles
avec le temps écoulé et les déplacements lorsque la vitesse GPS fiable indique
un arrêt ; une vitesse indisponible ne bloque pas le suivi. Cela peut retarder
de quelques secondes l'enregistrement. Les anciens points ne sont pas modifiés.
La carte réagit aux nouveaux points locaux ; le fond OpenStreetMap
nécessite du réseau pour les tuiles non déjà disponibles. Le score provient uniquement
du backoffice : sans score serveur, l'app affiche « Évaluation en cours ».

Sur Android, un service foreground natif possède le suivi dès qu'une session a
au moins un lot en route. Sa notification permanente reste visible et le service
continue après verrouillage, fermeture de l'interface ou retrait de l'application
des applications récentes. La session active est persistée et restaurée après
redémarrage du processus. Après redémarrage du téléphone, la reprise nécessite
la permission de localisation « Toujours autoriser ». Le service s'arrête lorsque
le dernier lot arrive. Android interrompt toutefois définitivement le suivi après
« Forcer l'arrêt », révocation du GPS ou désinstallation.

## Documentation

- [Contrat API complet](docs/api/README.md)
- [Création et validation d'une mine](docs/api/contrat_creation_mine.md)
- [Schéma de la base locale](docs/database.md)
