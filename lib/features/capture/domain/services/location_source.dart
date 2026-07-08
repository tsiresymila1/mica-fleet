import 'package:geolocator/geolocator.dart';
import '../../../../core/utils/location.dart';

/// Un point GPS abstrait (réel ou simulé).
class GpsFix {
  final double lat, lon, accuracy;
  final bool mocked;
  const GpsFix(this.lat, this.lon, this.accuracy, {this.mocked = false});
}

/// Source de position — permet de substituer un GPS simulé au GPS réel.
abstract class LocationSource {
  Future<GpsFix> fix();
}

class RealLocationSource implements LocationSource {
  @override
  Future<GpsFix> fix() async {
    await ensureLocationReady();
    final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    return GpsFix(p.latitude, p.longitude, p.accuracy, mocked: p.isMocked);
  }
}
