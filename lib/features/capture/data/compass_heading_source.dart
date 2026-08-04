import 'package:flutter_compass/flutter_compass.dart';

import '../domain/services/heading_source.dart';

class CompassHeadingSource implements HeadingSource {
  final Duration timeout;
  final Stream<CompassEvent>? Function() _events;

  CompassHeadingSource({
    this.timeout = const Duration(seconds: 2),
    Stream<CompassEvent>? Function()? events,
  }) : _events = events ?? (() => FlutterCompass.events);

  @override
  Future<HeadingFix?> current() async {
    final events = _events();
    if (events == null) return null;
    try {
      final event = await events
          .firstWhere((event) => event.headingForCameraMode != null)
          .timeout(timeout);
      final rawHeading = event.headingForCameraMode;
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
    } catch (_) {
      // Un appareil sans magnétomètre ne doit pas bloquer la photo.
      return null;
    }
  }

  static double _normalize(double degrees) => (degrees % 360 + 360) % 360;
}
