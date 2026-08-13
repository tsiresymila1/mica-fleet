import 'captured_photo.dart';

enum TraceabilityPhotoRole {
  plate('plate'),
  mica('mica'),
  truckWithMica('truck_with_mica');

  final String apiValue;
  const TraceabilityPhotoRole(this.apiValue);
}

/// Les trois preuves obligatoires d'une étape de traçabilité photo v2.
class TraceabilityPhotos {
  final CapturedPhoto plate;
  final CapturedPhoto mica;
  final CapturedPhoto truckWithMica;

  const TraceabilityPhotos({
    required this.plate,
    required this.mica,
    required this.truckWithMica,
  });

  CapturedPhoto byRole(TraceabilityPhotoRole role) => switch (role) {
    TraceabilityPhotoRole.plate => plate,
    TraceabilityPhotoRole.mica => mica,
    TraceabilityPhotoRole.truckWithMica => truckWithMica,
  };

  Iterable<({TraceabilityPhotoRole role, CapturedPhoto photo})> get entries =>
      TraceabilityPhotoRole.values.map(
        (role) => (role: role, photo: byRole(role)),
      );
}
