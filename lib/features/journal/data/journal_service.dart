import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../domain/journal_hash.dart';

/// Journal immuable append-only : chaque événement métier est haché et chaîné
/// au précédent (prevHash). Toute altération casse la chaîne (cf. verifyChain).
class JournalService {
  final AppDatabase db;
  JournalService(this.db);

  Future<void> append(
      String entityType, String entityId, String payload) async {
    final dataHash = computeDataHash(payload);
    final last = await (db.select(db.journalEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.seq)])
          ..limit(1))
        .getSingleOrNull();
    final seq = (last?.seq ?? 0) + 1;
    final prev = last?.entryHash ?? genesisHash;
    final entryHash = computeEntryHash(seq, prev, dataHash);
    await db.into(db.journalEntries).insert(JournalEntriesCompanion.insert(
          seq: Value(seq),
          entityType: entityType,
          entityId: entityId,
          dataHash: dataHash,
          prevHash: prev,
          entryHash: entryHash,
          createdAt: DateTime.now(),
        ));
  }

  /// Vérifie l'intégrité complète du journal local.
  Future<bool> verify() async {
    final rows = await db.select(db.journalEntries).get();
    final links = rows
        .map((r) => JournalLink(
            seq: r.seq,
            prevHash: r.prevHash,
            dataHash: r.dataHash,
            entryHash: r.entryHash))
        .toList();
    return verifyChain(links);
  }
}
