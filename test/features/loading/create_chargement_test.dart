import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mica_fleet/features/loading/domain/entities/chargement.dart';
import 'package:mica_fleet/features/loading/domain/repositories/loading_repository.dart';
import 'package:mica_fleet/features/loading/domain/usecases/create_chargement.dart';

class _MockRepo extends Mock implements LoadingRepository {}

class _FakeChargement extends Fake implements Chargement {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeChargement()));

  test('crée un chargement avec ID MICA-YYYY-XXXX', () async {
    final repo = _MockRepo();
    when(() => repo.nextSequence(2026)).thenAnswer((_) async => 7);
    when(() => repo.persist(any()))
        .thenAnswer((i) async => right(i.positionalArguments[0] as Chargement));
    final uc = CreateChargement(repo);
    final r = await uc(fournisseurId: 'F001', now: DateTime(2026, 6, 22));
    expect(r.getRight().toNullable()!.id, 'MICA-2026-0007');
  });
}
