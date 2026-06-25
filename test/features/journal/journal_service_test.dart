import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/journal/data/journal_service.dart';

void main() {
  late AppDatabase db;
  late JournalService journal;
  setUp(() {
    db = AppDatabase.memory();
    journal = JournalService(db);
  });
  tearDown(() => db.close());

  test('append chaîne et verify valide', () async {
    await journal.append('chargement', 'C1', '{"a":1}');
    await journal.append('arrivee_depot', 'C1', '{"b":2}');
    expect(await journal.verify(), isTrue);
    expect((await db.select(db.journalEntries).get()).length, 2);
  });

  test('verify détecte une altération directe en base', () async {
    await journal.append('chargement', 'C1', '{"a":1}');
    await journal.append('arrivee_depot', 'C1', '{"b":2}');
    // Falsifie le contenu du 1er maillon sans recalculer le hash
    await (db.update(db.journalEntries)..where((t) => t.seq.equals(1)))
        .write(const JournalEntriesCompanion(dataHash: Value('HACK')));
    expect(await journal.verify(), isFalse);
  });
}
