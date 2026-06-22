import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/loading_id.dart';
import '../entities/chargement.dart';
import '../repositories/loading_repository.dart';

class CreateChargement {
  final LoadingRepository repo;
  CreateChargement(this.repo);

  Future<Either<Failure, Chargement>> call({
    required String fournisseurId,
    required DateTime now,
  }) async {
    final seq = await repo.nextSequence(now.year);
    final c = Chargement(
      id: buildLoadingId(now.year, seq),
      fournisseurId: fournisseurId,
      dateCreation: now,
    );
    return repo.persist(c);
  }
}
