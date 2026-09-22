import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_compass/flutter_compass.dart';

import '../domain/services/heading_source.dart';

class CompassHeadingSource implements HeadingSource {
  final Duration timeout;
  final int sampleCount;
  final Stream<CompassEvent>? Function() _events;
  final bool _useCameraHeading;

  CompassHeadingSource({
    this.timeout = const Duration(seconds: 2),
    this.sampleCount = 3,
    Stream<CompassEvent>? Function()? events,
    bool? useCameraHeading,
  }) : assert(sampleCount > 0),
       _events = events ?? (() => FlutterCompass.events),
       // flutter_compass 0.8.1 ne remplit pas headingForCameraMode sur
       // Android (la valeur reste 0). Son `heading` contient déjà le calcul
       // remappé selon l'inclinaison de l'appareil.
       _useCameraHeading = useCameraHeading ?? !Platform.isAndroid;

  @override
  Stream<HeadingFix> watch() async* {
    final events = _events();
    if (events == null) return;
    await for (final event in events) {
      final fix = _fixOf(event);
      if (fix != null) yield fix;
    }
  }

  @override
  Future<HeadingFix?> current() async {
    try {
      final samples = await watch()
          .where((fix) => fix.isReliable)
          .take(sampleCount)
          .toList()
          .timeout(timeout);
      if (samples.isEmpty) return null;
      return _average(samples);
    } catch (_) {
      // Un appareil sans magnétomètre ne doit pas bloquer la photo.
      return null;
    }
  }

  HeadingFix? _fixOf(CompassEvent event) {
    final rawHeading = _headingOf(event);
    if (rawHeading == null || !rawHeading.isFinite) return null;
    final rawAccuracy = event.accuracy;
    final accuracy =
        rawAccuracy != null && rawAccuracy.isFinite && rawAccuracy >= 0
        ? rawAccuracy
        : null;
    return HeadingFix(
      degrees: _normalize(rawHeading),
      accuracy: accuracy,
      reference: 'magnetic',
    );
  }

  static HeadingFix _average(List<HeadingFix> samples) {
    var x = 0.0;
    var y = 0.0;
    for (final sample in samples) {
      final radians = sample.degrees * math.pi / 180;
      x += math.cos(radians);
      y += math.sin(radians);
    }
    final degrees = x.abs() < 1e-9 && y.abs() < 1e-9
        ? samples.last.degrees
        : _normalize(math.atan2(y, x) * 180 / math.pi);
    final accuracy = samples.map((sample) => sample.accuracy!).reduce(math.max);
    return HeadingFix(
      degrees: degrees,
      accuracy: accuracy,
      reference: samples.last.reference,
    );
  }

  double? _headingOf(CompassEvent event) => _useCameraHeading
      ? (event.headingForCameraMode ?? event.heading)
      : (event.heading ?? event.headingForCameraMode);

  static double _normalize(double degrees) => (degrees % 360 + 360) % 360;
}
