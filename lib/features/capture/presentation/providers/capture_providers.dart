import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../trip/presentation/sim_session.dart';
import '../../data/compass_heading_source.dart';
import '../../data/mock_location_guard_impl.dart';
import '../../domain/services/heading_source.dart';
import '../../domain/services/location_source.dart';
import '../../domain/services/mock_location_guard.dart';

final headingSourceProvider = Provider<HeadingSource>(
  (ref) => CompassHeadingSource(),
);

/// GPS réel, ou simulé si une session de simulation est active.
final locationSourceProvider = Provider<LocationSource>((ref) {
  final sim = ref.watch(simSessionProvider);
  if (sim != null) {
    return SimLocationSource(ref.read(simSessionProvider.notifier));
  }
  return RealLocationSource();
});

/// GPS for plate/truck photos: first fresh position, no accuracy threshold.
final vehiclePhotoLocationSourceProvider = Provider<LocationSource>((ref) {
  if (ref.watch(simSessionProvider) != null) {
    return ref.watch(locationSourceProvider);
  }
  return RealLocationSource(requirePreciseFix: false);
});

/// The screen owns and disposes the initialized controller returned here.
final cameraFactoryProvider = Provider<Future<CameraController> Function()>((
  ref,
) {
  return () async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception('Aucune caméra disponible');
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      return controller;
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  };
});

final mockLocationGuardProvider = Provider<MockLocationGuard>(
  (ref) => GeolocatorMockGuard(ref.watch(locationSourceProvider)),
);
