import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/trip/domain/trip_simulator.dart';
import 'package:mica_fleet/features/trip/presentation/sim_session.dart';

void main() {
  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('start génère une plaque au format NNNN LLL', () {
    final s = c.read(simSessionProvider.notifier);
    s.start(const SimPoint(-18.9, 47.5), const SimPoint(-19.0, 47.6));
    expect(RegExp(r'^\d{4} [A-Z]{3}$').hasMatch(s.plate), isTrue);
  });

  test('rotateTruck change la plaque (nouveau camion) et chaîne', () {
    final s = c.read(simSessionProvider.notifier);
    s.start(const SimPoint(-18.9, 47.5), const SimPoint(-19.0, 47.6));
    final p0 = s.plate; // camion A
    final p1 = s.rotateTruck(); // camion B
    expect(p1, isNot(p0));
    expect(s.plate, p1); // l'avant du prochain maillon reprendra p1
    final p2 = s.rotateTruck(); // camion C
    expect(p2, isNot(p1));
    expect(s.plate, p2);
  });
}
