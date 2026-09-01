import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/update/app_update_service.dart';
import '../data/drift_update_readiness_repository.dart';
import '../domain/update_readiness_repository.dart';

final updateReadinessRepositoryProvider = Provider<UpdateReadinessRepository>(
  (ref) => DriftUpdateReadinessRepository(ref.watch(dbProvider)),
);

final appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateState>(
      AppUpdateController.new,
    );

class AppUpdateState {
  final AppUpdateCheck? check;
  final bool checking;
  final bool downloading;
  final double? progress;
  final int unsyncedDataCount;
  final Object? error;

  const AppUpdateState({
    this.check,
    this.checking = false,
    this.downloading = false,
    this.progress,
    this.unsyncedDataCount = 0,
    this.error,
  });

  AppUpdateInfo? get update => check?.update;

  AppUpdateState copyWith({
    AppUpdateCheck? check,
    bool keepCheck = true,
    bool? checking,
    bool? downloading,
    double? progress,
    bool clearProgress = false,
    int? unsyncedDataCount,
    Object? error,
    bool clearError = false,
  }) => AppUpdateState(
    check: keepCheck ? (check ?? this.check) : check,
    checking: checking ?? this.checking,
    downloading: downloading ?? this.downloading,
    progress: clearProgress ? null : (progress ?? this.progress),
    unsyncedDataCount: unsyncedDataCount ?? this.unsyncedDataCount,
    error: clearError ? null : (error ?? this.error),
  );
}

class UnsyncedDataBeforeUpdate implements Exception {
  final int count;

  const UnsyncedDataBeforeUpdate(this.count);

  @override
  String toString() =>
      'Synchronisez les données locales avant de mettre à jour l’application.';
}

class AppUpdateController extends Notifier<AppUpdateState> {
  @override
  AppUpdateState build() => const AppUpdateState();

  Future<AppUpdateCheck?> check({bool silent = true}) async {
    if (state.checking) return state.check;
    state = state.copyWith(checking: true, clearError: true);
    try {
      final result = await ref.read(appUpdateServiceProvider).check();
      state = state.copyWith(
        check: result,
        keepCheck: false,
        checking: false,
        clearError: true,
      );
      return result;
    } catch (error) {
      state = state.copyWith(checking: false, error: error);
      if (!silent) rethrow;
      return null;
    }
  }

  Future<int> refreshUnsyncedDataCount() async {
    final count = await ref
        .read(updateReadinessRepositoryProvider)
        .unsyncedDataCount();
    state = state.copyWith(unsyncedDataCount: count);
    return count;
  }

  Future<String> downloadAndInstall(AppUpdateInfo update) async {
    final pending = await refreshUnsyncedDataCount();
    if (pending > 0) throw UnsyncedDataBeforeUpdate(pending);

    state = state.copyWith(
      downloading: true,
      clearProgress: true,
      clearError: true,
    );
    try {
      final result = await ref
          .read(appUpdateServiceProvider)
          .downloadAndInstall(
            update,
            onProgress: (received, total) {
              if (total <= 0) return;
              state = state.copyWith(progress: received / total);
            },
          );
      state = state.copyWith(downloading: false, progress: 1);
      return result;
    } catch (error) {
      state = state.copyWith(
        downloading: false,
        error: error,
        clearProgress: true,
      );
      rethrow;
    }
  }
}
