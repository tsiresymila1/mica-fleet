import 'package:geolocator/geolocator.dart';
import '../domain/services/mock_location_guard.dart';

class GeolocatorMockGuard implements MockLocationGuard {
  @override
  Future<bool> isMockLocationActive() async {
    final pos = await Geolocator.getCurrentPosition();
    return pos.isMocked; // geolocator expose isMocked sur Android
  }
}
