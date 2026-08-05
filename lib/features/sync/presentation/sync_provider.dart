import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../depot/presentation/providers/depot_provider.dart';
import '../../mines/presentation/providers/mine_submissions_provider.dart';
import '../../mines/presentation/providers/mines_provider.dart';

/// Synchronise puis force les listes affichées à relire le cache Drift.
final triggerSyncProvider = Provider(SyncController.new);

class SyncController {
  final Ref ref;
  SyncController(this.ref);

  Future<void> sync() async {
    await ref.read(syncEngineProvider).sync();
    ref.invalidate(minesProvider);
    ref.invalidate(activeDepotsProvider);
    ref.invalidate(communesProvider);
    ref.invalidate(mineSubmissionsProvider);
  }
}
