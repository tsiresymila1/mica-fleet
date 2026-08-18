import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import 'chargement_detail_provider.dart' show SyncEtat, syncEtatFrom;

/// Ligne d'historique : un LOT (unité de traçabilité et de score).
class LotListItem {
  final String id; // ex. MICA-2026-0007-L1
  final String sessionId;
  final String mineId;
  final String mineName;
  final String? couleur;
  final double? tonnage;
  final DateTime date;
  final String statut; // en_cours / arrive
  final int? score;
  final bool arrive;
  final SyncEtat sync;
  final String validationStatus;
  final String? validationReason;
  final String? serverReference;
  final bool remoteOnly;
  const LotListItem({
    required this.id,
    required this.sessionId,
    required this.mineId,
    required this.mineName,
    required this.couleur,
    required this.tonnage,
    required this.date,
    required this.statut,
    required this.score,
    required this.arrive,
    required this.sync,
    required this.validationStatus,
    required this.validationReason,
    required this.serverReference,
    required this.remoteOnly,
  });
}

String normalizeValidationStatus(String status) {
  return switch (status.trim().toLowerCase()) {
    'draft' => 'draft',
    'in_progress' || 'en_cours' => 'draft',
    'validated' || 'validé' || 'valide' => 'validated',
    'rejected' || 'rejeté' || 'rejete' => 'rejected',
    _ => 'draft',
  };
}

/// Historique des lots (plus récent d'abord), avec score.
final lotsListProvider = FutureProvider.autoDispose<List<LotListItem>>((
  ref,
) async {
  final db = ref.watch(dbProvider);
  final sessions = await db.select(db.chargements).get();
  final dates = {for (final s in sessions) s.id: s.dateCreation};
  final lots = await db.select(db.lots).get();
  final mines = await db.select(db.mines).get();
  final mineNames = {for (final mine in mines) mine.id: mine.nom};
  final items = <LotListItem>[];
  for (final l in lots) {
    final arr = await (db.select(
      db.arriveesDepot,
    )..where((t) => t.lotId.equals(l.id))).getSingleOrNull();
    final op =
        await (db.select(db.syncQueue)..where(
              (t) => t.entityId.equals(l.id) & t.entityType.equals('lot'),
            ))
            .getSingleOrNull();
    items.add(
      LotListItem(
        id: l.id,
        sessionId: l.sessionId,
        mineId: l.mineId,
        mineName: mineNames[l.mineId] ?? l.mineId,
        couleur: l.couleur,
        tonnage: l.quantiteEstimee,
        date: dates[l.sessionId] ?? DateTime.fromMillisecondsSinceEpoch(0),
        statut: l.statut,
        score: l.score ?? arr?.scoreTracabilite,
        arrive: arr != null,
        sync: l.remoteOnly
            ? SyncEtat.synchronise
            : syncEtatFrom(op?.status, l.photosUploaded),
        validationStatus: normalizeValidationStatus(l.validationStatus),
        validationReason: l.validationReason,
        serverReference: l.serverReference,
        remoteOnly: l.remoteOnly,
      ),
    );
  }
  items.sort((a, b) => b.date.compareTo(a.date));
  return items;
});
