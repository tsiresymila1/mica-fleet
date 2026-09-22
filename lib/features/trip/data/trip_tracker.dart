import 'dart:async';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/location.dart';
import '../domain/trip_gps_filter.dart';
import 'background_trip_service.dart';

/// Suit le parcours du téléphone pendant le transport et enregistre les points
/// GPS confirmés espacés d'au moins [seuilMetres]. Fonctionne en arrière-plan via un
/// service de premier plan (notification permanente).
class TripTracker {
  final AppDatabase db;
  final Future<void> Function() _ensureReady;
  final Stream<Position> Function(LocationSettings) _positions;
  final BackgroundTripService? _backgroundService;
  TripTracker(
    this.db, {
    Future<void> Function()? ensureReady,
    Stream<Position> Function(LocationSettings)? positions,
    BackgroundTripService? backgroundService,
  }) : _ensureReady = ensureReady ?? ensureLocationReady,
       _backgroundService = backgroundService,
       _positions =
           positions ??
           ((settings) =>
               Geolocator.getPositionStream(locationSettings: settings));

  static const double seuilMetres = 8;
  static const double maximumAccuracyMeters = 25;

  StreamSubscription<Position>? _sub;
  String? _chargementId;
  final _filter = TripGpsFilter();
  TripGpsSample? _lastSaved;
  Future<void> _writes = Future.value();
  Timer? _nativeRefresh;
  bool _nativeTracking = false;

  bool get isTracking => _sub != null || _nativeTracking;
  String? get currentChargement => _chargementId;

  /// Restaure le service après un redémarrage de Flutter. La base, et non un
  /// état d'écran, décide si une session doit encore être suivie.
  Future<void> restoreFromDatabase() async {
    final row = await db
        .customSelect(
          'SELECT l.session_id AS session_id FROM lots l '
          'LEFT JOIN arrivees_depot a ON a.lot_id = l.id '
          'WHERE a.lot_id IS NULL AND l.remote_only = 0 '
          'ORDER BY l.date_heure DESC LIMIT 1',
          readsFrom: {db.lots, db.arriveesDepot},
        )
        .getSingleOrNull();
    final id = row?.read<String>('session_id');
    if (id == null || id.isEmpty) {
      if (await _backgroundService?.isRunning() == true) await stop();
      return;
    }
    await start(id);
  }

  Future<void> start(String chargementId) async {
    if (_sub != null) return;
    await _ensureReady();
    _chargementId = chargementId;
    final backgroundService = _backgroundService;
    if (backgroundService != null) {
      await backgroundService.start(chargementId);
      _nativeTracking = true;
      _nativeRefresh?.cancel();
      _nativeRefresh = Timer.periodic(const Duration(seconds: 3), (_) {
        db.notifyUpdates({TableUpdate.onTable(db.trajetPoints)});
      });
      return;
    }
    // Reprend le dernier point connu pour le filtrage.
    final last =
        await (db.select(db.trajetPoints)
              ..where((t) => t.chargementId.equals(chargementId))
              ..orderBy([(t) => OrderingTerm.desc(t.capturedAt)])
              ..limit(1))
            .getSingleOrNull();
    _lastSaved = last == null
        ? null
        : TripGpsSample(
            lat: last.lat,
            lon: last.lon,
            accuracy: maximumAccuracyMeters,
            at: last.capturedAt,
          );
    _filter.reset(anchor: _lastSaved);

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      // Le flux Geolocator est partagé avec la caméra : fournir des mesures
      // fraîches même à l'arrêt. recordPoint conserve le filtre de déplacement.
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 3),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Mica — suivi du trajet',
        notificationText: 'Enregistrement du parcours en cours',
        enableWakeLock: true,
      ),
    );
    _sub = _positions(settings).listen((p) {
      if (p.isMocked) return;
      unawaited(
        recordPoint(
          chargementId,
          p.latitude,
          p.longitude,
          accuracy: p.accuracy,
          at: p.timestamp,
          speed: p.speed,
          speedAccuracy: p.speedAccuracy,
        ).catchError((Object error, StackTrace stack) {
          developer.log(
            'Échec enregistrement GPS',
            name: 'TripTracker',
            error: error,
            stackTrace: stack,
          );
        }),
      );
    });
  }

  Future<void> stop() async {
    _nativeRefresh?.cancel();
    _nativeRefresh = null;
    await _backgroundService?.stop();
    _nativeTracking = false;
    await _sub?.cancel();
    _sub = null;
    await _writes;
    _chargementId = null;
    _lastSaved = null;
    _filter.reset();
  }

  /// Détache uniquement l'observation Flutter. Le service Android appartient
  /// à la session métier et ne doit pas s'arrêter avec un widget/provider.
  Future<void> dispose() async {
    _nativeRefresh?.cancel();
    _nativeRefresh = null;
    await _sub?.cancel();
    _sub = null;
  }

  /// Confirme le déplacement GPS avant d'enregistrer, même hors ligne.
  /// Le simulateur utilise uniquement le seuil de distance.
  Future<void> recordPoint(
    String chargementId,
    double lat,
    double lon, {
    bool simule = false,
    double? accuracy,
    DateTime? at,
    double? speed,
    double? speedAccuracy,
  }) {
    final sample = TripGpsSample(
      lat: lat,
      lon: lon,
      accuracy: accuracy ?? (simule ? 1 : double.nan),
      at: at ?? DateTime.now(),
      speed: speed,
      speedAccuracy: speedAccuracy,
    );
    final write = _writes.then(
      (_) => _recordPoint(chargementId, sample, simule),
    );
    // Keep subsequent writes usable after one failed insert; callers still see
    // that failure through the original future.
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> _recordPoint(
    String chargementId,
    TripGpsSample sample,
    bool simule,
  ) async {
    final lat = sample.lat;
    final lon = sample.lon;
    if (!lat.isFinite ||
        lat < -90 ||
        lat > 90 ||
        !lon.isFinite ||
        lon < -180 ||
        lon > 180) {
      return;
    }
    if (simule) {
      if (_lastSaved != null && _lastSaved!.distanceTo(sample) < seuilMetres) {
        return;
      }
    } else if (!_filter.shouldRecord(sample)) {
      return;
    }
    await db
        .into(db.trajetPoints)
        .insert(
          TrajetPointsCompanion.insert(
            chargementId: chargementId,
            lat: lat,
            lon: lon,
            capturedAt: sample.at,
            simule: Value(simule),
          ),
        );
    _lastSaved = sample;
    _filter.commit(sample);
  }
}
