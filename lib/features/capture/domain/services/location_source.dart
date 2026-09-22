import 'dart:async';

import 'package:geolocator/geolocator.dart';
import '../../../../core/utils/location.dart';

/// Un point GPS abstrait (réel ou simulé).
class GpsFix {
  final double lat, lon, accuracy;
  final bool mocked;
  const GpsFix(this.lat, this.lon, this.accuracy, {this.mocked = false});
}

/// Source de position — permet de substituer un GPS simulé au GPS réel.
abstract class LocationSource {
  Future<GpsFix> fix();
}

/// Préparation limitée à la durée de vie de l'écran caméra.
abstract class PreparedLocationSource implements LocationSource {
  Future<void> prepare();
  Future<void> stopPreparing();
}

typedef PositionStreamFactory =
    Stream<Position> Function(LocationSettings settings);

class RealLocationSource implements PreparedLocationSource {
  static const double defaultTargetAccuracyMeters = 8;
  static const double defaultMaximumAccuracyMeters = 25;

  final double targetAccuracyMeters;
  final double maximumAccuracyMeters;

  /// Vehicle evidence keeps the reported accuracy, without waiting for a better
  /// measurement. Other captures retain the precise-location policy.
  final bool requirePreciseFix;
  final Duration sampleTimeout;
  final Duration maximumFixAge;
  final Future<void> Function() _ensureReady;
  final Future<LocationAccuracyStatus> Function() _accuracyStatus;
  final PositionStreamFactory _positions;
  final DateTime Function() _now;
  StreamSubscription<Position>? _warmSubscription;
  StreamController<Position>? _warmUpdates;
  Position? _latest;
  int _preparationGeneration = 0;

  RealLocationSource({
    this.requirePreciseFix = true,
    this.targetAccuracyMeters = defaultTargetAccuracyMeters,
    this.maximumAccuracyMeters = defaultMaximumAccuracyMeters,
    this.sampleTimeout = const Duration(seconds: 5),
    this.maximumFixAge = const Duration(seconds: 3),
    Future<void> Function()? ensureReady,
    Future<LocationAccuracyStatus> Function()? accuracyStatus,
    PositionStreamFactory? positions,
    DateTime Function()? now,
  }) : assert(targetAccuracyMeters > 0),
       assert(maximumAccuracyMeters >= targetAccuracyMeters),
       assert(sampleTimeout > Duration.zero),
       assert(maximumFixAge > Duration.zero),
       _now = now ?? DateTime.now,
       _ensureReady = ensureReady ?? ensureLocationReady,
       _accuracyStatus = accuracyStatus ?? Geolocator.getLocationAccuracy,
       _positions =
           positions ??
           ((settings) =>
               Geolocator.getPositionStream(locationSettings: settings));

  Future<void> _checkReady() async {
    await _ensureReady();
    if (requirePreciseFix &&
        await _accuracyStatus() == LocationAccuracyStatus.reduced) {
      throw Exception(
        'Active « Position précise » pour MICA Fleet dans les réglages GPS',
      );
    }
  }

  @override
  Future<void> prepare() async {
    if (_warmSubscription != null) return;
    final generation = ++_preparationGeneration;
    await _checkReady();
    if (generation != _preparationGeneration || _warmSubscription != null) {
      return;
    }
    final updates = StreamController<Position>.broadcast();
    _warmUpdates = updates;
    _warmSubscription =
        _positions(
          const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          ),
        ).listen(
          (position) {
            if (generation != _preparationGeneration) return;
            _latest = _isFreshAndUsable(position) ? position : null;
            updates.add(position);
          },
          onError: (Object error, StackTrace stack) {
            if (generation != _preparationGeneration) return;
            _latest = null;
            updates.addError(error, stack);
          },
          onDone: () {
            if (identical(_warmUpdates, updates)) {
              _warmSubscription = null;
              _warmUpdates = null;
            }
            unawaited(updates.close());
          },
        );
  }

  @override
  Future<void> stopPreparing() async {
    ++_preparationGeneration;
    final subscription = _warmSubscription;
    final updates = _warmUpdates;
    _warmSubscription = null;
    _warmUpdates = null;
    _latest = null;
    await subscription?.cancel();
    await updates?.close();
  }

  @override
  Future<GpsFix> fix() async {
    await _checkReady();
    final latest = _latest;
    if (latest != null && _isFreshAndUsable(latest)) {
      _rejectMocked(latest);
      if (!requirePreciseFix || latest.accuracy <= maximumAccuracyMeters) {
        return _fixOf(latest);
      }
    }

    Position? best;
    final stopwatch = Stopwatch()..start();
    final iterator = StreamIterator(
      _warmUpdates?.stream ??
          _positions(
            const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
            ),
          ),
    );
    try {
      while (stopwatch.elapsed < sampleTimeout) {
        final remaining = sampleTimeout - stopwatch.elapsed;
        if (!await iterator.moveNext().timeout(remaining)) break;
        final position = iterator.current;
        if (!_isFreshAndUsable(position)) continue;
        _rejectMocked(position);
        if (!requirePreciseFix) return _fixOf(position);
        if (best == null ||
            !_isFreshAndUsable(best) ||
            position.accuracy < best.accuracy) {
          best = position;
        }
        if (position.accuracy <= targetAccuracyMeters) break;
      }
    } on TimeoutException {
      // Le meilleur point reçu avant l'expiration reste utilisable ci-dessous.
    } finally {
      stopwatch.stop();
      await iterator.cancel();
    }

    if (best == null || !_isFreshAndUsable(best)) {
      throw Exception(
        requirePreciseFix
            ? 'Aucune position GPS fiable. Place-toi à l’extérieur puis réessaie.'
            : 'Aucune position GPS disponible. Active le GPS puis réessaie.',
      );
    }
    if (best.accuracy > maximumAccuracyMeters) {
      throw Exception(
        'Précision GPS insuffisante (±${best.accuracy.round()} m). '
        'Place-toi à l’extérieur puis réessaie.',
      );
    }
    return _fixOf(best);
  }

  bool _isFreshAndUsable(Position position) {
    final age = _now().difference(position.timestamp);
    return _isUsable(position) && age >= Duration.zero && age <= maximumFixAge;
  }

  static void _rejectMocked(Position position) {
    if (position.isMocked) {
      throw Exception('Position GPS simulée détectée — capture refusée');
    }
  }

  static GpsFix _fixOf(Position position) => GpsFix(
    position.latitude,
    position.longitude,
    position.accuracy,
    mocked: position.isMocked,
  );

  bool _isUsable(Position position) =>
      position.latitude.isFinite &&
      position.latitude >= -90 &&
      position.latitude <= 90 &&
      position.longitude.isFinite &&
      position.longitude >= -180 &&
      position.longitude <= 180 &&
      position.accuracy.isFinite &&
      (requirePreciseFix ? position.accuracy > 0 : position.accuracy >= 0);
}
