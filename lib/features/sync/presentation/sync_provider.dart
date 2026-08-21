import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../depot/presentation/providers/depot_provider.dart';
import '../../mines/presentation/providers/mine_submissions_provider.dart';
import '../../mines/presentation/providers/mines_provider.dart';
import '../../loading/presentation/providers/chargements_list_provider.dart';

/// Synchronise puis force les listes affichées à relire le cache Drift.
final triggerSyncProvider = Provider(SyncController.new);

final syncInProgressProvider = NotifierProvider<SyncActivityController, bool>(
  SyncActivityController.new,
);

class SyncActivityController extends Notifier<bool> {
  @override
  bool build() => false;

  void start() => state = true;
  void stop() => state = false;
}

class SyncController {
  final Ref ref;
  SyncController(this.ref);

  Future<void> sync() async {
    final ownsActivity = !ref.read(syncInProgressProvider);
    if (ownsActivity) {
      ref.read(syncInProgressProvider.notifier).start();
    }
    try {
      await ref.read(syncEngineProvider).sync();
      ref.invalidate(minesProvider);
      ref.invalidate(activeDepotsProvider);
      ref.invalidate(mineSubmissionsProvider);
      ref.invalidate(lotsListProvider);
    } finally {
      if (ownsActivity) {
        ref.read(syncInProgressProvider.notifier).stop();
      }
    }
  }
}
