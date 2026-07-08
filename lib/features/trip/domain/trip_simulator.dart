import 'dart:math' as math;

class SimPoint {
  final double lat, lon;
  const SimPoint(this.lat, this.lon);
}

/// Génère un trajet plausible départ → transbordement → dépôt : interpolation
/// linéaire + léger zigzag pour ressembler à une vraie route.
class TripSimulator {
  /// [steps] points entre départ et dépôt. [seed] rend le jitter déterministe.
  /// Renvoie (points, indexTransbordement) — le transbordement est vers ~40 %.
  (List<SimPoint>, int) generate(
      SimPoint depart, SimPoint depot, {int steps = 20, int seed = 7}) {
    final rnd = math.Random(seed);
    final pts = <SimPoint>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final lat = _lerp(depart.lat, depot.lat, t);
      final lon = _lerp(depart.lon, depot.lon, t);
      // Jitter perpendiculaire décroissant (~ quelques dizaines de mètres).
      final j = (rnd.nextDouble() - 0.5) * 0.0004 * math.sin(t * math.pi);
      pts.add(SimPoint(lat + j, lon - j));
    }
    // Départ et dépôt exacts (sans jitter) aux extrémités.
    pts[0] = depart;
    pts[pts.length - 1] = depot;
    final idxTransbordement = (steps * 0.4).round();
    return (pts, idxTransbordement);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}
