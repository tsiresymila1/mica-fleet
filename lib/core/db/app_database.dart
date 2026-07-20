import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

@DataClassName('FournisseurRow')
class Fournisseurs extends Table {
  TextColumn get id => text()();
  TextColumn get nom => text()();
  BoolColumn get actif => boolean().withDefault(const Constant(true))();
  TextColumn get sessionToken => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MineRow')
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
  @override
  Set<Column> get primaryKey => {id};
}

/// Session de collecte : les lots partis ensemble (regroupement pratique).
/// L'unité de traçabilité est le LOT, pas la session.
@DataClassName('ChargementRow')
class Chargements extends Table {
  TextColumn get id => text()(); // MICA-YYYY-XXXX
  TextColumn get fournisseurId => text()();
  DateTimeColumn get dateCreation => dateTime()();
  TextColumn get statut => text().withDefault(const Constant('brouillon'))();
  TextColumn get lotReference => text().nullable()(); // regroupement Odoo (opt.)
  @override
  Set<Column> get primaryKey => {id};
}

/// LOT = chargement d'UNE mine. Indivisible, unité de traçabilité et de score.
@DataClassName('LotRow')
class Lots extends Table {
  TextColumn get id => text()(); // ex. MICA-2026-0007-L1
  TextColumn get sessionId => text().references(Chargements, #id)();
  TextColumn get mineId => text().references(Mines, #id)();
  TextColumn get reference => text().nullable()();
  TextColumn get couleur => text().nullable()();
  RealColumn get quantiteEstimee => real().nullable()(); // figée au départ
  TextColumn get plaqueDepart => text().nullable()();
  RealColumn get gpsLat => real().nullable()();
  RealColumn get gpsLon => real().nullable()();
  RealColumn get gpsPrecision => real().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get photoHash => text().nullable()();
  DateTimeColumn get dateHeure => dateTime().nullable()();
  TextColumn get statut => text().withDefault(const Constant('en_cours'))();
  TextColumn get deviceUuid => text().nullable()(); // idempotence sync (par lot)
  IntColumn get score => integer().nullable()();
  BoolColumn get photosUploaded =>
      boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncQueueRow')
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
  IntColumn get odooId => integer().nullable()(); // id du record créé côté Odoo
  DateTimeColumn get syncedAt => dateTime().nullable()();
  TextColumn get agentLogin => text().nullable()(); // fournisseur (submit)
  RealColumn get gpsLat => real().nullable()();
  RealColumn get gpsLon => real().nullable()();
  RealColumn get gpsAccuracy => real().nullable()();
  @override
  Set<Column> get primaryKey => {opId};
}

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

/// Transbordement PAR LOT : quel camion porte ce lot à chaque étape.
@DataClassName('TransbordementRow')
class Transbordements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get lotId => text().references(Lots, #id)();
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

/// Arrivée PAR LOT (un lot arrive en un seul camion).
@DataClassName('ArriveeDepotRow')
class ArriveesDepot extends Table {
  TextColumn get lotId => text().references(Lots, #id)();
  TextColumn get depotId => text().references(Depots, #id)();
  TextColumn get chauffeur => text()();
  TextColumn get numPermis => text()();
  TextColumn get photoPermisPath => text().nullable()();
  TextColumn get numLot => text()();
  RealColumn get gpsLat => real()();
  RealColumn get gpsLon => real()();
  TextColumn get photoArriveePath => text().nullable()();
  TextColumn get plaqueArrivee => text().nullable()();
  BoolColumn get plaqueCoherente => boolean().withDefault(const Constant(true))();
  IntColumn get scoreTracabilite => integer().nullable()();
  TextColumn get statutGps => text()(); // valide / hors_zone
  @override
  Set<Column> get primaryKey => {lotId};
}

@DataClassName('JournalEntryRow')
class JournalEntries extends Table {
  IntColumn get seq => integer()(); // assigné séquentiellement (chaînage)
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get dataHash => text()();
  TextColumn get prevHash => text()();
  TextColumn get entryHash => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {seq};
}

@DataClassName('TrajetPointRow')
class TrajetPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get chargementId => text().references(Chargements, #id)();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  DateTimeColumn get capturedAt => dateTime()();
  BoolColumn get simule => boolean().withDefault(const Constant(false))();
}

@DriftDatabase(tables: [
  Fournisseurs,
  Mines,
  Chargements,
  Lots,
  SyncQueue,
  Depots,
  Transbordements,
  ArriveesDepot,
  JournalEntries,
  TrajetPoints,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  @override
  int get schemaVersion => 12;

  // ponytail: migration destructive (recrée tout) — OK en pré-prod/démo.
  // Avant la prod réelle, remplacer par des migrations pas-à-pas qui
  // préservent les données (m.addColumn / m.createTable par version).
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          for (final table in allTables) {
            await m.deleteTable(table.actualTableName);
          }
          await m.createAll();
        },
      );

  static Future<AppDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'mica_fleet.db'));
    return AppDatabase(NativeDatabase(file));
  }

  /// Variante in-memory pour les tests.
  static AppDatabase memory() => AppDatabase(NativeDatabase.memory());
}
