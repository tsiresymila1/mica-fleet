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
  TextColumn get fokontany => text().nullable()();
  TextColumn get commune => text().nullable()();
  TextColumn get region => text().nullable()();
  BoolColumn get actif => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

/// Référentiel des communes chargé après connexion et conservé hors ligne.
@DataClassName('CommuneRow')
class Communes extends Table {
  IntColumn get id => integer()();
  TextColumn get nom => text()();
  TextColumn get district => text().nullable()();
  BoolColumn get actif => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

/// Proposition de mine créée sur le terrain. Elle reste séparée du référentiel
/// [Mines] tant que le serveur ne l'a pas approuvée.
@DataClassName('MineSubmissionRow')
class MineSubmissions extends Table {
  TextColumn get payloadId => text()(); // UUID envoyé dans payload.id
  TextColumn get deviceUuid => text()(); // idempotence submit + photos
  TextColumn get nom => text()();
  IntColumn get communeId => integer().nullable()();
  TextColumn get agentLogin => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('local_pending'))();
  IntColumn get serverId => integer().nullable()();
  TextColumn get approvedMineId => text().nullable()();
  TextColumn get rejectionReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {payloadId};
}

/// Preuves photographiques d'une proposition. Une ligne = un upload unitaire.
@DataClassName('MineSubmissionPhotoRow')
class MineSubmissionPhotos extends Table {
  TextColumn get payloadId => text().references(MineSubmissions, #payloadId)();
  TextColumn get key => text()(); // position_1, position_2, ...
  TextColumn get path => text()();
  TextColumn get hash => text()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get gpsAccuracy => real()();
  RealColumn get headingDegrees => real().nullable()();
  RealColumn get headingAccuracy => real().nullable()();
  TextColumn get headingReference => text().nullable()();
  DateTimeColumn get capturedAt => dateTime()();
  BoolColumn get uploaded => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {payloadId, key};
}

/// Session de collecte : les lots partis ensemble (regroupement pratique).
/// L'unité de traçabilité est le LOT, pas la session.
@DataClassName('ChargementRow')
class Chargements extends Table {
  TextColumn get id => text()(); // MICA-YYYY-XXXX
  TextColumn get sessionUuid => text().nullable()(); // UUID exposé à l'API
  TextColumn get fournisseurId => text()();
  DateTimeColumn get dateCreation => dateTime()();
  TextColumn get statut => text().withDefault(const Constant('brouillon'))();
  TextColumn get lotReference =>
      text().nullable()(); // regroupement Odoo (opt.)
  @override
  Set<Column> get primaryKey => {id};
}

/// LOT = chargement d'UNE mine. Indivisible, unité de traçabilité et de score.
@DataClassName('LotRow')
class Lots extends Table {
  TextColumn get id => text()(); // ex. MICA-2026-0007-L1
  TextColumn get payloadUuid =>
      text().nullable()(); // payload.id exposé à l'API
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
  RealColumn get photoHeadingDegrees => real().nullable()();
  RealColumn get photoHeadingAccuracy => real().nullable()();
  TextColumn get photoHeadingReference => text().nullable()();
  DateTimeColumn get dateHeure => dateTime().nullable()();
  TextColumn get statut => text().withDefault(const Constant('en_cours'))();
  TextColumn get deviceUuid =>
      text().nullable()(); // idempotence sync (par lot)
  IntColumn get score => integer().nullable()();
  BoolColumn get photosUploaded =>
      boolean().withDefault(const Constant(false))();
  // Clés des fichiers déjà confirmés par Odoo. Les fichiers restent conservés
  // pour l'historique visuel ; cette liste évite les doublons à la reprise.
  TextColumn get uploadedPhotoKeys =>
      text().withDefault(const Constant('[]'))();
  IntColumn get photoSchemaVersion =>
      integer().withDefault(const Constant(1))();
  TextColumn get validationStatus =>
      text().withDefault(const Constant('draft'))();
  TextColumn get validationReason => text().nullable()();
  TextColumn get serverReference => text().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  BoolColumn get remoteOnly => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

/// Photos de traçabilité v2. Une ligne représente un rôle d'une étape d'un lot.
@DataClassName('LotTraceabilityPhotoRow')
class LotTraceabilityPhotos extends Table {
  TextColumn get lotId => text().references(Lots, #id)();
  TextColumn get stage => text()();
  IntColumn get stageOrder => integer().withDefault(const Constant(0))();
  TextColumn get role => text()();
  TextColumn get path => text()();
  TextColumn get hash => text()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get gpsAccuracy => real()();
  DateTimeColumn get capturedAt => dateTime()();
  RealColumn get headingDegrees => real().nullable()();
  RealColumn get headingAccuracy => real().nullable()();
  TextColumn get headingReference => text().nullable()();
  @override
  Set<Column> get primaryKey => {lotId, stage, stageOrder, role};
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
  RealColumn get photoDechargeHeadingDegrees => real().nullable()();
  RealColumn get photoDechargeHeadingAccuracy => real().nullable()();
  TextColumn get photoDechargeHeadingReference => text().nullable()();
  TextColumn get photoRechargePath => text().nullable()();
  RealColumn get photoRechargeHeadingDegrees => real().nullable()();
  RealColumn get photoRechargeHeadingAccuracy => real().nullable()();
  TextColumn get photoRechargeHeadingReference => text().nullable()();
}

/// Arrivée PAR LOT (un lot arrive en un seul camion).
@DataClassName('ArriveeDepotRow')
class ArriveesDepot extends Table {
  TextColumn get lotId => text().references(Lots, #id)();
  TextColumn get depotId => text().nullable().references(Depots, #id)();
  TextColumn get chauffeur => text()();
  TextColumn get numPermis => text()();
  TextColumn get photoPermisPath => text().nullable()();
  RealColumn get photoPermisHeadingDegrees => real().nullable()();
  RealColumn get photoPermisHeadingAccuracy => real().nullable()();
  TextColumn get photoPermisHeadingReference => text().nullable()();
  TextColumn get numLot => text()();
  RealColumn get gpsLat => real()();
  RealColumn get gpsLon => real()();
  TextColumn get photoArriveePath => text().nullable()();
  RealColumn get photoArriveeHeadingDegrees => real().nullable()();
  RealColumn get photoArriveeHeadingAccuracy => real().nullable()();
  TextColumn get photoArriveeHeadingReference => text().nullable()();
  TextColumn get plaqueArrivee => text().nullable()();
  BoolColumn get plaqueCoherente =>
      boolean().withDefault(const Constant(true))();
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

@DriftDatabase(
  tables: [
    Fournisseurs,
    Mines,
    Communes,
    MineSubmissions,
    MineSubmissionPhotos,
    Chargements,
    Lots,
    LotTraceabilityPhotos,
    SyncQueue,
    Depots,
    Transbordements,
    ArriveesDepot,
    JournalEntries,
    TrajetPoints,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  @override
  int get schemaVersion => 20;

  // Les installations historiques antérieures à v12 sont recréées. Depuis
  // v12, chaque évolution doit utiliser une migration additive et préserver
  // la file offline ainsi que les identifiants d'idempotence.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Les versions historiques restent pré-prod et sont recréées. À
      // partir de v12, les migrations doivent préserver les données.
      if (from < 12) {
        for (final table in allTables) {
          await m.deleteTable(table.actualTableName);
        }
        await m.createAll();
        return;
      }
      if (from < 13) {
        await m.addColumn(chargements, chargements.sessionUuid);
        await m.addColumn(lots, lots.payloadUuid);
      }
      if (from < 14) {
        await m.createTable(mineSubmissions);
        await m.createTable(mineSubmissionPhotos);
      }
      if (from < 15) {
        await m.addColumn(lots, lots.uploadedPhotoKeys);
      }
      // Si la table vient d'être créée par la migration v14, elle possède
      // déjà les colonnes du schéma courant.
      if (from >= 14 && from < 16) {
        await m.addColumn(
          mineSubmissionPhotos,
          mineSubmissionPhotos.headingDegrees,
        );
        await m.addColumn(
          mineSubmissionPhotos,
          mineSubmissionPhotos.headingAccuracy,
        );
        await m.addColumn(
          mineSubmissionPhotos,
          mineSubmissionPhotos.headingReference,
        );
      }
      if (from >= 12 && from < 17) {
        await m.addColumn(lots, lots.photoHeadingDegrees);
        await m.addColumn(lots, lots.photoHeadingAccuracy);
        await m.addColumn(lots, lots.photoHeadingReference);
        await m.addColumn(
          transbordements,
          transbordements.photoDechargeHeadingDegrees,
        );
        await m.addColumn(
          transbordements,
          transbordements.photoDechargeHeadingAccuracy,
        );
        await m.addColumn(
          transbordements,
          transbordements.photoDechargeHeadingReference,
        );
        await m.addColumn(
          transbordements,
          transbordements.photoRechargeHeadingDegrees,
        );
        await m.addColumn(
          transbordements,
          transbordements.photoRechargeHeadingAccuracy,
        );
        await m.addColumn(
          transbordements,
          transbordements.photoRechargeHeadingReference,
        );
        await m.addColumn(
          arriveesDepot,
          arriveesDepot.photoPermisHeadingDegrees,
        );
        await m.addColumn(
          arriveesDepot,
          arriveesDepot.photoPermisHeadingAccuracy,
        );
        await m.addColumn(
          arriveesDepot,
          arriveesDepot.photoPermisHeadingReference,
        );
        await m.addColumn(
          arriveesDepot,
          arriveesDepot.photoArriveeHeadingDegrees,
        );
        await m.addColumn(
          arriveesDepot,
          arriveesDepot.photoArriveeHeadingAccuracy,
        );
        await m.addColumn(
          arriveesDepot,
          arriveesDepot.photoArriveeHeadingReference,
        );
      }
      if (from >= 12 && from < 18) {
        await m.createTable(communes);
      }
      // Une table créée par la migration v14 possède déjà toutes les colonnes
      // du schéma courant. Seules les installations v14+ ont besoin de cet
      // ajout explicite.
      if (from >= 14 && from < 18) {
        await m.addColumn(mineSubmissions, mineSubmissions.communeId);
      }
      if (from >= 12 && from < 19) {
        await m.addColumn(lots, lots.photoSchemaVersion);
        await m.createTable(lotTraceabilityPhotos);
      }
      if (from >= 12 && from < 20) {
        await m.addColumn(mines, mines.fokontany);
        await m.addColumn(lots, lots.validationStatus);
        await m.addColumn(lots, lots.validationReason);
        await m.addColumn(lots, lots.serverReference);
        await m.addColumn(lots, lots.serverUpdatedAt);
        await m.addColumn(lots, lots.remoteOnly);
        // Le dépôt est désormais résolu par le backend depuis arrival.gps.
        // La migration conserve les anciennes valeurs mais autorise null pour
        // les nouvelles arrivées.
        await m.alterTable(TableMigration(arriveesDepot));
      }
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
