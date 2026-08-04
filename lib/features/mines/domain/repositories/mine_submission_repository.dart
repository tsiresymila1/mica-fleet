import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../entities/commune.dart';
import '../entities/mine_submission.dart';

abstract class MineSubmissionRepository {
  Future<Either<Failure, MineSubmission>> create({
    required String name,
    required int communeId,
    required List<CapturedPhoto> photos,
    String? agentLogin,
  });

  Future<List<MineSubmission>> list();

  Future<List<Commune>> listCommunes();
}
