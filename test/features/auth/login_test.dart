import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mica_fleet/features/auth/domain/entities/fournisseur.dart';
import 'package:mica_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:mica_fleet/features/auth/domain/usecases/login.dart';

class _MockRepo extends Mock implements AuthRepository {}

void main() {
  late _MockRepo repo;
  late Login login;
  setUp(() {
    repo = _MockRepo();
    login = Login(repo);
  });

  test('identifiant vide → ValidationFailure', () async {
    final r = await login('  ');
    expect(r.isLeft(), isTrue);
  });

  test('identifiant valide → délègue au repo', () async {
    when(() => repo.login('F001'))
        .thenAnswer((_) async => right(const Fournisseur(id: 'F001', nom: 'X')));
    final r = await login('F001');
    expect(r.isRight(), isTrue);
    verify(() => repo.login('F001')).called(1);
  });
}
