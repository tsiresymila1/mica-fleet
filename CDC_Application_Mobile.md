# Cahier des Charges Fonctionnel — Application Mobile de Traçabilité du Mica Artisanal

**Projet :** Système de Traçabilité Digitale du Mica Artisanal — Volet Application Mobile
**Périmètre :** Application mobile Android (offline-first) de collecte terrain
**Version :** 1.0
**Date :** 22 juin 2026
**Plateforme cible :** Flutter / Android (offline-first)
**Backend :** Odoo (via API de synchronisation) + Portail Fournisseur

> Ce document spécifie le fonctionnement de l'**application mobile** uniquement. Le calcul du score, le bonus et le portail fournisseur sont décrits dans les CDC associés (« CDC Application Mobile Traçabilité Mica » et « CDC Portail Fournisseur v2 ») et sont rappelés ici lorsqu'ils conditionnent un comportement de l'application.

---

## 1. Contexte et objectifs

### 1.1 Contexte
La filière mica artisanale présente des contraintes opérationnelles fortes que l'application doit absorber :

- Extraction artisanale dispersée, **sans mise en sac à la mine**
- Regroupement de produits issus de **plusieurs mines** (jusqu'à 3 par chargement)
- **Zones à faible ou sans couverture réseau** → fonctionnement hors ligne obligatoire
- **Multiples changements de transporteurs** (transbordements)
- Besoin de **preuves visuelles géolocalisées** infalsifiables
- Risques de mélange de lots

### 1.2 Objectif principal
Tracer le mica depuis la mine artisanale jusqu'au dépôt final, en collectant sur le terrain des preuves fiables, géolocalisées et infalsifiables, avec un fonctionnement **100 % hors ligne** et une **synchronisation différée** vers Odoo.

### 1.3 Objectifs spécifiques
- Garantir l'origine des produits (GPS + photo à la mine)
- Assurer la traçabilité multi-mines (≤ 3 mines par chargement)
- Suivre les transports et transbordements
- Vérifier les immatriculations des camions (OCR)
- Alimenter la création automatique des bons de commande dans Odoo
- Permettre un fonctionnement offline complet
- Fournir les données nécessaires au système de bonus basé sur la traçabilité

---

## 2. Périmètre fonctionnel

| Inclus dans l'application mobile | Hors application (Odoo / Portail) |
|---|---|
| Authentification fournisseur / responsable dépôt | Calcul final du score (moteur Odoo) |
| Création et gestion d'un chargement | Calcul et versement du bonus |
| Capture photo géolocalisée infalsifiable | Création du bon de commande |
| OCR plaque d'immatriculation | Classement fournisseur |
| Ajout multi-mines (≤ 3) | Paramétrage des délais et rayons GPS |
| Transbordement (déchargement + rechargement) | Consultation historique long terme (portail) |
| Arrivée et validation au dépôt | Comptabilité / paiements |
| File d'attente et synchronisation différée | |
| Aperçu local du score (estimation) | |
| Notifications et alertes de délai | |

---

## 3. Acteurs et rôles

| Acteur | Rôle dans l'application | Connexion réseau |
|---|---|---|
| **Fournisseur (terrain)** | Crée le chargement à la mine, prend les photos, gère le transport et le transbordement | Hors ligne autorisé |
| **Responsable dépôt** | Valide l'arrivée au dépôt, enregistre chauffeur/permis/lot, déclenche la validation de cohérence | **Connexion réseau requise** à l'arrivée |
| **Administrateur (Odoo)** | Définit mines, dépôts, délais, rayons GPS, bonus max | N/A (paramétrage côté Odoo, consommé par l'app) |
| **Contrôleur / Auditeur** (optionnel) | Audits terrain aléatoires | Lecture |

---

## 4. Architecture technique

### 4.1 Composants
- **Application mobile Android Flutter, offline-first**
- **Base de données locale** (chiffrée) : chargements, mines, dépôts, file de synchronisation, médias
- **Stockage photo local** sécurisé (chiffrement au repos)
- **API de synchronisation** vers le serveur Odoo central
- **Journal immuable des événements** (préparé pour blockchain en phase avancée)

### 4.2 Principe offline-first
1. Toute action terrain s'écrit **d'abord en base locale**.
2. Les médias et événements sont mis dans une **file de synchronisation persistante**.
3. Dès qu'une connexion est disponible, la file est **rejouée** vers Odoo (idempotent, reprise sur erreur).
4. Le serveur calcule le score ; l'application affiche le statut de synchronisation.

### 4.3 Données de référence synchronisées depuis Odoo
L'application télécharge et met en cache (lecture seule) :
- Liste des **mines autorisées et actives** (nom, district, commune, région, point GPS, rayon)
- Liste des **dépôts** (point GPS, rayon d'acceptation, multi-dépôts)
- **Délais** paramétrés par étape
- **Profil fournisseur** (identifiant, actif/inactif)
- Paramètres anti-fraude (HDOP, temps min sur site, etc.)

> Si ces données n'ont jamais été synchronisées, l'application doit bloquer la création de chargement et inviter à se connecter au moins une fois.

---

## 5. Authentification et sécurité d'accès

- **Identifiant fournisseur unique** + code/mot de passe (ou PIN local après première connexion).
- **Accès strictement limité aux données du fournisseur** connecté.
- **Première connexion en ligne obligatoire** (téléchargement des données de référence + jeton).
- Sessions suivantes **hors ligne autorisées** via jeton local et PIN.
- Déconnexion / changement d'utilisateur protégé.
- Verrouillage automatique après inactivité.

---

## 6. Processus métier et fonctionnalités détaillées

### 6.1 Chargement à la mine

**Parcours :**
1. Le fournisseur se connecte et choisit **« Nouveau chargement »**.
2. Il **sélectionne la mine** dans la liste des mines autorisées (recherche par nom/zone).
3. Il renseigne, pour cette mine :
   - **Référence produit**
   - **Couleur** du mica
   - **Quantité estimée**
4. Il prend une **photo obligatoire** (voir §6.4) incluant :
   - **Camion à moitié chargé**
   - **Plaque visible**
   - **Mica visible clairement** (échantillon en main)
5. L'application capture **automatiquement** : GPS, date, heure, plaque (OCR), nom carrière, district, commune, région (déduits de la mine).
6. Un **identifiant unique** est généré localement : `MICA-YYYY-XXXX`.

**Règles :**
- La création n'est possible que si le **GPS est dans le rayon autorisé** de la mine (sinon avertissement bloquant ou marquage « hors zone » selon paramétrage — l'éligibilité finale est tranchée par Odoo).
- **Temps minimum sur site** (ex. 5 min) : l'app mesure la présence dans le rayon ; si insuffisant, le critère GPS sera pénalisé (information affichée à l'utilisateur).
- Tous les champs obligatoires doivent être remplis avant validation.

### 6.2 Chargement multi-mines
- Bouton **« Ajouter une mine »** pour empiler une nouvelle source sur le même chargement.
- **Maximum 3 mines** par chargement (4ᵉ ajout bloqué).
- **Photo obligatoire pour chaque mine** (mêmes contraintes qu'en §6.4).
- Chaque mine conserve sa référence, couleur, quantité estimée, GPS, horodatage.
- Bouton **« Valider »** actif dès qu'au moins 1 mine (et ≤ 3) est ajoutée.

### 6.3 Transport et transbordement (regroupement)
En cas de changement de camion / regroupement :
1. **Photo de déchargement obligatoire** (géolocalisée).
2. **Photo de rechargement obligatoire** (géolocalisée).
3. **Nouvelle immatriculation** enregistrée (OCR + validation).
4. **GPS déchargement** et **GPS rechargement** enregistrés ; l'app calcule la distance entre les deux points.
   - Si **distance ≤ rayon paramétré** (ex. 20 m) → transbordement cohérent.
   - Sinon → alerte « GPS transbordement incohérent » (le score sera réduit côté Odoo).

### 6.4 Capture photo géolocalisée (infalsifiable) — règle transverse
Contraintes appliquées à **toutes** les photos (mine, transbordement, arrivée) :

- **Prise via l'application uniquement** — import depuis la galerie **interdit** et techniquement bloqué.
- **Géolocalisation et horodatage** attachés à la capture.
- **Signature numérique (hash SHA-256)** générée à la capture ; toute modification ultérieure invalide la photo.
- **Détection de mock location / GPS spoofing** : si position simulée détectée → critère GPS = 0 et alerte.
- **Coefficient de confiance GPS (HDOP)** enregistré avec la photo :
  - ≤ 10 m → 100 % | ≤ 20 m → 90 % | ≤ 50 m → 70 % | > 50 m → 0 %
- Assistance au cadrage : aide visuelle (netteté, plaque lisible, mica visible) avant validation.
- Stockage local **sans réexposition des métadonnées EXIF** au fournisseur (confidentialité des sites).

### 6.5 Reconnaissance de plaque (OCR)
- Lecture **automatique** de la plaque sur la photo.
- **Validation manuelle** proposée si l'OCR échoue ou si la confiance est faible.
- La plaque alimente la cohérence transport (départ vs arrivée).

### 6.6 Arrivée au dépôt (responsable dépôt)
**Pré-requis : connexion réseau active.**
1. Le responsable dépôt prend la **photo de déchargement** géolocalisée (preuve de réception).
2. L'application **détecte automatiquement le dépôt concerné** (multi-dépôts) selon le point GPS et le rayon paramétré.
3. **Validation automatique de cohérence** :
   - Immatriculation cohérente (départ → arrivée)
   - GPS d'arrivée **dans le rayon autorisé** du dépôt
   - Photo valide
4. Champs obligatoires :
   - **Nom du chauffeur**
   - **Numéro de permis**
   - **Photo du permis** (optionnel)
   - **Numéro de lot** (par couleur / référence)

---

## 7. Gestion des délais et rappels

L'application consomme les délais paramétrés dans Odoo et déclenche localement les rappels.

### 7.1 Délais paramétrés (exemples par défaut, modifiables côté Odoo)
- Mine → Point de collecte : **24 h**
- Point de collecte → Dépôt : **48 h**
- Transport direct → Dépôt : **72 h**
- Collecte → Validation finale : **24 h**

### 7.2 Notifications et alertes
L'application émet des notifications locales (et, en ligne, remonte les alertes à Odoo) :

| Alerte | Déclencheur | Niveau |
|---|---|---|
| Chargement non synchronisé | Hors ligne depuis > 24 h | Avertissement |
| Transport en retard | Délai étape dépassé | Critique |
| Arrivée non confirmée | Photo d'arrivée manquante après délai | Critique |
| GPS transbordement incohérent | Écart > rayon autorisé | Avertissement |
| Plaque non reconnue | OCR impossible | Information |
| Rappel avant échéance | Ex. 80 % du délai écoulé | Information |

### 7.3 Conséquences (calculées par Odoo, signalées par l'app)
Dépassement de délai → score de traçabilité réduit, bonus désactivé, alerte administrateur.

---

## 8. Validation GPS

- **Rayon mine** : le GPS de chargement doit être dans le rayon autorisé de la mine.
- **Rayon transbordement** (ex. 20 m) : distance déchargement↔rechargement.
- **Rayon dépôt** (ex. 20 m) : arrivée détectée automatiquement, photo géolocalisée obligatoire.
- **Multi-dépôts** : détection automatique du dépôt dans la zone, rayon paramétrable par dépôt.
- Tous les rayons sont **paramétrés côté administrateur Odoo** et appliqués par l'application.

---

## 9. Modèle de données local (capturé / stocké)

| Entité | Champs principaux |
|---|---|
| **Fournisseur** | Identifiant, nom, statut actif |
| **Mine** | Nom carrière, GPS, district, commune, région, rayon (référence) |
| **Camion** | Plaque (OCR + validée) |
| **Chargement** | ID `MICA-YYYY-XXXX`, fournisseur, statut, date/heure création |
| **Ligne mine (×1 à 3)** | Mine, référence produit, couleur, quantité estimée, GPS, horodatage, photo+hash, HDOP, durée sur site |
| **Transbordement** | GPS déchargement, GPS rechargement, distance, nouvelle plaque, photos+hash |
| **Arrivée dépôt** | Dépôt, GPS arrivée, statut zone, photo+hash, chauffeur, n° permis, photo permis, n° lot |
| **File de synchronisation** | Type d'événement, payload, statut (en attente / envoyé / erreur), tentatives |
| **Journal immuable** | Événement, horodatage, hash chaîné |

---

## 10. Mode offline et synchronisation

- **Tout fonctionne hors ligne** : création, photos, OCR, transbordement.
- **Stockage local chiffré** des données et médias.
- **Synchronisation automatique** dès retour réseau (et déclenchable manuellement).
- File **persistante, idempotente**, avec reprise sur erreur et nombre de tentatives.
- Affichage par chargement du **statut de synchronisation** : *En attente / Synchronisé / Erreur*.
- Compteur global **« Chargements en attente de synchronisation »** avec alerte au-delà de 24 h.
- Le **recalcul de score** côté Odoo peut intervenir après complétion de données (ex. validation manuelle de plaque) ; l'app reflète le statut le plus récent.

---

## 11. Aperçu local du score (estimation)

> Le score **officiel** est calculé exclusivement par Odoo après synchronisation et **ne peut être modifié manuellement**. L'application n'affiche qu'une **estimation indicative** pour guider le fournisseur sur le terrain.

Rappel des règles (référence — calcul final côté serveur) :

**Niveau 1 — Éligibilité (Pass/Fail)** — un seul échec ⇒ Score = 0, Bonus = 0, statut « Rejeté » :
- GPS mine dans le rayon autorisé
- Photo mine valide (prise via l'app, claire, camion + mica visibles)
- Fournisseur identifié et actif ; mine autorisée et active ; dépôt reconnu et actif
- Données complètes et synchronisées ; ≤ 3 mines ; GPS non falsifié

**Niveau 2 — Conformité (100 pts)** :
| Catégorie | Points | Règle (résumé) |
|---|---|---|
| A. Traçabilité GPS | 20 | ≤ 20 m : 20 / ≤ 50 m : 15 / ≤ 100 m : 10 / > 100 m : 0 |
| B. Respect des délais | 25 | ≤ 100 % : 25 / +10 % : 18 / +25 % : 12 / +50 % : 6 / > 50 % : 0 |
| C. Cohérence transport | 20 | Cohérent : 20 / Incohérent : 0 |
| D. Exactitude quantité | 20 | écart ≤ 2 % : 20 / ≤ 5 % : 15 / ≤ 10 % : 10 / > 10 % : 0 |
| E. Historique fournisseur (90 j.) | 15 | ≥ 95 % : 15 / ≥ 90 % : 12 / ≥ 80 % : 7 / < 80 % : 0 |

**Niveau 3 — Bonus** : `Bonus réel (Ar/kg) = Bonus Max × (Score / 100)` — seuil d'éligibilité ≥ 80.

---

## 12. Sécurité et intégrité des données

- **Signature SHA-256** de chaque photo à la capture.
- **Détection mock location / GPS spoofing** → rejet du point.
- **Pondération HDOP** du score GPS.
- **Temps minimum sur site** mine (anti-capture éclair).
- **Capture première obligatoire via l'app** (pas d'import galerie).
- **Cohérence temporelle/vitesse** : détection de trajets physiquement impossibles.
- **Limitation des chargements simultanés** par camion (un camion = un lieu à la fois).
- **Journal immuable** (hash chaîné) préparé pour ancrage blockchain.
- **Chiffrement local** au repos des données et médias.

> Détection de fraude ou score < 50 pendant 3 mois ⇒ mise sous surveillance / suspension (géré par Odoo).

---

## 13. Intégration Odoo (via API de synchronisation)

À la synchronisation d'un chargement, Odoo crée/alimente automatiquement :
- **Bon de commande à l'état brouillon**
- Fournisseur, dépôt, lots
- Photos (avec hash), positions GPS
- Score et éligibilité bonus (recalculés côté serveur)

Flux : **App mobile → API sync → Odoo → Portail fournisseur**.

---

## 14. Exigences non fonctionnelles

| Domaine | Exigence |
|---|---|
| **Disponibilité** | 100 % des fonctions terrain utilisables hors ligne |
| **Performance** | Capture + enregistrement local < 2 s ; OCR < 3 s |
| **Robustesse** | Aucune perte de donnée en cas de coupure/redémarrage |
| **Ergonomie** | Parcours simple, gros boutons, utilisable en extérieur / une main / faible luminosité |
| **Langue** | Français (extensible) |
| **Stockage** | Gestion de l'espace, compression photo sans perte de preuve |
| **Sécurité** | Chiffrement local, jeton, verrouillage |
| **Compatibilité** | Android (versions à préciser), appareils d'entrée de gamme |
| **Batterie** | Usage GPS optimisé pour journée terrain |

---

## 15. Écrans principaux (parcours)

1. **Connexion** (en ligne 1ʳᵉ fois, puis PIN offline)
2. **Tableau de bord** : chargements en cours, en attente de sync, alertes, score moyen estimé
3. **Nouveau chargement** : sélection mine → saisie (réf/couleur/quantité) → photo → ajout mine (≤ 3) → Valider
4. **Détail chargement** : lignes mines, statut GPS, statut sync, estimation score
5. **Transbordement** : photo déchargement → nouvelle plaque → photo rechargement → contrôle distance GPS
6. **Arrivée dépôt** (responsable, en ligne) : photo → détection dépôt → chauffeur/permis/lot → validation cohérence
7. **File de synchronisation** : statut par chargement, relance manuelle
8. **Notifications / alertes**
9. **Profil / déconnexion**

---

## 16. Règles métier clés (synthèse)

- 1 chargement = **1 à 3 mines** max.
- **Photo obligatoire par mine** et à chaque transbordement/arrivée, **prise via l'app**.
- **GPS hors rayon, mock location, photo importée** ⇒ éligibilité compromise (rejet possible).
- **Arrivée dépôt = connexion requise** ; le reste fonctionne offline.
- **Aucun score / donnée modifiable manuellement** après synchronisation.
- **Identifiant chargement `MICA-YYYY-XXXX`** généré localement et conservé jusqu'au portail.

---

## 17. Critères d'acceptation

- [ ] Création complète d'un chargement **hors ligne**, multi-mines (≤ 3).
- [ ] Photo **bloquée si importée** depuis la galerie ; capture app uniquement.
- [ ] **Hash SHA-256** présent et vérifiable sur chaque photo.
- [ ] **Mock location** détecté et rejeté.
- [ ] **OCR plaque** fonctionnel avec repli en saisie manuelle.
- [ ] **Transbordement** avec contrôle de distance GPS.
- [ ] **Arrivée dépôt** avec détection automatique du dépôt et validation de cohérence.
- [ ] **Synchronisation différée** fiable (reprise sur erreur, idempotence).
- [ ] **Bon de commande brouillon** créé automatiquement dans Odoo après sync.
- [ ] Alertes de **délai** et de **synchronisation** fonctionnelles.

---

## 18. Phases du projet

| Phase | Contenu |
|---|---|
| **Phase 1** | Application mobile : auth, chargement mine, multi-mines, photo+hash, OCR, offline, sync, bon de commande brouillon |
| **Phase 2** | Validation dépôt : transbordement GPS, arrivée multi-dépôts, délais & rappels |
| **Phase 3** | Sécurité avancée : anti-fraude complet (HDOP, vitesse, audits), journal immuable, préparation blockchain |

**Priorité projet : Très haute.**

---

## Annexes
- Documents sources : *Système de Traçabilité Digitale du Mica Artisanal*, *CDC Portail Fournisseur v2.0*, infographies « Flux complet de la mine au dépôt » et « Système de scoring ».
- *Projet Cartographie Minière de Radoran* (PDF) : référentiel des sites miniers — **non lu automatiquement** (extraction PDF indisponible). À intégrer comme source des points GPS/rayons de mines si requis.
