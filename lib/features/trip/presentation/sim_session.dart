import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../capture/domain/services/location_source.dart';
import '../domain/trip_simulator.dart';

class SimState {
  final List<SimPoint> points;
  final int transbordementIndex;
  final int stage; // 0 = mine, 1 = transbordement, 2 = dépôt
  final String plate;
  const SimState(
      this.points, this.transbordementIndex, this.stage, this.plate);

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
  String get plate => state?.plate ?? 'SIM-1234';

  void start(SimPoint depart, SimPoint depot) {
    final (pts, idx) = TripSimulator().generate(depart, depot);
    state = SimState(pts, idx, 0, 'SIM-1234');
  }

  GpsFix currentFix() {
    final s = state!;
    return GpsFix(s.current.lat, s.current.lon, 6);
  }

  void advance() {
    final s = state;
    if (s == null) return;
    state = SimState(
        s.points, s.transbordementIndex, (s.stage + 1).clamp(0, 2), s.plate);
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
