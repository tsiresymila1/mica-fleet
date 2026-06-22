# Phase 2 — Transbordement, Arrivée Dépôt, Scoring & Délais — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compléter la chaîne logistique : transbordements dynamiques (0..N) avec contrôle GPS par maillon, validation d'arrivée au dépôt (chauffeur/permis/lot + GPS zone + détection multi-dépôts), moteur de scoring complet (Niveau 1 éligibilité + Niveau 2 conformité 100 pts), et suivi des délais avec alertes locales.

**Architecture:** Prolonge la base Phase 1 (Riverpod + Clean Arch + Drift + sync engine op-based). Nouvelles entités Freezed + tables Drift, usecases purs testés en TDD, chaque mutation journalisée dans `sync_queue`. Le scoring local reste **indicatif** (calcul définitif = Odoo).

**Tech Stack:** Identique Phase 1. Réutilise `haversineMeters`/`isWithinRadius`, `SyncOperation`, `LoadingRepository`.

**Référence spec:** `docs/superpowers/specs/2026-06-22-app-mobile-tracabilite-mica-design.md` (§6.3, §6.4, §6bis, §7, §10)
**Prérequis:** Phase 1 terminée (tag `phase-1-mvp`).

---

## File Structure (Phase 2)

```
lib/
  core/db/app_database.dart            # +tables Transbordements, ArriveesDepot, Depots
  features/
    transport/
      domain/entities/transbordement.dart
      domain/repositories/transport_repository.dart
      domain/usecases/add_transbordement.dart
      domain/usecases/remove_transbordement.dart
      domain/usecases/validate_transbordement.dart
      data/repositories/transport_repository_impl.dart
      presentation/providers/transport_provider.dart
      presentation/screens/transbordement_screen.dart
    depot/
      domain/entities/depot.dart
      domain/entities/arrivee_depot.dart
      domain/repositories/depot_repository.dart
      domain/usecases/detect_depot.dart
      domain/usecases/validate_arrivee.dart
      data/repositories/depot_repository_impl.dart
      presentation/providers/depot_provider.dart
      presentation/screens/arrivee_screen.dart
    scoring/
      domain/entities/score_result.dart
      domain/entities/scoring_inputs.dart
      domain/scoring_engine.dart
    delais/
      domain/entities/delai_config.dart
      domain/delais_checker.dart
test/
  features/transport/transbordement_test.dart
  features/depot/depot_test.dart
  features/scoring/scoring_engine_test.dart
  features/delais/delais_checker_test.dart
```

---

## Task 1: Tables Drift Phase 2

**Files:**
- Modify: `lib/core/db/app_database.dart`

- [ ] **Step 1: Ajouter les tables (avant la déclaration `@DriftDatabase`)**

```dart
@DataClassName('DepotRow')
class Depots extends Table {
  TextColumn get id => text()();
  TextColumn get nom => text()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get rayonMetres => real().withDefault(const Constant(20))();
  BoolColumn get actif => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TransbordementRow')
class Transbordements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get chargementId => text().references(Chargements, #id)();
  IntColumn get ordre => integer()(); // séquence dans la chaîne (1..N)
  TextColumn get plaqueAvant => text().nullable()();
  TextColumn get plaqueApres => text().nullable()();
  RealColumn get gpsDechargeLat => real().nullable()();
  RealColumn get gpsDechargeLon => real().nullable()();
  RealColumn get gpsRechargeLat => real().nullable()();
  RealColumn get gpsRechargeLon => real().nullable()();
  RealColumn get distanceMetres => real().nullable()();
  BoolColumn get conforme => boolean().withDefault(const Constant(false))();
  TextColumn get photoDechargePath => text().nullable()();
  TextColumn get photoRechargePath => text().nullable()();
}

@DataClassName('ArriveeDepotRow')
class ArriveesDepot extends Table {
  TextColumn get chargementId => text().references(Chargements, #id)();
  TextColumn get depotId => text().references(Depots, #id)();
  TextColumn get chauffeur => text()();
  TextColumn get numPermis => text()();
  TextColumn get photoPermisPath => text().nullable()();
  TextColumn get numLot => text()();
  RealColumn get gpsLat => real()();
  RealColumn get gpsLon => real()();
  TextColumn get photoArriveePath => text().nullable()();
  TextColumn get statutGps => text()(); // valide / hors_zone
  @override
  Set<Column> get primaryKey => {chargementId};
}
```

- [ ] **Step 2: Enregistrer les tables**

Modify la ligne `@DriftDatabase(tables: [...])` pour ajouter `Depots, Transbordements, ArriveesDepot`, et bump `schemaVersion` à `2`.

```dart
@DriftDatabase(tables: [
  Fournisseurs, Mines, Chargements, MineChargements, SyncQueue,
  Depots, Transbordements, ArriveesDepot,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  @override
  int get schemaVersion => 2;
  // ...
}
```

- [ ] **Step 3: Régénérer**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `app_database.g.dart` régénéré sans erreur.

- [ ] **Step 4: Commit**

```bash
git add lib/core/db/app_database.dart lib/core/db/app_database.g.dart 2>/dev/null; git add -A
git commit -m "feat(db): tables transbordements, arrivées dépôt, dépôts (schema v2)"
```

---

## Task 2: Entité Transbordement + usecases (TDD)

**Files:**
- Create: `lib/features/transport/domain/entities/transbordement.dart`
- Create: `lib/features/transport/domain/usecases/add_transbordement.dart`
- Create: `lib/features/transport/domain/usecases/remove_transbordement.dart`
- Create: `lib/features/transport/domain/usecases/validate_transbordement.dart`
- Test: `test/features/transport/transbordement_test.dart`

- [ ] **Step 1: Entité**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'transbordement.freezed.dart';

@freezed
abstract class Transbordement with _$Transbordement {
  const Transbordement._();
  const factory Transbordement({
    required int ordre,
    String? plaqueAvant,
    String? plaqueApres,
    double? gpsDechargeLat,
    double? gpsDechargeLon,
    double? gpsRechargeLat,
    double? gpsRechargeLon,
    @Default(false) bool conforme,
  }) = _Transbordement;
}
```

- [ ] **Step 2: Usecases (chaîne dynamique 0..N)**

`add_transbordement.dart`:
```dart
import '../entities/transbordement.dart';

class AddTransbordement {
  /// Ajoute un maillon en fin de chaîne, ordre = taille+1.
  List<Transbordement> call(List<Transbordement> chaine, Transbordement maillon) {
    final ordre = chaine.length + 1;
    return [...chaine, maillon.copyWith(ordre: ordre)];
  }
}
```
`remove_transbordement.dart`:
```dart
import '../entities/transbordement.dart';

class RemoveTransbordement {
  /// Retire le maillon d'ordre donné et renumérote la chaîne.
  List<Transbordement> call(List<Transbordement> chaine, int ordre) {
    final filtree = chaine.where((m) => m.ordre != ordre).toList();
    for (var i = 0; i < filtree.length; i++) {
      filtree[i] = filtree[i].copyWith(ordre: i + 1);
    }
    return filtree;
  }
}
```
`validate_transbordement.dart`:
```dart
import '../../../../core/utils/geo.dart';
import '../entities/transbordement.dart';

class ValidateTransbordement {
  /// Marque chaque maillon conforme si distance décharge↔recharge ≤ rayon.
  List<Transbordement> call(List<Transbordement> chaine, double rayonMetres) {
    return chaine.map((m) {
      if (m.gpsDechargeLat == null || m.gpsRechargeLat == null) {
        return m.copyWith(conforme: false);
      }
      final ok = isWithinRadius(m.gpsDechargeLat!, m.gpsDechargeLon!,
          m.gpsRechargeLat!, m.gpsRechargeLon!, rayonMetres);
      return m.copyWith(conforme: ok);
    }).toList();
  }

  /// Cohérence de chaîne : plaqueApres[i] == plaqueAvant[i+1].
  bool chaineCoherente(List<Transbordement> chaine) {
    for (var i = 0; i < chaine.length - 1; i++) {
      if (chaine[i].plaqueApres != chaine[i + 1].plaqueAvant) return false;
    }
    return true;
  }
}
```

- [ ] **Step 3: Écrire les tests qui échouent**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/transport/domain/entities/transbordement.dart';
import 'package:mica_fleet/features/transport/domain/usecases/add_transbordement.dart';
import 'package:mica_fleet/features/transport/domain/usecases/remove_transbordement.dart';
import 'package:mica_fleet/features/transport/domain/usecases/validate_transbordement.dart';

void main() {
  test('add ajoute des maillons avec ordre croissant 0..N', () {
    final add = AddTransbordement();
    var c = <Transbordement>[];
    c = add(c, const Transbordement(ordre: 0, plaqueApres: 'B'));
    c = add(c, const Transbordement(ordre: 0, plaqueAvant: 'B', plaqueApres: 'C'));
    expect(c.map((m) => m.ordre).toList(), [1, 2]);
  });

  test('remove renumérote la chaîne', () {
    final add = AddTransbordement();
    final rem = RemoveTransbordement();
    var c = <Transbordement>[];
    for (var i = 0; i < 3; i++) {
      c = add(c, const Transbordement(ordre: 0));
    }
    c = rem(c, 2);
    expect(c.map((m) => m.ordre).toList(), [1, 2]);
  });

  test('validate marque conforme si dans le rayon', () {
    final v = ValidateTransbordement();
    final c = [
      const Transbordement(ordre: 1,
          gpsDechargeLat: -18.90000, gpsDechargeLon: 47.5,
          gpsRechargeLat: -18.90010, gpsRechargeLon: 47.5),
    ];
    expect(v(c, 20).single.conforme, isTrue);
  });

  test('chaineCoherente vraie si plaques s enchaînent', () {
    final v = ValidateTransbordement();
    final c = [
      const Transbordement(ordre: 1, plaqueApres: 'B'),
      const Transbordement(ordre: 2, plaqueAvant: 'B', plaqueApres: 'C'),
    ];
    expect(v.chaineCoherente(c), isTrue);
  });
}
```

- [ ] **Step 4: Lancer (échec attendu)**

Run: `flutter test test/features/transport/transbordement_test.dart`
Expected: FAIL — symboles non générés.

- [ ] **Step 5: Générer + relancer**

Run: `dart run build_runner build --delete-conflicting-outputs`
Run: `flutter test test/features/transport/transbordement_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/transport/ test/features/transport/
git commit -m "feat(transport): transbordement dynamique 0..N + validation GPS (TDD)"
```

---

## Task 3: Détection dépôt + validation arrivée (TDD)

**Files:**
- Create: `lib/features/depot/domain/entities/depot.dart`
- Create: `lib/features/depot/domain/entities/arrivee_depot.dart`
- Create: `lib/features/depot/domain/usecases/detect_depot.dart`
- Create: `lib/features/depot/domain/usecases/validate_arrivee.dart`
- Test: `test/features/depot/depot_test.dart`

- [ ] **Step 1: Entités**

`depot.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'depot.freezed.dart';

@freezed
abstract class Depot with _$Depot {
  const factory Depot({
    required String id, required String nom,
    required double lat, required double lon,
    @Default(20) double rayonMetres, @Default(true) bool actif,
  }) = _Depot;
}
```
`arrivee_depot.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'arrivee_depot.freezed.dart';

@freezed
abstract class ArriveeDepot with _$ArriveeDepot {
  const factory ArriveeDepot({
    required String chargementId, required String depotId,
    required String chauffeur, required String numPermis, required String numLot,
    required double gpsLat, required double gpsLon,
    required String statutGps, // valide / hors_zone
    String? photoPermisPath, String? photoArriveePath,
  }) = _ArriveeDepot;
}
```

- [ ] **Step 2: Usecases**

`detect_depot.dart`:
```dart
import '../../../../core/utils/geo.dart';
import '../entities/depot.dart';

class DetectDepot {
  /// Retourne le dépôt actif dont la zone contient la position, ou null.
  Depot? call(List<Depot> depots, double lat, double lon) {
    for (final d in depots.where((d) => d.actif)) {
      if (isWithinRadius(lat, lon, d.lat, d.lon, d.rayonMetres)) return d;
    }
    return null;
  }
}
```
`validate_arrivee.dart`:
```dart
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/arrivee_depot.dart';
import '../entities/depot.dart';
import 'detect_depot.dart';

class ValidateArrivee {
  final DetectDepot detect;
  ValidateArrivee(this.detect);

  Either<Failure, ArriveeDepot> call({
    required String chargementId, required List<Depot> depots,
    required double lat, required double lon,
    required String chauffeur, required String numPermis, required String numLot,
  }) {
    if (chauffeur.trim().isEmpty || numPermis.trim().isEmpty || numLot.trim().isEmpty) {
      return left(const Failure.validation('Chauffeur, permis et lot obligatoires'));
    }
    final depot = detect(depots, lat, lon);
    if (depot == null) {
      return left(const Failure.validation('Aucun dépôt reconnu dans la zone GPS'));
    }
    return right(ArriveeDepot(
      chargementId: chargementId, depotId: depot.id,
      chauffeur: chauffeur, numPermis: numPermis, numLot: numLot,
      gpsLat: lat, gpsLon: lon, statutGps: 'valide',
    ));
  }
}
```

- [ ] **Step 3: Écrire les tests qui échouent**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/depot/domain/entities/depot.dart';
import 'package:mica_fleet/features/depot/domain/usecases/detect_depot.dart';
import 'package:mica_fleet/features/depot/domain/usecases/validate_arrivee.dart';

void main() {
  final depots = [
    const Depot(id: 'D1', nom: 'Dépôt 1', lat: -18.9, lon: 47.5),
    const Depot(id: 'D2', nom: 'Dépôt 2', lat: -19.0, lon: 47.6),
  ];

  test('detect renvoie le dépôt dont la zone contient le point', () {
    final d = DetectDepot()(depots, -18.90005, 47.5);
    expect(d?.id, 'D1');
  });

  test('detect renvoie null hors zone', () {
    expect(DetectDepot()(depots, -18.95, 47.55), isNull);
  });

  test('validate échoue si champs obligatoires vides', () {
    final r = ValidateArrivee(DetectDepot())(
      chargementId: 'MICA-2026-0001', depots: depots, lat: -18.9, lon: 47.5,
      chauffeur: '', numPermis: 'P1', numLot: 'L1');
    expect(r.isLeft(), isTrue);
  });

  test('validate réussit dans la zone avec champs remplis', () {
    final r = ValidateArrivee(DetectDepot())(
      chargementId: 'MICA-2026-0001', depots: depots, lat: -18.90005, lon: 47.5,
      chauffeur: 'Jean', numPermis: 'P1', numLot: 'L1');
    expect(r.getRight().toNullable()!.depotId, 'D1');
  });
}
```

- [ ] **Step 4: Lancer (échec attendu)**

Run: `flutter test test/features/depot/depot_test.dart`
Expected: FAIL.

- [ ] **Step 5: Générer + relancer**

Run: `dart run build_runner build --delete-conflicting-outputs`
Run: `flutter test test/features/depot/depot_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/depot/ test/features/depot/
git commit -m "feat(depot): détection multi-dépôts + validation arrivée GPS (TDD)"
```

---

## Task 4: Moteur de scoring complet (TDD)

**Files:**
- Create: `lib/features/scoring/domain/entities/scoring_inputs.dart`
- Create: `lib/features/scoring/domain/entities/score_result.dart`
- Create: `lib/features/scoring/domain/scoring_engine.dart`
- Test: `test/features/scoring/scoring_engine_test.dart`

- [ ] **Step 1: Entrées + résultat**

`scoring_inputs.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'scoring_inputs.freezed.dart';

@freezed
abstract class ScoringInputs with _$ScoringInputs {
  const factory ScoringInputs({
    // Niveau 1 — éligibilité
    required bool gpsMineDansRayon,
    required bool photoMineValide,
    required bool fournisseurActif,
    required bool mineAutorisee,
    required bool donneesCompletes,
    required int nombreMines,
    required bool depotReconnu,
    required bool gpsNonFalsifie,
    // Niveau 2 — conformité
    required double distanceGpsMetres,     // A
    required double ratioDelai,            // B : temps écoulé / limite (1.0 = pile)
    required bool transportCoherent,       // C
    required double ecartQuantitePct,      // D : écart en %
    required double tauxConformite90j,     // E : 0..1
  }) = _ScoringInputs;
}
```
`score_result.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'score_result.freezed.dart';

@freezed
abstract class ScoreResult with _$ScoreResult {
  const factory ScoreResult({
    required bool eligible,
    required int score,        // 0..100 (0 si non éligible)
    required String statut,    // 'rejete' | 'evalue'
  }) = _ScoreResult;
}
```

- [ ] **Step 2: Moteur**

```dart
import 'entities/scoring_inputs.dart';
import 'entities/score_result.dart';

class ScoringEngine {
  ScoreResult evaluate(ScoringInputs i) {
    if (!_eligible(i)) {
      return const ScoreResult(eligible: false, score: 0, statut: 'rejete');
    }
    final score = _gps(i.distanceGpsMetres) +
        _delai(i.ratioDelai) +
        (i.transportCoherent ? 20 : 0) +
        _quantite(i.ecartQuantitePct) +
        _historique(i.tauxConformite90j);
    return ScoreResult(eligible: true, score: score, statut: 'evalue');
  }

  bool _eligible(ScoringInputs i) =>
      i.gpsMineDansRayon && i.photoMineValide && i.fournisseurActif &&
      i.mineAutorisee && i.donneesCompletes && i.nombreMines >= 1 &&
      i.nombreMines <= 3 && i.depotReconnu && i.gpsNonFalsifie;

  int _gps(double m) => m <= 20 ? 20 : m <= 50 ? 15 : m <= 100 ? 10 : 0;

  int _delai(double r) =>
      r <= 1.0 ? 25 : r <= 1.10 ? 18 : r <= 1.25 ? 12 : r <= 1.50 ? 6 : 0;

  int _quantite(double pct) =>
      pct <= 2 ? 20 : pct <= 5 ? 15 : pct <= 10 ? 10 : 0;

  int _historique(double t) =>
      t >= 0.95 ? 15 : t >= 0.90 ? 12 : t >= 0.80 ? 7 : 0;
}
```

- [ ] **Step 3: Écrire les tests qui échouent**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/scoring/domain/entities/scoring_inputs.dart';
import 'package:mica_fleet/features/scoring/domain/scoring_engine.dart';

ScoringInputs _base({
  bool gpsMine = true, int mines = 1, bool mock = false,
  double dist = 10, double ratio = 1.0, bool transport = true,
  double ecart = 1, double hist = 1.0,
}) => ScoringInputs(
  gpsMineDansRayon: gpsMine, photoMineValide: true, fournisseurActif: true,
  mineAutorisee: true, donneesCompletes: true, nombreMines: mines,
  depotReconnu: true, gpsNonFalsifie: !mock,
  distanceGpsMetres: dist, ratioDelai: ratio, transportCoherent: transport,
  ecartQuantitePct: ecart, tauxConformite90j: hist);

void main() {
  final engine = ScoringEngine();

  test('score parfait = 100', () {
    final r = engine.evaluate(_base());
    expect(r.eligible, isTrue);
    expect(r.score, 100);
  });

  test('GPS mine hors rayon → rejeté, score 0', () {
    final r = engine.evaluate(_base(gpsMine: false));
    expect(r.eligible, isFalse);
    expect(r.score, 0);
    expect(r.statut, 'rejete');
  });

  test('mock location → rejeté', () {
    expect(engine.evaluate(_base(mock: true)).eligible, isFalse);
  });

  test('4 mines → rejeté', () {
    expect(engine.evaluate(_base(mines: 4)).eligible, isFalse);
  });

  test('barèmes partiels cumulés', () {
    // GPS ≤50m=15, délai +25%=12, transport incohérent=0,
    // quantité ≤10%=10, historique ≥90%=12 → 49
    final r = engine.evaluate(_base(
        dist: 40, ratio: 1.25, transport: false, ecart: 8, hist: 0.92));
    expect(r.score, 15 + 12 + 0 + 10 + 12);
  });
}
```

- [ ] **Step 4: Lancer (échec attendu)**

Run: `flutter test test/features/scoring/scoring_engine_test.dart`
Expected: FAIL.

- [ ] **Step 5: Générer + relancer**

Run: `dart run build_runner build --delete-conflicting-outputs`
Run: `flutter test test/features/scoring/scoring_engine_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/scoring/ test/features/scoring/
git commit -m "feat(scoring): moteur Niveau 1 éligibilité + Niveau 2 conformité 100 pts (TDD)"
```

---

## Task 5: Vérificateur de délais (TDD)

**Files:**
- Create: `lib/features/delais/domain/entities/delai_config.dart`
- Create: `lib/features/delais/domain/delais_checker.dart`
- Test: `test/features/delais/delais_checker_test.dart`

- [ ] **Step 1: Config + checker**

`delai_config.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'delai_config.freezed.dart';

@freezed
abstract class DelaiConfig with _$DelaiConfig {
  const factory DelaiConfig({
    @Default(Duration(hours: 24)) Duration mineVersCollecte,
    @Default(Duration(hours: 48)) Duration collecteVersDepot,
    @Default(Duration(hours: 72)) Duration directVersDepot,
    @Default(0.8) double seuilAlerteAvant, // 80% du délai
  }) = _DelaiConfig;
}
```
`delais_checker.dart`:
```dart
enum DelaiStatut { ok, bientotEchu, depasse }

class DelaisChecker {
  /// Compare le temps écoulé à la limite. [seuilAvant] = fraction déclenchant l'alerte préventive.
  DelaiStatut statut(Duration ecoule, Duration limite, {double seuilAvant = 0.8}) {
    if (ecoule > limite) return DelaiStatut.depasse;
    if (ecoule >= limite * seuilAvant) return DelaiStatut.bientotEchu;
    return DelaiStatut.ok;
  }

  /// Ratio pour le scoring (catégorie B).
  double ratio(Duration ecoule, Duration limite) =>
      ecoule.inSeconds / limite.inSeconds;
}
```

- [ ] **Step 2: Écrire les tests qui échouent**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/delais/domain/delais_checker.dart';

void main() {
  final c = DelaisChecker();
  const limite = Duration(hours: 24);

  test('ok bien avant échéance', () {
    expect(c.statut(const Duration(hours: 10), limite), DelaiStatut.ok);
  });
  test('bientôt échu à 80%+', () {
    expect(c.statut(const Duration(hours: 20), limite), DelaiStatut.bientotEchu);
  });
  test('dépassé au-delà de la limite', () {
    expect(c.statut(const Duration(hours: 25), limite), DelaiStatut.depasse);
  });
  test('ratio = écoulé/limite', () {
    expect(c.ratio(const Duration(hours: 12), limite), closeTo(0.5, 0.001));
  });
}
```

- [ ] **Step 3: Lancer (échec attendu)**

Run: `flutter test test/features/delais/delais_checker_test.dart`
Expected: FAIL.

- [ ] **Step 4: Générer + relancer**

Run: `dart run build_runner build --delete-conflicting-outputs`
Run: `flutter test test/features/delais/delais_checker_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/delais/ test/features/delais/
git commit -m "feat(delais): vérificateur délais + ratio scoring (TDD)"
```

---

## Task 6: Vérification finale Phase 2

- [ ] **Step 1: Suite complète**

Run: `flutter test`
Expected: tous PASS (Phase 1 + Phase 2).

- [ ] **Step 2: Analyse**

Run: `flutter analyze`
Expected: 0 erreur.

- [ ] **Step 3: Commit + tag**

```bash
git add -A
git commit -m "chore: phase 2 terminée — transport, dépôt, scoring, délais"
git tag phase-2-complete
```

---

## Notes de fin de Phase 2

**Couvert** : transbordement dynamique 0..N (ajout/retrait/renumérotation, validation GPS par maillon, cohérence de chaîne de plaques), détection multi-dépôts + validation arrivée (chauffeur/permis/lot + GPS zone), moteur de scoring complet (Niveau 1 Pass/Fail + Niveau 2 A–E sur 100), vérificateur de délais + ratio pour le scoring.

**Reporté (itération UI / Phase 3)** : écrans complets transbordement et arrivée branchés à la caméra/OCR, persistance Drift + journalisation sync des transbordements/arrivées (repos `transport_repository_impl`/`depot_repository_impl` à câbler comme `LoadingRepositoryImpl`), purge photos post-sync, SQLCipher key management durci, journal immuable / blockchain, audits aléatoires.
