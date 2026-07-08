import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/di/providers.dart';
import '../data/trip_tracker.dart';

/// Singleton de suivi de trajet (garde l'abonnement GPS actif).
final tripTrackerProvider =
    Provider<TripTracker>((ref) => TripTracker(ref.watch(dbProvider)));

/// Points du trajet d'un chargement (pour la carte).
final trajetPointsProvider =
    FutureProvider.autoDispose.family<List<LatLng>, String>((ref, id) async {
  final db = ref.watch(dbProvider);
  final rows = await (db.select(db.trajetPoints)
        ..where((t) => t.chargementId.equals(id))
        ..orderBy([(t) => OrderingTerm.asc(t.capturedAt)]))
      .get();
  return rows.map((r) => LatLng(r.lat, r.lon)).toList();
});
