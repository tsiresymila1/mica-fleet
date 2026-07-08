import 'dart:async';
import 'package:drift/drift.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/geo.dart';
import '../../../core/utils/location.dart';

/// Suit le parcours du téléphone pendant le transport et enregistre les points
/// GPS espacés de plus de [seuilMetres]. Fonctionne en arrière-plan via un
/// service de premier plan (notification permanente).
class TripTracker {
  final AppDatabase db;
  TripTracker(this.db);

  static const double seuilMetres = 20;

  StreamSubscription<Position>? _sub;
  String? _chargementId;
  double? _lastLat, _lastLon;

  bool get isTracking => _sub != null;
  String? get currentChargement => _chargementId;

  Future<void> start(String chargementId) async {
    if (_sub != null) return;
    await ensureLocationReady();
    _chargementId = chargementId;
    // Reprend le dernier point connu pour le filtrage.
    final last = await (db.select(db.trajetPoints)
          ..where((t) => t.chargementId.equals(chargementId))
          ..orderBy([(t) => OrderingTerm.desc(t.capturedAt)])
          ..limit(1))
        .getSingleOrNull();
    _lastLat = last?.lat;
    _lastLon = last?.lon;

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: seuilMetres.toInt(),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Mica — suivi du trajet',
        notificationText: 'Enregistrement du parcours en cours',
        enableWakeLock: true,
      ),
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen((p) {
      recordPoint(chargementId, p.latitude, p.longitude);
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _chargementId = null;
    _lastLat = _lastLon = null;
  }

  /// Enregistre un point si sa distance au dernier point retenu dépasse le seuil.
  /// Utilisé par le flux GPS réel et par le simulateur.
  Future<void> recordPoint(String chargementId, double lat, double lon,
      {bool simule = false, DateTime? at}) async {
    if (_lastLat != null &&
        haversineMeters(_lastLat!, _lastLon!, lat, lon) < seuilMetres) {
      return; // trop proche → ignoré
    }
    _lastLat = lat;
    _lastLon = lon;
    await db.into(db.trajetPoints).insert(TrajetPointsCompanion.insert(
          chargementId: chargementId,
          lat: lat,
          lon: lon,
          capturedAt: at ?? DateTime.now(),
          simule: Value(simule),
        ));
  }
}
