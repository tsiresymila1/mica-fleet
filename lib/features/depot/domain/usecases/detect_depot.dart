import '../../../../core/utils/geo.dart';
import '../entities/depot.dart';

class DetectDepot {
  /// Retourne le dépôt actif dont la zone contient la position, ou null.
  Depot? call(List<Depot> depots, double lat, double lon) {
    for (final d in depots.where((d) => d.actif)) {
      if (isWithinRadius(lat, lon, d.lat, d.lon, d.rayonMetres)) return d;
    }
    return null;
  }
}
