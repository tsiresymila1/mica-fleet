import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/trip/data/trip_tracker.dart';

void main() {
  late AppDatabase db;
  late TripTracker tracker;

  setUp(() async {
    db = AppDatabase.memory();
    tracker = TripTracker(db);
    await db.into(db.chargements).insert(ChargementsCompanion.insert(
        id: 'C1', fournisseurId: 'F001', dateCreation: DateTime(2026)));
  });
  tearDown(() => db.close());

  test('ignore un point trop proche (<20m), garde les éloignés', () async {
    await tracker.recordPoint('C1', -18.90000, 47.5, simule: true);
    // ~5 m plus loin → ignoré
    await tracker.recordPoint('C1', -18.90004, 47.5, simule: true);
    // ~50 m plus loin → gardé
    await tracker.recordPoint('C1', -18.90050, 47.5, simule: true);
    final pts = await db.select(db.trajetPoints).get();
    expect(pts.length, 2);
  });
}
