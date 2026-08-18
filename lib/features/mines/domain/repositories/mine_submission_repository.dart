import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../entities/mine_submission.dart';

abstract class MineSubmissionRepository {
  Future<Either<Failure, MineSubmission>> create({
    required String name,
    required List<CapturedPhoto> photos,
    String? agentLogin,
  });

  Future<List<MineSubmission>> list({String? agentLogin});

  /// Supprime la copie locale, les preuves et l'opération encore en file.
  Future<Either<Failure, Unit>> delete(String payloadId);
}
