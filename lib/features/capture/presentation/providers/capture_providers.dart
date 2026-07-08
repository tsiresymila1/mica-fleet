import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../trip/presentation/sim_session.dart';
import '../../data/mock_location_guard_impl.dart';
import '../../data/plate_ocr_service_impl.dart';
import '../../domain/services/location_source.dart';
import '../../domain/services/mock_location_guard.dart';
import '../../domain/services/plate_ocr_service.dart';

final plateOcrServiceProvider =
    Provider<PlateOcrService>((ref) => MlkitPlateOcrService());

/// GPS réel, ou simulé si une session de simulation est active.
final locationSourceProvider = Provider<LocationSource>((ref) {
  final sim = ref.watch(simSessionProvider);
  if (sim != null) {
    return SimLocationSource(ref.read(simSessionProvider.notifier));
  }
  return RealLocationSource();
});

final mockLocationGuardProvider = Provider<MockLocationGuard>(
    (ref) => GeolocatorMockGuard(ref.watch(locationSourceProvider)));
