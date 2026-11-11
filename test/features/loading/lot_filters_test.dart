import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/loading/presentation/providers/chargements_list_provider.dart';
import 'package:mica_fleet/features/loading/presentation/providers/chargement_detail_provider.dart'
    show SyncEtat;
import 'package:mica_fleet/features/loading/presentation/widgets/lot_filters.dart';

LotListItem _lot({
  double? kg,
  int? score,
  String? plate,
  String v = 'pending',
}) => LotListItem(
  id: 'L',
  sessionId: 'S',
  mineId: 'M',
  mineName: 'Mine A',
  tonnage: kg,
  date: DateTime(2026, 5, 10, 14),
  statut: 'en_cours',
  score: score,
  arrive: false,
  sync: SyncEtat.local,
  validationStatus: v,
  validationReason: null,
  serverReference: null,
  remoteOnly: false,
  plate: plate,
);

void main() {
  bool m(LotFilterField f, LotFilterOp o, String v, LotListItem l) =>
      LotFilterRule(f, o, v).matches(l);

  test('nombres : égal, différent, sup, inf', () {
    final l = _lot(kg: 500);
    expect(m(LotFilterField.tonnage, LotFilterOp.eq, '500', l), isTrue);
    expect(m(LotFilterField.tonnage, LotFilterOp.ne, '500', l), isFalse);
    expect(m(LotFilterField.tonnage, LotFilterOp.gt, '499,5', l), isTrue);
    expect(m(LotFilterField.tonnage, LotFilterOp.lt, '500', l), isFalse);
  });

  test('valeur absente : seul ≠ la retient', () {
    final l = _lot();
    expect(m(LotFilterField.score, LotFilterOp.gte, '10', l), isFalse);
    expect(m(LotFilterField.score, LotFilterOp.ne, '10', l), isTrue);
  });

  test('date au jour, plaque sans espace, statut', () {
    final l = _lot(plate: '1234 TBR', v: 'validated');
    expect(m(LotFilterField.date, LotFilterOp.eq, '2026-05-10', l), isTrue);
    expect(m(LotFilterField.date, LotFilterOp.lt, '2026-05-10', l), isFalse);
    expect(m(LotFilterField.plaque, LotFilterOp.eq, '1234tbr', l), isTrue);
    expect(m(LotFilterField.statut, LotFilterOp.ne, 'rejected', l), isTrue);
  });
}
