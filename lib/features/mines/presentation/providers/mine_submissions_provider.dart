import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/error/failure.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../../data/repositories/mine_submission_repository_impl.dart';
import '../../domain/entities/mine_submission.dart';
import '../../domain/repositories/mine_submission_repository.dart';
import '../../../sync/data/sync_engine.dart';
import 'mines_provider.dart';

final mineSubmissionRepositoryProvider = Provider<MineSubmissionRepository>(
  (ref) => MineSubmissionRepositoryImpl(ref.watch(dbProvider)),
);

final mineSubmissionsProvider = FutureProvider<List<MineSubmission>>(
  (ref) => ref.watch(mineSubmissionRepositoryProvider).list(),
);

final createMineSubmissionProvider = Provider<CreateMineSubmissionController>(
  (ref) => CreateMineSubmissionController(ref),
);

final mineSubmissionActionsProvider = Provider<MineSubmissionActionsController>(
  MineSubmissionActionsController.new,
);

class CreateMineSubmissionController {
  final Ref ref;
  CreateMineSubmissionController(this.ref);

  Future<Either<Failure, MineSubmission>> create({
    required String name,
    required List<CapturedPhoto> photos,
    String? agentLogin,
  }) async {
    final result = await ref
        .read(mineSubmissionRepositoryProvider)
        .create(name: name, photos: photos, agentLogin: agentLogin);
    if (result.isRight()) {
      ref.invalidate(mineSubmissionsProvider);
      // Le moteur absorbe les erreurs réseau et gardera l'opération en attente.
      unawaited(
        ref.read(syncEngineProvider).sync().then((_) {
          ref.invalidate(mineSubmissionsProvider);
          ref.invalidate(minesProvider);
        }),
      );
    }
    return result;
  }
}

class MineSubmissionActionsController {
  final Ref ref;
  MineSubmissionActionsController(this.ref);

  Future<Either<Failure, Unit>> delete(String payloadId) async {
    final result = await ref
        .read(mineSubmissionRepositoryProvider)
        .delete(payloadId);
    if (result.isRight()) ref.invalidate(mineSubmissionsProvider);
    return result;
  }

  Future<MineSubmissionSendResult> sendNow(String payloadId) async {
    final result = await ref
        .read(syncEngineProvider)
        .sendMineSubmissionNow(payloadId);
    ref.invalidate(mineSubmissionsProvider);
    ref.invalidate(minesProvider);
    return result;
  }
}
