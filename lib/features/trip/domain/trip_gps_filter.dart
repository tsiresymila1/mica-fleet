import 'dart:math' as math;

import '../../../core/utils/geo.dart';

class TripGpsSample {
  const TripGpsSample({
    required this.lat,
    required this.lon,
    required this.accuracy,
    required this.at,
    this.speed,
    this.speedAccuracy,
  });

  final double lat, lon, accuracy;
  final DateTime at;
  final double? speed, speedAccuracy;

  bool get isValid =>
      lat.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lon.isFinite &&
      lon >= -180 &&
      lon <= 180 &&
      accuracy.isFinite &&
      accuracy > 0 &&
      accuracy <= 25;

  // Zero is also the plugin's default when speed accuracy is unavailable.
  bool get hasReliableSpeed =>
      speed != null &&
      speed!.isFinite &&
      speed! >= 0 &&
      speedAccuracy != null &&
      speedAccuracy!.isFinite &&
      speedAccuracy! > 0 &&
      speedAccuracy! <= 1;

  double distanceTo(TripGpsSample other) =>
      haversineMeters(lat, lon, other.lat, other.lon);
}

/// Confirms uncertain displacement before persistence. Does not rewrite tracks.
class TripGpsFilter {
  static const minimumDistance = 8.0;
  static const maximumSpeed = 45.0; // 162 km/h; generous ceiling for trucks.
  TripGpsSample? _anchor, _previous;
  DateTime? _latestTime;
  final List<TripGpsSample> _pending = [];

  void reset({TripGpsSample? anchor}) {
    _anchor = _previous = anchor;
    _latestTime = anchor?.at;
    _pending.clear();
  }

  double _uncertainty(TripGpsSample a, TripGpsSample b) =>
      math.sqrt(a.accuracy * a.accuracy + b.accuracy * b.accuracy);

  bool shouldRecord(TripGpsSample sample) {
    if (!sample.isValid ||
        (_latestTime != null && !sample.at.isAfter(_latestTime!))) {
      return false;
    }
    _latestTime = sample.at;
    final previous = _previous;
    if (previous != null) {
      final seconds = sample.at.difference(previous.at).inMicroseconds / 1e6;
      final minimumTravel = math.max(
        0.0,
        previous.distanceTo(sample) - _uncertainty(previous, sample),
      );
      if (minimumTravel / seconds > maximumSpeed) {
        _pending.clear();
        return false; // A rejected jump must not become the next reference.
      }
    }
    _previous = sample;
    final anchor = _anchor;
    if (anchor == null) return true;

    if (sample.hasReliableSpeed &&
        sample.speed! + sample.speedAccuracy! <= .3) {
      _pending.clear();
      return false;
    }
    // Unknown speed is never evidence of a stop.
    if (anchor.distanceTo(sample) < minimumDistance) {
      _pending.clear();
      return false;
    }

    if (_pending.isNotEmpty) {
      final first = _pending.first;
      final expired =
          sample.at.difference(first.at) > const Duration(seconds: 15);
      final a = anchor.distanceTo(first);
      final b = anchor.distanceTo(sample);
      final c = first.distanceTo(sample);
      // Opposite sides of the anchor are typical stationary jitter. Reset the
      // confirmation window, not the persisted route (real U-turns remain valid).
      final opposite = a * a + b * b - c * c < 0;
      if (expired || opposite) _pending.clear();
    }
    _pending.add(sample);
    if (_pending.length > 6) _pending.removeAt(0);
    final clear = anchor.distanceTo(sample) >= _uncertainty(anchor, sample);
    if (clear) return _pending.length >= 2;
    return _pending.length >= 3 && _pending.first.distanceTo(sample) >= 3;
  }

  /// Advance only after the database insert succeeds.
  void commit(TripGpsSample sample) {
    _anchor = _previous = sample;
    _latestTime = sample.at;
    _pending.clear();
  }
}
