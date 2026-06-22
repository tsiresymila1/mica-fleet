import 'dart:math' as math;

/// Distance en mètres entre deux points GPS (formule de Haversine).
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0; // rayon Terre en m
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

bool isWithinRadius(
    double lat1, double lon1, double lat2, double lon2, double radiusMeters) {
  return haversineMeters(lat1, lon1, lat2, lon2) <= radiusMeters;
}

double _rad(double deg) => deg * math.pi / 180.0;
