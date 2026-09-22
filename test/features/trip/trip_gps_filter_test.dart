import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/trip/domain/trip_gps_filter.dart';

TripGpsSample sample(
  double meters,
  int seconds, {
  double accuracy = 5,
  double? speed,
  double? speedAccuracy,
}) => TripGpsSample(
  lat: meters / 111194.9266,
  lon: 0,
  accuracy: accuracy,
  at: DateTime(2026).add(Duration(seconds: seconds)),
  speed: speed,
  speedAccuracy: speedAccuracy,
);

void main() {
  late TripGpsFilter filter;
  late List<TripGpsSample> saved;
  void add(TripGpsSample point) {
    if (filter.shouldRecord(point)) {
      saved.add(point);
      filter.commit(point);
    }
  }

  setUp(() {
    filter = TripGpsFilter();
    saved = [];
  });

  test('8 m reste un minimum et le mouvement précis est confirmé', () {
    add(sample(0, 0));
    add(sample(7, 3));
    add(sample(8.1, 6));
    expect(saved, hasLength(1));
    add(sample(10, 9));
    expect(saved, hasLength(2));
  });

  test('un décalage incertain suivi du retour ne crée pas une boucle', () {
    add(sample(0, 0, accuracy: 20));
    add(sample(9, 3, accuracy: 20));
    add(sample(0, 6, accuracy: 20));
    add(sample(-10, 9, accuracy: 20));
    add(sample(0, 12, accuracy: 20));
    expect(saved, hasLength(1));
  });

  test('vitesse inconnue ne bloque pas une progression lente incertaine', () {
    add(sample(0, 0, accuracy: 20));
    for (final (meters, seconds) in [(8.1, 3), (10.0, 6), (12.0, 9)]) {
      add(sample(meters, seconds, accuracy: 20, speed: 0, speedAccuracy: 0));
    }
    expect(saved, hasLength(2));
  });

  test('un décalage stable dans la marge de précision ne suffit pas', () {
    add(sample(0, 0, accuracy: 20));
    for (var t = 3; t <= 12; t += 3) {
      add(sample(12, t, accuracy: 20));
    }
    expect(saved, hasLength(1));
  });

  test('la vitesse fiable à arrêt écarte la dérive et permet de repartir', () {
    add(sample(0, 0));
    for (var t = 3; t <= 12; t += 3) {
      add(sample(t.isEven ? -12 : 12, t, speed: 0, speedAccuracy: .1));
    }
    expect(saved, hasLength(1));
    add(sample(10, 15, speed: 2, speedAccuracy: .1));
    add(sample(16, 18, speed: 2, speedAccuracy: .1));
    expect(saved, hasLength(2));
  });

  test('un saut impossible ne remplace pas la référence fiable', () {
    add(sample(0, 0));
    add(sample(500, 3));
    add(sample(9, 6));
    add(sample(12, 9));
    expect(saved, hasLength(2));
    expect(saved.last.distanceTo(sample(12, 9)), closeTo(0, .01));
  });

  test('dates répétées ou antérieures ignorées', () {
    add(sample(0, 0));
    add(sample(10, 0));
    add(sample(10, -3));
    expect(saved, hasLength(1));
  });

  test('la confirmation expire après une interruption', () {
    add(sample(0, 0));
    add(sample(9, 3));
    add(sample(10, 24));
    expect(saved, hasLength(1));
    add(sample(12, 27));
    expect(saved, hasLength(2));
  });

  test('les vrais demi-tours ne sont pas supprimés', () {
    add(sample(0, 0));
    add(sample(10, 3));
    add(sample(20, 6));
    add(sample(10, 9));
    add(sample(0, 12));
    expect(saved, hasLength(3));
    expect(saved.last.distanceTo(sample(0, 12)), closeTo(0, .01));
  });

  test('reprise sur dernier point enregistré et précision invalide', () {
    filter.reset(anchor: sample(0, 0, accuracy: 25));
    add(sample(10, 3, accuracy: 40));
    add(sample(10, 6));
    add(sample(12, 9));
    add(sample(14, 12));
    expect(saved, hasLength(1));
    filter.reset();
    add(sample(100, 15));
    expect(saved, hasLength(2));
  });
}
