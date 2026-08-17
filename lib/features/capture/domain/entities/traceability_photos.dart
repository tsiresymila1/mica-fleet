import 'captured_photo.dart';

enum TraceabilityPhotoRole {
  plate('plate'),
  mica('mica'),
  truckWithMica('truck_with_mica');

  final String apiValue;
  const TraceabilityPhotoRole(this.apiValue);
}

/// Les trois preuves obligatoires d'une étape de traçabilité photo v2.
/// En v3, `mica` est conservée uniquement pour relire les anciens lots : les
/// nouvelles captures exigent seulement `plate` et `truck_with_mica`.
class TraceabilityPhotos {
  final CapturedPhoto plate;
  final CapturedPhoto? mica;
  final CapturedPhoto truckWithMica;

  const TraceabilityPhotos({
    required this.plate,
    this.mica,
    required this.truckWithMica,
  });

  CapturedPhoto? byRole(TraceabilityPhotoRole role) => switch (role) {
    TraceabilityPhotoRole.plate => plate,
    TraceabilityPhotoRole.mica => mica,
    TraceabilityPhotoRole.truckWithMica => truckWithMica,
  };

  Iterable<({TraceabilityPhotoRole role, CapturedPhoto photo})> get entries =>
      TraceabilityPhotoRole.values
          .map((role) => (role: role, photo: byRole(role)))
          .where((entry) => entry.photo != null)
          .map((entry) => (role: entry.role, photo: entry.photo!));
}
