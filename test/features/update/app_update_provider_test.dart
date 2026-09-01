import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/di/providers.dart';
import 'package:mica_fleet/core/update/app_update_service.dart';
import 'package:mica_fleet/features/update/domain/update_readiness_repository.dart';
import 'package:mica_fleet/features/update/presentation/app_update_provider.dart';

void main() {
  test(
    'revérifie et bloque le téléchargement si des données attendent',
    () async {
      final gateway = _FakeUpdateGateway();
      final container = ProviderContainer(
        overrides: [
          appUpdateServiceProvider.overrideWithValue(gateway),
          updateReadinessRepositoryProvider.overrideWithValue(
            const _FixedReadiness(2),
          ),
        ],
      );
      addTearDown(container.dispose);
      const update = AppUpdateInfo(
        version: '1.2.7',
        build: 115,
        apkUrl: 'https://example.test/app.apk',
        sha256Hash: 'abc',
        mandatory: false,
        releaseNotes: null,
      );

      await expectLater(
        container
            .read(appUpdateControllerProvider.notifier)
            .downloadAndInstall(update),
        throwsA(isA<UnsyncedDataBeforeUpdate>()),
      );

      expect(gateway.downloadCalls, 0);
      expect(container.read(appUpdateControllerProvider).unsyncedDataCount, 2);
    },
  );
}

class _FixedReadiness implements UpdateReadinessRepository {
  final int count;

  const _FixedReadiness(this.count);

  @override
  Future<int> unsyncedDataCount() async => count;
}

class _FakeUpdateGateway implements AppUpdateGateway {
  int downloadCalls = 0;

  @override
  Future<AppUpdateCheck> check() async => const AppUpdateCheck(
    currentVersion: '1.2.6',
    currentBuild: 114,
    update: null,
  );

  @override
  Future<String> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(int received, int total)? onProgress,
  }) async {
    downloadCalls++;
    return 'installer_opened';
  }
}
