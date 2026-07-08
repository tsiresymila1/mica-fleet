import '../domain/services/location_source.dart';
import '../domain/services/mock_location_guard.dart';

class GeolocatorMockGuard implements MockLocationGuard {
  final LocationSource location;
  GeolocatorMockGuard(this.location);

  @override
  Future<bool> isMockLocationActive() async => (await location.fix()).mocked;
}
