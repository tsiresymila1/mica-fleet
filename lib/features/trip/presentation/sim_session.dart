import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../capture/domain/services/location_source.dart';
import '../domain/trip_simulator.dart';

class SimState {
  final List<SimPoint> points;
  final int transbordementIndex;
  final int stage; // 0 = mine, 1 = transbordement, 2 = dépôt
  final String plateA; // camion de départ (mine → transbordement)
  final String plateB; // camion après transbordement (→ dépôt)
  const SimState(this.points, this.transbordementIndex, this.stage,
      this.plateA, this.plateB);

  int get _idx => switch (stage) {
        0 => 0,
        1 => transbordementIndex,
        _ => points.length - 1,
      };

  SimPoint get current => points[_idx];
}

/// Session de simulation guidée : fournit des coordonnées GPS simulées selon
/// l'étape (mine → transbordement → dépôt) et la trace à enregistrer.
final simSessionProvider =
    NotifierProvider<SimSession, SimState?>(SimSession.new);

class SimSession extends Notifier<SimState?> {
  @override
  SimState? build() => null;

  bool get active => state != null;
  String get plateA => state?.plateA ?? '';
  String get plateB => state?.plateB ?? '';

  void start(SimPoint depart, SimPoint depot) {
    final (pts, idx) = TripSimulator().generate(depart, depot);
    final r = math.Random();
    state = SimState(pts, idx, 0, _randomPlate(r), _randomPlate(r));
  }

  /// Plaque malgache plausible : 4 chiffres + espace + 3 lettres (ex. 1234 TBR).
  static String _randomPlate(math.Random r) {
    final digits = (1000 + r.nextInt(9000)).toString();
    const letters = 'ABCDEFGHJKLMNPRSTVWXYZ';
    final l =
        List.generate(3, (_) => letters[r.nextInt(letters.length)]).join();
    return '$digits $l';
  }

  GpsFix currentFix() {
    final s = state!;
    return GpsFix(s.current.lat, s.current.lon, 6);
  }

  void advance() {
    final s = state;
    if (s == null) return;
    state = SimState(s.points, s.transbordementIndex,
        (s.stage + 1).clamp(0, 2), s.plateA, s.plateB);
  }

  /// Points de la trace mine → transbordement.
  List<SimPoint> legMineToTransbordement() =>
      state!.points.sublist(0, state!.transbordementIndex + 1);

  /// Points de la trace transbordement → dépôt.
  List<SimPoint> legTransbordementToDepot() =>
      state!.points.sublist(state!.transbordementIndex);

  void stop() => state = null;
}

/// Source de position simulée branchée sur la session.
class SimLocationSource implements LocationSource {
  final SimSession session;
  SimLocationSource(this.session);
  @override
  Future<GpsFix> fix() async => session.currentFix();
}
