import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';

/// Ligne d'historique : un LOT (unité de traçabilité et de score).
class LotListItem {
  final String id; // ex. MICA-2026-0007-L1
  final String sessionId;
  final String mineId;
  final String? couleur;
  final DateTime date;
  final String statut; // en_cours / arrive
  final int? score;
  final bool arrive;
  const LotListItem({
    required this.id,
    required this.sessionId,
    required this.mineId,
    required this.couleur,
    required this.date,
    required this.statut,
    required this.score,
    required this.arrive,
  });
}

/// Historique des lots (plus récent d'abord), avec score.
final lotsListProvider =
    FutureProvider.autoDispose<List<LotListItem>>((ref) async {
  final db = ref.watch(dbProvider);
  final sessions = await db.select(db.chargements).get();
  final dates = {for (final s in sessions) s.id: s.dateCreation};
  final lots = await db.select(db.lots).get();
  final items = <LotListItem>[];
  for (final l in lots) {
    final arr = await (db.select(db.arriveesDepot)
          ..where((t) => t.lotId.equals(l.id)))
        .getSingleOrNull();
    items.add(LotListItem(
      id: l.id,
      sessionId: l.sessionId,
      mineId: l.mineId,
      couleur: l.couleur,
      date: dates[l.sessionId] ?? DateTime.fromMillisecondsSinceEpoch(0),
      statut: l.statut,
      score: l.score ?? arr?.scoreTracabilite,
      arrive: arr != null,
    ));
  }
  items.sort((a, b) => b.date.compareTo(a.date));
  return items;
});
