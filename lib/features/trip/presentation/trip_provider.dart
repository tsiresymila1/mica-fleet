import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/di/providers.dart';
import '../../../core/config/app_config.dart';
import '../data/trip_tracker.dart';
import '../data/background_trip_service.dart';

/// Singleton de suivi de trajet (garde l'abonnement GPS actif).
final tripTrackerProvider = Provider<TripTracker>((ref) {
  final tracker = TripTracker(
    ref.watch(dbProvider),
    backgroundService: Platform.isAndroid && !AppConfig.demo
        ? const MethodChannelBackgroundTripService()
        : null,
  );
  ref.onDispose(() => unawaited(tracker.dispose()));
  return tracker;
});

/// Points du trajet d'un chargement (pour la carte).
final trajetPointsProvider = StreamProvider.autoDispose
    .family<List<LatLng>, String>((ref, id) {
      final db = ref.watch(dbProvider);
      return (db.select(db.trajetPoints)
            ..where((t) => t.chargementId.equals(id))
            ..orderBy([(t) => OrderingTerm.asc(t.capturedAt)]))
          .watch()
          .map((rows) => rows.map((r) => LatLng(r.lat, r.lon)).toList());
    });
