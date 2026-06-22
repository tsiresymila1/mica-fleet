# Phase 1 — Fondation, Collecte Mine & Sync Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer une tranche verticale fonctionnelle de l'app mobile : un fournisseur se connecte hors ligne, crée un chargement mica avec 1 à 3 mines (photo + GPS + hash), et tout est journalisé puis synchronisé vers Odoo via un moteur de sync op-based.

**Architecture:** Flutter + Riverpod + Clean Architecture feature-first. DB locale Drift (chiffrée SQLCipher) source de vérité ; écritures journalisées dans une file `sync_queue` ; `SyncEngine` push idempotent vers un `RemoteDataSource` Retrofit (Odoo) et pull du référentiel mines. Modèles immuables Freezed, erreurs `Either<Failure,T>` (fpdart).

**Tech Stack:** Flutter (Dart 3), Riverpod, Drift + SQLCipher, Freezed + json_serializable, Retrofit + dio, fpdart, geolocator, camera, google_mlkit_text_recognition, crypto, uuid, connectivity_plus, build_runner. minSdk 23.

**Référence spec:** `docs/superpowers/specs/2026-06-22-app-mobile-tracabilite-mica-design.md`

---

## File Structure (Phase 1)

```
pubspec.yaml
android/app/build.gradle              # minSdk 23, ABI split
lib/
  main.dart
  core/
    error/failure.dart                # Failure (freezed union)
    db/app_database.dart              # Drift DB + tables
    db/app_database.steps.dart        # (généré)
    network/dio_client.dart           # dio + intercepteurs
    network/connectivity.dart         # wrapper connectivity_plus
    utils/geo.dart                    # distance Haversine
    utils/loading_id.dart             # générateur MICA-YYYY-XXXX
    di/providers.dart                 # providers Riverpod racine
  features/
    auth/
      domain/entities/fournisseur.dart
      domain/repositories/auth_repository.dart
      domain/usecases/login.dart
      data/datasources/auth_local_ds.dart
      data/repositories/auth_repository_impl.dart
      presentation/providers/auth_provider.dart
      presentation/screens/login_screen.dart
    mines/
      domain/entities/mine.dart
      domain/repositories/mine_repository.dart
      data/repositories/mine_repository_impl.dart
    sync/
      domain/entities/sync_operation.dart
      domain/repositories/local_sync_store.dart
      domain/repositories/remote_data_source.dart
      data/local_sync_store_impl.dart
      data/remote_data_source_retrofit.dart   # Retrofit (.g généré)
      data/sync_engine.dart
      presentation/sync_provider.dart
    capture/
      domain/entities/captured_photo.dart
      domain/services/capture_service.dart
      domain/services/mock_location_guard.dart
      domain/services/plate_ocr_service.dart
      data/capture_service_impl.dart
      data/mock_location_guard_impl.dart
      data/plate_ocr_service_impl.dart
    loading/
      domain/entities/chargement.dart
      domain/entities/mine_chargement.dart
      domain/repositories/loading_repository.dart
      domain/usecases/create_chargement.dart
      domain/usecases/add_mine_to_chargement.dart
      domain/usecases/validate_chargement.dart
      data/repositories/loading_repository_impl.dart
      presentation/providers/loading_provider.dart
      presentation/screens/chargement_screen.dart
      presentation/screens/add_mine_screen.dart
test/
  core/utils/geo_test.dart
  core/utils/loading_id_test.dart
  features/auth/login_test.dart
  features/sync/sync_engine_test.dart
  features/loading/create_chargement_test.dart
  features/loading/validate_chargement_test.dart
```

---

## Task 0: Prérequis & scaffold du projet

**Files:**
- Create: whole Flutter project skeleton

- [ ] **Step 1: Vérifier le toolchain Flutter**

Run: `flutter --version`
Expected: affiche Flutter 3.x / Dart 3.x. Si « command not found », installer le SDK Flutter et l'ajouter au PATH avant de continuer.

- [ ] **Step 2: Générer le projet Flutter dans le dossier courant**

Run:
```bash
cd /Users/tsiresymila/Development/Flutter/mica-fleet
flutter create --org com.radoran --project-name mica_fleet --platforms=android .
```
Expected: arborescence Android créée sans écraser `docs/`.

- [ ] **Step 3: Ajouter les dépendances (dernières versions stables)**

Run:
```bash
flutter pub add flutter_riverpod drift sqlcipher_flutter_libs sqlite3_flutter_libs \
  fpdart freezed_annotation json_annotation retrofit dio geolocator camera \
  google_mlkit_text_recognition crypto uuid connectivity_plus path_provider path intl
flutter pub add dev:build_runner dev:drift_dev dev:freezed dev:json_serializable \
  dev:retrofit_generator dev:mocktail dev:flutter_lints
```
Expected: `pubspec.yaml` mis à jour, `pub get` réussi.

- [ ] **Step 4: Configurer Android bas de gamme**

Modify `android/app/build.gradle` — dans `defaultConfig`:
```gradle
minSdkVersion 23
targetSdkVersion 34
```
Ajouter le split ABI dans `android { ... }`:
```gradle
splits {
    abi {
        enable true
        reset()
        include "armeabi-v7a", "arm64-v8a"
        universalApk false
    }
}
```

- [ ] **Step 5: Permissions Android**

Modify `android/app/src/main/AndroidManifest.xml` — ajouter avant `<application>`:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: scaffold flutter project + deps + android low-end config"
```

---

## Task 1: Failure union (Freezed)

**Files:**
- Create: `lib/core/error/failure.dart`

- [ ] **Step 1: Écrire la union Failure**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'failure.freezed.dart';

@freezed
sealed class Failure with _$Failure {
  const factory Failure.network([String? message]) = NetworkFailure;
  const factory Failure.database([String? message]) = DatabaseFailure;
  const factory Failure.auth([String? message]) = AuthFailure;
  const factory Failure.validation(String message) = ValidationFailure;
  const factory Failure.mockLocation() = MockLocationFailure;
  const factory Failure.unexpected([String? message]) = UnexpectedFailure;
}
```

- [ ] **Step 2: Générer le code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `failure.freezed.dart` créé, pas d'erreur.

- [ ] **Step 3: Commit**

```bash
git add lib/core/error/
git commit -m "feat(core): Failure union freezed"
```

---

## Task 2: Distance Haversine (TDD)

**Files:**
- Create: `lib/core/utils/geo.dart`
- Test: `test/core/utils/geo_test.dart`

- [ ] **Step 1: Écrire le test qui échoue**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/utils/geo.dart';

void main() {
  test('distance 0 entre point identique', () {
    expect(haversineMeters(-18.9, 47.5, -18.9, 47.5), closeTo(0, 0.001));
  });

  test('distance ~111320 m pour 1 degré de latitude', () {
    expect(haversineMeters(0, 0, 1, 0), closeTo(111320, 200));
  });

  test('isWithinRadius vrai si distance <= rayon', () {
    // ~15 m à cette latitude
    expect(isWithinRadius(-18.90000, 47.50000, -18.90013, 47.50000, 20), isTrue);
    expect(isWithinRadius(-18.90000, 47.50000, -18.90050, 47.50000, 20), isFalse);
  });
}
```

- [ ] **Step 2: Lancer le test (échec attendu)**

Run: `flutter test test/core/utils/geo_test.dart`
Expected: FAIL — `haversineMeters` non défini.

- [ ] **Step 3: Implémenter**

```dart
import 'dart:math' as math;

/// Distance en mètres entre deux points GPS (formule de Haversine).
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0; // rayon Terre en m
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) *
          math.sin(dLon / 2) * math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

bool isWithinRadius(
  double lat1, double lon1, double lat2, double lon2, double radiusMeters) {
  return haversineMeters(lat1, lon1, lat2, lon2) <= radiusMeters;
}

double _rad(double deg) => deg * math.pi / 180.0;
```

- [ ] **Step 4: Lancer le test (succès attendu)**

Run: `flutter test test/core/utils/geo_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/geo.dart test/core/utils/geo_test.dart
git commit -m "feat(core): distance Haversine + isWithinRadius (TDD)"
```

---

## Task 3: Générateur d'ID de chargement (TDD)

**Files:**
- Create: `lib/core/utils/loading_id.dart`
- Test: `test/core/utils/loading_id_test.dart`

- [ ] **Step 1: Écrire le test qui échoue**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/utils/loading_id.dart';

void main() {
  test('format MICA-YYYY-XXXX avec année et séquence paddée', () {
    expect(buildLoadingId(2026, 7), 'MICA-2026-0007');
    expect(buildLoadingId(2026, 1234), 'MICA-2026-1234');
  });

  test('séquence > 9999 non tronquée', () {
    expect(buildLoadingId(2026, 12345), 'MICA-2026-12345');
  });
}
```

- [ ] **Step 2: Lancer le test (échec attendu)**

Run: `flutter test test/core/utils/loading_id_test.dart`
Expected: FAIL — `buildLoadingId` non défini.

- [ ] **Step 3: Implémenter**

```dart
/// Construit l'identifiant unique d'un chargement : MICA-YYYY-XXXX.
/// [sequence] est paddé sur 4 chiffres minimum.
String buildLoadingId(int year, int sequence) {
  final seq = sequence.toString().padLeft(4, '0');
  return 'MICA-$year-$seq';
}
```

- [ ] **Step 4: Lancer le test (succès attendu)**

Run: `flutter test test/core/utils/loading_id_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/loading_id.dart test/core/utils/loading_id_test.dart
git commit -m "feat(core): générateur ID MICA-YYYY-XXXX (TDD)"
```

---

## Task 4: Base de données Drift chiffrée

**Files:**
- Create: `lib/core/db/app_database.dart`

- [ ] **Step 1: Définir les tables et la DB**

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'app_database.g.dart';

class Fournisseurs extends Table {
  TextColumn get id => text()();
  TextColumn get nom => text()();
  BoolColumn get actif => boolean().withDefault(const Constant(true))();
  TextColumn get sessionToken => text().nullable()();
  @override Set<Column> get primaryKey => {id};
}

class Mines extends Table {
  TextColumn get id => text()();
  TextColumn get nom => text()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get rayonMetres => real().withDefault(const Constant(20))();
  TextColumn get district => text().nullable()();
  TextColumn get commune => text().nullable()();
  TextColumn get region => text().nullable()();
  BoolColumn get actif => boolean().withDefault(const Constant(true))();
  @override Set<Column> get primaryKey => {id};
}

class Chargements extends Table {
  TextColumn get id => text()(); // MICA-YYYY-XXXX
  TextColumn get fournisseurId => text()();
  DateTimeColumn get dateCreation => dateTime()();
  TextColumn get statut => text().withDefault(const Constant('brouillon'))();
  @override Set<Column> get primaryKey => {id};
}

class MineChargements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get chargementId => text().references(Chargements, #id)();
  TextColumn get mineId => text().references(Mines, #id)();
  TextColumn get reference => text().nullable()();
  TextColumn get couleur => text().nullable()();
  RealColumn get quantiteEstimee => real().nullable()();
  TextColumn get plaqueOcr => text().nullable()();
  RealColumn get gpsLat => real().nullable()();
  RealColumn get gpsLon => real().nullable()();
  RealColumn get gpsPrecision => real().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get photoHash => text().nullable()();
  DateTimeColumn get dateHeure => dateTime().nullable()();
}

class SyncQueue extends Table {
  TextColumn get opId => text()(); // UUID
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get opType => text()(); // create/update/delete
  TextColumn get payload => text()(); // JSON
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {opId};
}

@DriftDatabase(tables: [Fournisseurs, Mines, Chargements, MineChargements, SyncQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  @override int get schemaVersion => 1;

  static Future<AppDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'mica_fleet.db'));
    return AppDatabase(NativeDatabase(file)); // SQLCipher branché via setup natif
  }

  /// Variante in-memory pour les tests.
  static AppDatabase memory() => AppDatabase(NativeDatabase.memory());
}
```

> Note SQLCipher : la clé de chiffrement et `PRAGMA key` se configurent via `sqlcipher_flutter_libs` au démarrage (setup dans `main.dart`, Task 12). Les tests utilisent `AppDatabase.memory()` sans chiffrement.

- [ ] **Step 2: Générer le code Drift**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `app_database.g.dart` généré sans erreur.

- [ ] **Step 3: Commit**

```bash
git add lib/core/db/
git commit -m "feat(core): schéma Drift (fournisseurs, mines, chargements, sync_queue)"
```

---

## Task 5: SyncOperation (entité Freezed)

**Files:**
- Create: `lib/features/sync/domain/entities/sync_operation.dart`

- [ ] **Step 1: Écrire l'entité**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'sync_operation.freezed.dart';

enum SyncStatus { pending, syncing, synced, failed }
enum SyncOpType { create, update, delete }

@freezed
class SyncOperation with _$SyncOperation {
  const factory SyncOperation({
    required String opId,
    required String entityType,
    required String entityId,
    required SyncOpType opType,
    required Map<String, dynamic> payload,
    @Default(SyncStatus.pending) SyncStatus status,
    @Default(0) int attempts,
    String? lastError,
    required DateTime createdAt,
    DateTime? nextRetryAt,
  }) = _SyncOperation;
}
```

- [ ] **Step 2: Générer**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `sync_operation.freezed.dart` généré.

- [ ] **Step 3: Commit**

```bash
git add lib/features/sync/domain/entities/
git commit -m "feat(sync): entité SyncOperation"
```

---

## Task 6: Contrats d'adaptateurs sync

**Files:**
- Create: `lib/features/sync/domain/repositories/local_sync_store.dart`
- Create: `lib/features/sync/domain/repositories/remote_data_source.dart`

- [ ] **Step 1: LocalSyncStore (contrat)**

```dart
import '../entities/sync_operation.dart';

abstract class LocalSyncStore {
  Future<void> enqueue(SyncOperation op);
  Future<List<SyncOperation>> pending(); // FIFO par createdAt
  Future<void> updateStatus(String opId, SyncStatus status,
      {int? attempts, String? lastError, DateTime? nextRetryAt});
}
```

- [ ] **Step 2: RemoteDataSource (contrat)**

```dart
import '../entities/sync_operation.dart';

class RemoteMine {
  final String id, nom;
  final double lat, lon, rayonMetres;
  final String? district, commune, region;
  final bool actif;
  RemoteMine(this.id, this.nom, this.lat, this.lon, this.rayonMetres,
      this.district, this.commune, this.region, this.actif);
}

abstract class RemoteDataSource {
  /// Push idempotent : Odoo déduplique sur op.opId. Lève en cas d'échec réseau.
  Future<void> pushOperation(SyncOperation op);
  /// Pull du référentiel mines.
  Future<List<RemoteMine>> fetchMines();
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/sync/domain/repositories/
git commit -m "feat(sync): contrats LocalSyncStore + RemoteDataSource"
```

---

## Task 7: LocalSyncStore (impl Drift, TDD)

**Files:**
- Create: `lib/features/sync/data/local_sync_store_impl.dart`
- Test: `test/features/sync/sync_engine_test.dart` (partie store)

- [ ] **Step 1: Écrire le test qui échoue**

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/sync/data/local_sync_store_impl.dart';
import 'package:mica_fleet/features/sync/domain/entities/sync_operation.dart';

SyncOperation _op(String id, DateTime at) => SyncOperation(
      opId: id, entityType: 'chargement', entityId: 'MICA-2026-0001',
      opType: SyncOpType.create, payload: {'k': 'v'}, createdAt: at);

void main() {
  late AppDatabase db;
  late DriftLocalSyncStore store;

  setUp(() {
    db = AppDatabase.memory();
    store = DriftLocalSyncStore(db);
  });
  tearDown(() => db.close());

  test('enqueue puis pending renvoie en FIFO', () async {
    await store.enqueue(_op('b', DateTime(2026, 1, 2)));
    await store.enqueue(_op('a', DateTime(2026, 1, 1)));
    final p = await store.pending();
    expect(p.map((o) => o.opId).toList(), ['a', 'b']);
  });

  test('updateStatus synced retire de pending', () async {
    await store.enqueue(_op('a', DateTime(2026, 1, 1)));
    await store.updateStatus('a', SyncStatus.synced);
    expect(await store.pending(), isEmpty);
  });
}
```

- [ ] **Step 2: Lancer (échec attendu)**

Run: `flutter test test/features/sync/sync_engine_test.dart`
Expected: FAIL — `DriftLocalSyncStore` non défini.

- [ ] **Step 3: Implémenter**

```dart
import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../domain/entities/sync_operation.dart';
import '../domain/repositories/local_sync_store.dart';

class DriftLocalSyncStore implements LocalSyncStore {
  final AppDatabase db;
  DriftLocalSyncStore(this.db);

  @override
  Future<void> enqueue(SyncOperation op) async {
    await db.into(db.syncQueue).insertOnConflictUpdate(SyncQueueCompanion.insert(
          opId: op.opId,
          entityType: op.entityType,
          entityId: op.entityId,
          opType: op.opType.name,
          payload: jsonEncode(op.payload),
          createdAt: op.createdAt,
          status: Value(op.status.name),
          attempts: Value(op.attempts),
        ));
  }

  @override
  Future<List<SyncOperation>> pending() async {
    final q = db.select(db.syncQueue)
      ..where((t) => t.status.equals('pending'))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    final rows = await q.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> updateStatus(String opId, SyncStatus status,
      {int? attempts, String? lastError, DateTime? nextRetryAt}) async {
    await (db.update(db.syncQueue)..where((t) => t.opId.equals(opId))).write(
      SyncQueueCompanion(
        status: Value(status.name),
        attempts: attempts == null ? const Value.absent() : Value(attempts),
        lastError: Value(lastError),
        nextRetryAt: Value(nextRetryAt),
      ),
    );
  }

  SyncOperation _toEntity(SyncQueueData r) => SyncOperation(
        opId: r.opId,
        entityType: r.entityType,
        entityId: r.entityId,
        opType: SyncOpType.values.byName(r.opType),
        payload: jsonDecode(r.payload) as Map<String, dynamic>,
        status: SyncStatus.values.byName(r.status),
        attempts: r.attempts,
        lastError: r.lastError,
        createdAt: r.createdAt,
        nextRetryAt: r.nextRetryAt,
      );
}
```

- [ ] **Step 4: Lancer (succès attendu)**

Run: `flutter test test/features/sync/sync_engine_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/sync/data/local_sync_store_impl.dart test/features/sync/sync_engine_test.dart
git commit -m "feat(sync): DriftLocalSyncStore (TDD)"
```

---

## Task 8: RemoteDataSource Retrofit (Odoo)

**Files:**
- Create: `lib/core/network/dio_client.dart`
- Create: `lib/features/sync/data/remote_data_source_retrofit.dart`

- [ ] **Step 1: Client dio**

```dart
import 'package:dio/dio.dart';

Dio buildDio({required String baseUrl, String? token}) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {if (token != null) 'Authorization': 'Bearer $token'},
  ));
  return dio;
}
```

- [ ] **Step 2: API Retrofit + adaptateur**

```dart
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import '../domain/entities/sync_operation.dart';
import '../domain/repositories/remote_data_source.dart';

part 'remote_data_source_retrofit.g.dart';

@RestApi()
abstract class OdooApi {
  factory OdooApi(Dio dio, {String baseUrl}) = _OdooApi;

  @POST('/mica/sync/operation')
  Future<void> pushOperation(@Body() Map<String, dynamic> body);

  @GET('/mica/mines')
  Future<List<dynamic>> fetchMines();
}

class RetrofitRemoteDataSource implements RemoteDataSource {
  final OdooApi api;
  RetrofitRemoteDataSource(this.api);

  @override
  Future<void> pushOperation(SyncOperation op) {
    return api.pushOperation({
      'op_id': op.opId,
      'entity_type': op.entityType,
      'entity_id': op.entityId,
      'op_type': op.opType.name,
      'payload': op.payload,
    });
  }

  @override
  Future<List<RemoteMine>> fetchMines() async {
    final raw = await api.fetchMines();
    return raw.map((e) {
      final m = e as Map<String, dynamic>;
      return RemoteMine(
        m['id'].toString(), m['nom'] as String,
        (m['lat'] as num).toDouble(), (m['lon'] as num).toDouble(),
        (m['rayon_metres'] as num?)?.toDouble() ?? 20,
        m['district'] as String?, m['commune'] as String?, m['region'] as String?,
        m['actif'] as bool? ?? true,
      );
    }).toList();
  }
}
```

- [ ] **Step 3: Générer**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `remote_data_source_retrofit.g.dart` généré.

- [ ] **Step 4: Commit**

```bash
git add lib/core/network/dio_client.dart lib/features/sync/data/remote_data_source_retrofit.dart
git commit -m "feat(sync): RemoteDataSource Retrofit (Odoo REST)"
```

---

## Task 9: SyncEngine — push/retry/pull (TDD)

**Files:**
- Create: `lib/features/sync/data/sync_engine.dart`
- Test: append à `test/features/sync/sync_engine_test.dart`

- [ ] **Step 1: Écrire les tests qui échouent (avec fakes)**

Ajouter en bas de `test/features/sync/sync_engine_test.dart`:
```dart
// --- fakes ---
class _FakeRemote implements RemoteDataSource {
  final List<String> pushed = [];
  int failTimes;
  _FakeRemote({this.failTimes = 0});
  @override
  Future<void> pushOperation(SyncOperation op) async {
    if (failTimes > 0) { failTimes--; throw Exception('net'); }
    pushed.add(op.opId);
  }
  @override
  Future<List<RemoteMine>> fetchMines() async =>
      [RemoteMine('m1', 'Mine 1', -18.9, 47.5, 20, null, null, null, true)];
}

void mainEngine() {
  group('SyncEngine', () {
    late AppDatabase db; late DriftLocalSyncStore store;
    setUp(() { db = AppDatabase.memory(); store = DriftLocalSyncStore(db); });
    tearDown(() => db.close());

    test('push réussi marque synced', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      final remote = _FakeRemote();
      final engine = SyncEngine(store, remote, db);
      await engine.sync();
      expect(remote.pushed, ['a']);
      expect(await store.pending(), isEmpty);
    });

    test('push échoué garde pending + incrémente attempts', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      final engine = SyncEngine(store, _FakeRemote(failTimes: 1), db);
      await engine.sync();
      final p = await store.pending();
      expect(p.single.attempts, 1);
    });

    test('même opId rejoué = pas de doublon distant', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      final remote = _FakeRemote();
      final engine = SyncEngine(store, remote, db);
      await engine.sync();
      await engine.sync(); // rejeu : a déjà synced, plus pending
      expect(remote.pushed, ['a']);
    });

    test('pull insère les mines en local', () async {
      final engine = SyncEngine(store, _FakeRemote(), db);
      await engine.sync();
      final mines = await db.select(db.mines).get();
      expect(mines.single.id, 'm1');
    });
  });
}
```
Et appeler `mainEngine();` à la fin du `main()` existant (ou exécuter via `flutter test`).

- [ ] **Step 2: Lancer (échec attendu)**

Run: `flutter test test/features/sync/sync_engine_test.dart`
Expected: FAIL — `SyncEngine` non défini.

- [ ] **Step 3: Implémenter**

```dart
import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../domain/entities/sync_operation.dart';
import '../domain/repositories/local_sync_store.dart';
import '../domain/repositories/remote_data_source.dart';

class SyncEngine {
  final LocalSyncStore store;
  final RemoteDataSource remote;
  final AppDatabase db;
  SyncEngine(this.store, this.remote, this.db);

  /// Push FIFO des pending puis pull du référentiel mines.
  Future<void> sync() async {
    final ops = await store.pending();
    for (final op in ops) {
      await store.updateStatus(op.opId, SyncStatus.syncing);
      try {
        await remote.pushOperation(op);
        await store.updateStatus(op.opId, SyncStatus.synced);
      } catch (e) {
        await store.updateStatus(op.opId, SyncStatus.pending,
            attempts: op.attempts + 1,
            lastError: e.toString(),
            nextRetryAt: _backoff(op.attempts + 1));
      }
    }
    await _pullMines();
  }

  Future<void> _pullMines() async {
    final mines = await remote.fetchMines();
    await db.batch((b) {
      for (final m in mines) {
        b.insert(
          db.mines,
          MinesCompanion.insert(
            id: m.id, nom: m.nom, lat: m.lat, lon: m.lon,
            rayonMetres: Value(m.rayonMetres),
            district: Value(m.district), commune: Value(m.commune),
            region: Value(m.region), actif: Value(m.actif),
          ),
          onConflict: DoUpdate((_) => MinesCompanion.custom(), target: [db.mines.id]),
        );
      }
    });
  }

  DateTime _backoff(int attempts) {
    final seconds = (attempts * attempts * 5).clamp(5, 600);
    return DateTime.now().add(Duration(seconds: seconds));
  }
}
```

> Note : `onConflict` upsert simple sur l'id mine (référentiel push-dominant). Si l'API drift exige un companion d'update explicite, remplacer par `insertOnConflictUpdate`.

- [ ] **Step 4: Lancer (succès attendu)**

Run: `flutter test test/features/sync/sync_engine_test.dart`
Expected: PASS (store + engine).

- [ ] **Step 5: Commit**

```bash
git add lib/features/sync/data/sync_engine.dart test/features/sync/sync_engine_test.dart
git commit -m "feat(sync): SyncEngine push idempotent + retry + pull mines (TDD)"
```

---

## Task 10: Auth offline (TDD)

**Files:**
- Create: `lib/features/auth/domain/entities/fournisseur.dart`
- Create: `lib/features/auth/domain/repositories/auth_repository.dart`
- Create: `lib/features/auth/domain/usecases/login.dart`
- Create: `lib/features/auth/data/datasources/auth_local_ds.dart`
- Create: `lib/features/auth/data/repositories/auth_repository_impl.dart`
- Test: `test/features/auth/login_test.dart`

- [ ] **Step 1: Entité + contrat**

`fournisseur.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'fournisseur.freezed.dart';

@freezed
class Fournisseur with _$Fournisseur {
  const factory Fournisseur({
    required String id, required String nom, @Default(true) bool actif,
  }) = _Fournisseur;
}
```
`auth_repository.dart`:
```dart
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/fournisseur.dart';

abstract class AuthRepository {
  Future<Either<Failure, Fournisseur>> login(String identifiant);
  Future<Fournisseur?> currentSession();
}
```

- [ ] **Step 2: Usecase**

`login.dart`:
```dart
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/fournisseur.dart';
import '../repositories/auth_repository.dart';

class Login {
  final AuthRepository repo;
  Login(this.repo);
  Future<Either<Failure, Fournisseur>> call(String identifiant) {
    if (identifiant.trim().isEmpty) {
      return Future.value(left(const Failure.validation('Identifiant requis')));
    }
    return repo.login(identifiant.trim());
  }
}
```

- [ ] **Step 3: Écrire le test qui échoue**

`test/features/auth/login_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mica_fleet/core/error/failure.dart';
import 'package:mica_fleet/features/auth/domain/entities/fournisseur.dart';
import 'package:mica_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:mica_fleet/features/auth/domain/usecases/login.dart';

class _MockRepo extends Mock implements AuthRepository {}

void main() {
  late _MockRepo repo; late Login login;
  setUp(() { repo = _MockRepo(); login = Login(repo); });

  test('identifiant vide → ValidationFailure', () async {
    final r = await login('  ');
    expect(r.isLeft(), isTrue);
  });

  test('identifiant valide → délègue au repo', () async {
    when(() => repo.login('F001'))
        .thenAnswer((_) async => right(const Fournisseur(id: 'F001', nom: 'X')));
    final r = await login('F001');
    expect(r.isRight(), isTrue);
    verify(() => repo.login('F001')).called(1);
  });
}
```

- [ ] **Step 4: Lancer (échec attendu)**

Run: `flutter test test/features/auth/login_test.dart`
Expected: FAIL — symboles non générés / non définis.

- [ ] **Step 5: Datasource + repo impl + génération**

`auth_local_ds.dart`:
```dart
import 'package:drift/drift.dart';
import '../../../../core/db/app_database.dart';

class AuthLocalDataSource {
  final AppDatabase db;
  AuthLocalDataSource(this.db);

  Future<FournisseurData?> findById(String id) =>
      (db.select(db.fournisseurs)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> saveSession(String id, String nom) =>
      db.into(db.fournisseurs).insertOnConflictUpdate(
        FournisseursCompanion.insert(id: id, nom: nom, sessionToken: const Value('local')));
}
```
`auth_repository_impl.dart`:
```dart
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/fournisseur.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_ds.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthLocalDataSource local;
  AuthRepositoryImpl(this.local);

  @override
  Future<Either<Failure, Fournisseur>> login(String identifiant) async {
    final row = await local.findById(identifiant);
    if (row == null) return left(const Failure.auth('Fournisseur inconnu'));
    if (!row.actif) return left(const Failure.auth('Compte inactif'));
    await local.saveSession(row.id, row.nom);
    return right(Fournisseur(id: row.id, nom: row.nom, actif: row.actif));
  }

  @override
  Future<Fournisseur?> currentSession() async {
    final all = await local.db.select(local.db.fournisseurs).get();
    final s = all.where((f) => f.sessionToken != null).firstOrNull;
    return s == null ? null : Fournisseur(id: s.id, nom: s.nom, actif: s.actif);
  }
}
```
Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 6: Lancer (succès attendu)**

Run: `flutter test test/features/auth/login_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/features/auth/ test/features/auth/
git commit -m "feat(auth): login offline fournisseur (TDD)"
```

---

## Task 11: Services de capture (photo, GPS, hash, mock-location, OCR)

**Files:**
- Create: `lib/features/capture/domain/entities/captured_photo.dart`
- Create: `lib/features/capture/domain/services/capture_service.dart`
- Create: `lib/features/capture/domain/services/mock_location_guard.dart`
- Create: `lib/features/capture/domain/services/plate_ocr_service.dart`
- Create: `lib/features/capture/data/capture_service_impl.dart`
- Create: `lib/features/capture/data/mock_location_guard_impl.dart`
- Create: `lib/features/capture/data/plate_ocr_service_impl.dart`

- [ ] **Step 1: Entité + contrats**

`captured_photo.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'captured_photo.freezed.dart';

@freezed
class CapturedPhoto with _$CapturedPhoto {
  const factory CapturedPhoto({
    required String path, required String sha256,
    required double lat, required double lon, required double precision,
    required DateTime takenAt,
  }) = _CapturedPhoto;
}
```
`capture_service.dart`:
```dart
import '../entities/captured_photo.dart';
abstract class CaptureService {
  /// Prend une photo IN-APP (jamais galerie), compresse, calcule GPS + hash.
  Future<CapturedPhoto> capture();
}
```
`mock_location_guard.dart`:
```dart
abstract class MockLocationGuard {
  Future<bool> isMockLocationActive();
}
```
`plate_ocr_service.dart`:
```dart
abstract class PlateOcrService {
  /// Renvoie la plaque détectée ou null si illisible (→ saisie manuelle).
  Future<String?> readPlate(String imagePath);
}
```

- [ ] **Step 2: Implémentations**

`capture_service_impl.dart` (compression bas de gamme + hash) :
```dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';
import '../domain/entities/captured_photo.dart';
import '../domain/services/capture_service.dart';

class CameraCaptureService implements CaptureService {
  final CameraController controller; // ResolutionPreset.medium injecté
  CameraCaptureService(this.controller);

  @override
  Future<CapturedPhoto> capture() async {
    final file = await controller.takePicture();
    final bytes = await File(file.path).readAsBytes();
    final digest = sha256.convert(bytes).toString();
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    return CapturedPhoto(
      path: file.path, sha256: digest,
      lat: pos.latitude, lon: pos.longitude, precision: pos.accuracy,
      takenAt: DateTime.now(),
    );
  }
}
```
> ponytail: compression réelle (resize ~1600px) ajoutée si une image full-res cause OOM sur device de test — le `CameraController` créé en `ResolutionPreset.medium` couvre déjà le cas courant. Upgrade : `flutter_image_compress` si nécessaire.

`mock_location_guard_impl.dart` :
```dart
import 'package:geolocator/geolocator.dart';
import '../domain/services/mock_location_guard.dart';

class GeolocatorMockGuard implements MockLocationGuard {
  @override
  Future<bool> isMockLocationActive() async {
    final pos = await Geolocator.getCurrentPosition();
    return pos.isMocked; // geolocator expose isMocked sur Android
  }
}
```
`plate_ocr_service_impl.dart` :
```dart
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../domain/services/plate_ocr_service.dart';

class MlkitPlateOcrService implements PlateOcrService {
  @override
  Future<String?> readPlate(String imagePath) async {
    final recognizer = TextRecognizer();
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      final candidates = result.blocks
          .map((b) => b.text.replaceAll(RegExp(r'[^A-Z0-9]'), ''))
          .where((t) => t.length >= 5 && t.length <= 10);
      return candidates.isEmpty ? null : candidates.first;
    } finally {
      await recognizer.close();
    }
  }
}
```

- [ ] **Step 3: Générer**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `captured_photo.freezed.dart` généré.

- [ ] **Step 4: Commit**

```bash
git add lib/features/capture/
git commit -m "feat(capture): photo+gps+hash, mock-location guard, OCR plaque"
```

---

## Task 12: LoadingModule — entités, repo, usecases (TDD)

**Files:**
- Create: `lib/features/loading/domain/entities/chargement.dart`
- Create: `lib/features/loading/domain/entities/mine_chargement.dart`
- Create: `lib/features/loading/domain/repositories/loading_repository.dart`
- Create: `lib/features/loading/domain/usecases/create_chargement.dart`
- Create: `lib/features/loading/domain/usecases/add_mine_to_chargement.dart`
- Create: `lib/features/loading/domain/usecases/validate_chargement.dart`
- Create: `lib/features/loading/data/repositories/loading_repository_impl.dart`
- Test: `test/features/loading/create_chargement_test.dart`, `test/features/loading/validate_chargement_test.dart`

- [ ] **Step 1: Entités**

`mine_chargement.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../capture/domain/entities/captured_photo.dart';
part 'mine_chargement.freezed.dart';

@freezed
class MineChargement with _$MineChargement {
  const factory MineChargement({
    required String mineId,
    String? reference, String? couleur, double? quantiteEstimee,
    String? plaqueOcr, CapturedPhoto? photo,
  }) = _MineChargement;
}
```
`chargement.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'mine_chargement.dart';
part 'chargement.freezed.dart';

@freezed
class Chargement with _$Chargement {
  const Chargement._();
  const factory Chargement({
    required String id, required String fournisseurId,
    required DateTime dateCreation,
    @Default('brouillon') String statut,
    @Default(<MineChargement>[]) List<MineChargement> mines,
  }) = _Chargement;

  bool get peutAjouterMine => mines.length < 3;
}
```

- [ ] **Step 2: Contrat repo**

`loading_repository.dart`:
```dart
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/chargement.dart';
import '../entities/mine_chargement.dart';

abstract class LoadingRepository {
  /// Prochaine séquence annuelle pour l'ID MICA-YYYY-XXXX.
  Future<int> nextSequence(int year);
  Future<Either<Failure, Chargement>> persist(Chargement c);
}
```

- [ ] **Step 3: Usecases**

`create_chargement.dart`:
```dart
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/loading_id.dart';
import '../entities/chargement.dart';
import '../repositories/loading_repository.dart';

class CreateChargement {
  final LoadingRepository repo;
  CreateChargement(this.repo);

  Future<Either<Failure, Chargement>> call({
    required String fournisseurId, required DateTime now,
  }) async {
    final seq = await repo.nextSequence(now.year);
    final c = Chargement(
      id: buildLoadingId(now.year, seq),
      fournisseurId: fournisseurId, dateCreation: now,
    );
    return repo.persist(c);
  }
}
```
`add_mine_to_chargement.dart`:
```dart
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/chargement.dart';
import '../entities/mine_chargement.dart';

class AddMineToChargement {
  Either<Failure, Chargement> call(Chargement c, MineChargement m) {
    if (!c.peutAjouterMine) {
      return left(const Failure.validation('Maximum 3 mines par chargement'));
    }
    if (c.mines.any((x) => x.mineId == m.mineId)) {
      return left(const Failure.validation('Mine déjà ajoutée'));
    }
    return right(c.copyWith(mines: [...c.mines, m]));
  }
}
```
`validate_chargement.dart`:
```dart
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/chargement.dart';

class ValidateChargement {
  /// Niveau 1 (extrait Phase 1) : ≥1 mine, ≤3, photo + GPS présents par mine.
  Either<Failure, Chargement> call(Chargement c) {
    if (c.mines.isEmpty) {
      return left(const Failure.validation('Au moins une mine requise'));
    }
    if (c.mines.length > 3) {
      return left(const Failure.validation('Maximum 3 mines'));
    }
    for (final m in c.mines) {
      if (m.photo == null) {
        return left(Failure.validation('Photo manquante pour la mine ${m.mineId}'));
      }
    }
    return right(c.copyWith(statut: 'valide'));
  }
}
```

- [ ] **Step 4: Écrire les tests qui échouent**

`test/features/loading/create_chargement_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mica_fleet/core/error/failure.dart';
import 'package:mica_fleet/features/loading/domain/entities/chargement.dart';
import 'package:mica_fleet/features/loading/domain/repositories/loading_repository.dart';
import 'package:mica_fleet/features/loading/domain/usecases/create_chargement.dart';

class _MockRepo extends Mock implements LoadingRepository {}
class _FakeChargement extends Fake implements Chargement {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeChargement()));
  test('crée un chargement avec ID MICA-YYYY-XXXX', () async {
    final repo = _MockRepo();
    when(() => repo.nextSequence(2026)).thenAnswer((_) async => 7);
    when(() => repo.persist(any())).thenAnswer((i) async => right(i.positionalArguments[0] as Chargement));
    final uc = CreateChargement(repo);
    final r = await uc(fournisseurId: 'F001', now: DateTime(2026, 6, 22));
    expect(r.getRight().toNullable()!.id, 'MICA-2026-0007');
  });
}
```
`test/features/loading/validate_chargement_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/capture/domain/entities/captured_photo.dart';
import 'package:mica_fleet/features/loading/domain/entities/chargement.dart';
import 'package:mica_fleet/features/loading/domain/entities/mine_chargement.dart';
import 'package:mica_fleet/features/loading/domain/usecases/add_mine_to_chargement.dart';
import 'package:mica_fleet/features/loading/domain/usecases/validate_chargement.dart';

CapturedPhoto _p() => CapturedPhoto(
    path: 'x', sha256: 'h', lat: -18.9, lon: 47.5, precision: 5, takenAt: DateTime(2026));

void main() {
  final c0 = Chargement(id: 'MICA-2026-0001', fournisseurId: 'F001', dateCreation: DateTime(2026));

  test('refuse une 4e mine', () {
    final add = AddMineToChargement();
    var c = c0;
    for (final id in ['a', 'b', 'c']) {
      c = add(c, MineChargement(mineId: id, photo: _p())).getRight().toNullable()!;
    }
    final r = add(c, const MineChargement(mineId: 'd'));
    expect(r.isLeft(), isTrue);
  });

  test('validation échoue si photo manquante', () {
    final c = c0.copyWith(mines: const [MineChargement(mineId: 'a')]);
    expect(ValidateChargement()(c).isLeft(), isTrue);
  });

  test('validation réussit avec 1 mine + photo', () {
    final c = c0.copyWith(mines: [MineChargement(mineId: 'a', photo: _p())]);
    expect(ValidateChargement()(c).getRight().toNullable()!.statut, 'valide');
  });
}
```

- [ ] **Step 5: Lancer (échec attendu)**

Run: `flutter test test/features/loading/`
Expected: FAIL — symboles non générés.

- [ ] **Step 6: Repo impl + génération**

`loading_repository_impl.dart`:
```dart
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../../sync/domain/entities/sync_operation.dart';
import '../../../sync/domain/repositories/local_sync_store.dart';
import '../../domain/entities/chargement.dart';
import '../../domain/repositories/loading_repository.dart';

class LoadingRepositoryImpl implements LoadingRepository {
  final AppDatabase db;
  final LocalSyncStore syncStore;
  final _uuid = const Uuid();
  LoadingRepositoryImpl(this.db, this.syncStore);

  @override
  Future<int> nextSequence(int year) async {
    final rows = await db.select(db.chargements).get();
    final n = rows.where((c) => c.id.startsWith('MICA-$year-')).length;
    return n + 1;
  }

  @override
  Future<Either<Failure, Chargement>> persist(Chargement c) async {
    try {
      await db.transaction(() async {
        await db.into(db.chargements).insertOnConflictUpdate(ChargementsCompanion.insert(
          id: c.id, fournisseurId: c.fournisseurId, dateCreation: c.dateCreation,
          statut: Value(c.statut)));
        for (final m in c.mines) {
          await db.into(db.mineChargements).insert(MineChargementsCompanion.insert(
            chargementId: c.id, mineId: m.mineId,
            reference: Value(m.reference), couleur: Value(m.couleur),
            quantiteEstimee: Value(m.quantiteEstimee), plaqueOcr: Value(m.plaqueOcr),
            gpsLat: Value(m.photo?.lat), gpsLon: Value(m.photo?.lon),
            gpsPrecision: Value(m.photo?.precision),
            photoPath: Value(m.photo?.path), photoHash: Value(m.photo?.sha256),
            dateHeure: Value(m.photo?.takenAt)));
        }
      });
      // Journalise pour synchronisation
      await syncStore.enqueue(SyncOperation(
        opId: _uuid.v4(), entityType: 'chargement', entityId: c.id,
        opType: SyncOpType.create,
        payload: {
          'id': c.id, 'fournisseur_id': c.fournisseurId, 'statut': c.statut,
          'mines': c.mines.map((m) => {
            'mine_id': m.mineId, 'reference': m.reference, 'couleur': m.couleur,
            'quantite_estimee': m.quantiteEstimee, 'plaque': m.plaqueOcr,
            'lat': m.photo?.lat, 'lon': m.photo?.lon, 'hash': m.photo?.sha256,
          }).toList(),
        },
        createdAt: DateTime.now()));
      return right(c);
    } catch (e) {
      return left(Failure.database(e.toString()));
    }
  }
}
```
Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 7: Lancer (succès attendu)**

Run: `flutter test test/features/loading/`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/features/loading/ test/features/loading/
git commit -m "feat(loading): chargement multi-mines (≤3) + usecases + persist→sync (TDD)"
```

---

## Task 13: DI Riverpod + bootstrap app

**Files:**
- Create: `lib/core/di/providers.dart`
- Create: `lib/features/auth/presentation/providers/auth_provider.dart`
- Create: `lib/features/sync/presentation/sync_provider.dart`
- Create: `lib/features/loading/presentation/providers/loading_provider.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Providers racine**

`lib/core/di/providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import '../network/dio_client.dart';
import '../../features/sync/data/local_sync_store_impl.dart';
import '../../features/sync/data/remote_data_source_retrofit.dart';
import '../../features/sync/data/sync_engine.dart';
import '../../features/sync/domain/repositories/local_sync_store.dart';
import '../../features/sync/domain/repositories/remote_data_source.dart';

final dbProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('override in main'));

final localSyncStoreProvider = Provider<LocalSyncStore>(
    (ref) => DriftLocalSyncStore(ref.watch(dbProvider)));

final odooBaseUrlProvider = Provider<String>((ref) => 'https://odoo.example/api');

final remoteDataSourceProvider = Provider<RemoteDataSource>((ref) {
  final dio = buildDio(baseUrl: ref.watch(odooBaseUrlProvider));
  return RetrofitRemoteDataSource(OdooApi(dio));
});

final syncEngineProvider = Provider<SyncEngine>((ref) => SyncEngine(
      ref.watch(localSyncStoreProvider),
      ref.watch(remoteDataSourceProvider),
      ref.watch(dbProvider),
    ));
```

- [ ] **Step 2: main.dart (override db ouverte + connectivity sync)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'core/db/app_database.dart';
import 'core/di/providers.dart';
import 'features/auth/presentation/screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final container = ProviderContainer(overrides: [dbProvider.overrideWithValue(db)]);

  // Sync au retour réseau
  Connectivity().onConnectivityChanged.listen((status) {
    if (status.any((s) => s != ConnectivityResult.none)) {
      container.read(syncEngineProvider).sync();
    }
  });

  runApp(UncontrolledProviderScope(container: container, child: const MicaFleetApp()));
}

class MicaFleetApp extends StatelessWidget {
  const MicaFleetApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mica Fleet',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1F4E79), useMaterial3: true),
        home: const LoginScreen(),
      );
}
```

- [ ] **Step 3: Providers feature (auth, loading)**

`auth_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../data/datasources/auth_local_ds.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/usecases/login.dart';

final loginProvider = Provider<Login>((ref) =>
    Login(AuthRepositoryImpl(AuthLocalDataSource(ref.watch(dbProvider)))));
```
`loading_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../data/repositories/loading_repository_impl.dart';
import '../../domain/usecases/create_chargement.dart';

final loadingRepoProvider = Provider((ref) =>
    LoadingRepositoryImpl(ref.watch(dbProvider), ref.watch(localSyncStoreProvider)));
final createChargementProvider = Provider(
    (ref) => CreateChargement(ref.watch(loadingRepoProvider)));
```
`sync_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
final triggerSyncProvider = Provider((ref) => ref.watch(syncEngineProvider));
```

- [ ] **Step 4: Vérifier compilation**

Run: `flutter analyze`
Expected: pas d'erreur (warnings de lint tolérés).

- [ ] **Step 5: Commit**

```bash
git add lib/core/di/ lib/features/*/presentation/providers/ lib/features/sync/presentation/ lib/main.dart
git commit -m "feat(core): DI Riverpod + bootstrap + sync au retour réseau"
```

---

## Task 14: Écrans Login + Chargement (UI minimale)

**Files:**
- Create: `lib/features/auth/presentation/screens/login_screen.dart`
- Create: `lib/features/loading/presentation/screens/chargement_screen.dart`

- [ ] **Step 1: Login screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../../../loading/presentation/screens/chargement_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _ctrl = TextEditingController();
  String? _error; bool _loading = false;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    final r = await ref.read(loginProvider)(_ctrl.text);
    r.match(
      (f) => setState(() { _error = 'Échec connexion'; _loading = false; }),
      (fournisseur) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ChargementScreen(fournisseurId: fournisseur.id)));
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Connexion fournisseur')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextField(controller: _ctrl, decoration: const InputDecoration(
              labelText: 'Identifiant fournisseur', border: OutlineInputBorder())),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loading ? null : _submit,
              child: Text(_loading ? '...' : 'Se connecter')),
          ]),
        ),
      );
}
```

- [ ] **Step 2: Chargement screen (création + statut sync)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/loading_provider.dart';
import '../../../sync/presentation/sync_provider.dart';

class ChargementScreen extends ConsumerWidget {
  final String fournisseurId;
  const ChargementScreen({super.key, required this.fournisseurId});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Nouveau chargement'), actions: [
          IconButton(icon: const Icon(Icons.sync),
            onPressed: () => ref.read(triggerSyncProvider).sync()),
        ]),
        body: Center(
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Créer un chargement'),
            onPressed: () async {
              final r = await ref.read(createChargementProvider)(
                fournisseurId: fournisseurId, now: DateTime.now());
              r.match(
                (f) => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Erreur création'))),
                (c) => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Chargement ${c.id} créé'))),
              );
            },
          ),
        ),
      );
}
```

> Note : les écrans d'ajout de mine (caméra + GPS + OCR) et le détail mine sont des sous-tâches UI de cette feature ; squelette créé ici, capture branchée via `CaptureService` (Task 11). L'UI complète de saisie mine est détaillée dans le plan Phase 2 ou une itération UI dédiée.

- [ ] **Step 3: Vérifier compilation**

Run: `flutter analyze`
Expected: pas d'erreur.

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/presentation/screens/ lib/features/loading/presentation/screens/
git commit -m "feat(ui): écrans login + création chargement"
```

---

## Task 15: Vérification finale Phase 1

**Files:** aucun (validation)

- [ ] **Step 1: Lancer toute la suite de tests**

Run: `flutter test`
Expected: tous les tests PASS (geo, loading_id, sync, auth, loading).

- [ ] **Step 2: Analyse statique**

Run: `flutter analyze`
Expected: 0 erreur.

- [ ] **Step 3: Build APK debug (vérifie config Android bas de gamme)**

Run: `flutter build apk --debug --split-per-abi`
Expected: APK arm64-v8a et armeabi-v7a générés.

- [ ] **Step 4: Commit final + tag**

```bash
git add -A
git commit -m "chore: phase 1 terminée — fondation + collecte mine + sync engine"
git tag phase-1-mvp
```

---

## Notes de fin de Phase 1

**Couvert** : scaffold, Android bas de gamme (minSdk 23, ABI split), DB Drift chiffrée, Failure/Either, Haversine, ID MICA-YYYY-XXXX, référentiel mines (pull), auth offline, capture (photo+GPS+hash), mock-location guard, OCR plaque, chargement multi-mines (≤3) avec journalisation, SyncEngine op-based idempotent + retry + pull.

**Reporté à Phase 2 (plan séparé)** : transbordement dynamique 0..N, validation arrivée dépôt (chauffeur/permis/lot, GPS zone), ScoringEngine complet (Niveaux 1+2), délais d'acheminement + rappels, UI complète de saisie mine (caméra/OCR branchés bout en bout), SQLCipher key management durci, purge photos post-sync.
