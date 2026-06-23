import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/db/dev_seed.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('seedIfEmpty insère fournisseur, mines et dépôts', () async {
    await DevSeeder(db).seedIfEmpty();
    expect((await db.select(db.fournisseurs).get()).length, 1);
    expect((await db.select(db.mines).get()).length, 3);
    expect((await db.select(db.depots).get()).length, 2);
  });

  test('seedIfEmpty est idempotent', () async {
    final seeder = DevSeeder(db);
    await seeder.seedIfEmpty();
    await seeder.seedIfEmpty();
    expect((await db.select(db.mines).get()).length, 3);
  });
}
