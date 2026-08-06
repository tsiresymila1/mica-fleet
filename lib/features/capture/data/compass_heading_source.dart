import 'dart:io';

import 'package:flutter_compass/flutter_compass.dart';

import '../domain/services/heading_source.dart';

class CompassHeadingSource implements HeadingSource {
  final Duration timeout;
  final Stream<CompassEvent>? Function() _events;
  final bool _useCameraHeading;

  CompassHeadingSource({
    this.timeout = const Duration(seconds: 2),
    Stream<CompassEvent>? Function()? events,
    bool? useCameraHeading,
  }) : _events = events ?? (() => FlutterCompass.events),
       // flutter_compass 0.8.1 ne remplit pas headingForCameraMode sur
       // Android (la valeur reste 0). Son `heading` contient déjà le calcul
       // remappé selon l'inclinaison de l'appareil.
       _useCameraHeading = useCameraHeading ?? !Platform.isAndroid;

  @override
  Future<HeadingFix?> current() async {
    final events = _events();
    if (events == null) return null;
    try {
      final event = await events
          .firstWhere((event) => _headingOf(event) != null)
          .timeout(timeout);
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
    } catch (_) {
      // Un appareil sans magnétomètre ne doit pas bloquer la photo.
      return null;
    }
  }

  double? _headingOf(CompassEvent event) => _useCameraHeading
      ? (event.headingForCameraMode ?? event.heading)
      : (event.heading ?? event.headingForCameraMode);

  static double _normalize(double degrees) => (degrees % 360 + 360) % 360;
}
