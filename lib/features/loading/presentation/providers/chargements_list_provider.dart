import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';

/// Ligne d'historique d'un chargement.
class ChargementListItem {
  final String id;
  final DateTime date;
  final String statut;
  final int nbMines;
  final int? score; // null tant que pas arrivé au dépôt
  final bool arrive;
  const ChargementListItem({
    required this.id,
    required this.date,
    required this.statut,
    required this.nbMines,
    required this.score,
    required this.arrive,
  });
}

/// Historique des chargements (plus récent d'abord), avec score d'arrivée.
final chargementsListProvider =
    FutureProvider.autoDispose<List<ChargementListItem>>((ref) async {
  final db = ref.watch(dbProvider);
  final chs = await (db.select(db.chargements)
        ..orderBy([(t) => OrderingTerm.desc(t.dateCreation)]))
      .get();
  final items = <ChargementListItem>[];
  for (final c in chs) {
    final nb = (await (db.select(db.mineChargements)
              ..where((t) => t.chargementId.equals(c.id)))
            .get())
        .length;
    final arr = await (db.select(db.arriveesDepot)
          ..where((t) => t.chargementId.equals(c.id)))
        .getSingleOrNull();
    items.add(ChargementListItem(
      id: c.id,
      date: c.dateCreation,
      statut: c.statut,
      nbMines: nb,
      score: arr?.scoreTracabilite,
      arrive: arr != null,
    ));
  }
  return items;
});
