import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/di/providers.dart';
import 'package:mica_fleet/features/auth/data/password_secret_store.dart';
import 'package:mica_fleet/features/profile/presentation/screens/profile_screen.dart';
import 'package:mica_fleet/features/sync/domain/entities/sync_operation.dart';
import 'package:mica_fleet/features/sync/domain/repositories/remote_data_source.dart';

class _NoPasswordSecretStore extends PasswordSecretStore {
  @override
  Future<PendingPasswordChange?> pending() async => null;
}

class _ReferencesRemote implements RemoteDataSource {
  int minesFetchCount = 0;
  int depotsFetchCount = 0;

  @override
  Future<List<RemoteMine>> fetchMines() async {
    minesFetchCount++;
    return [
      RemoteMine(
        '7',
        'Mine synchronisée',
        -18.9,
        47.5,
        20,
        null,
        null,
        null,
        true,
      ),
    ];
  }

  @override
  Future<List<RemoteDepot>> fetchDepots() async {
    depotsFetchCount++;
    return const [RemoteDepot('8', 'Dépôt synchronisé', -18.8, 47.4, 20, true)];
  }

  @override
  Future<List<RemoteLot>> fetchLots() async => const [];

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<int?> pushOperation(SyncOperation op) async => null;

  @override
  Future<void> uploadMinePhoto(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  ) async {}

  @override
  Future<void> uploadPhoto(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  ) async {}
}

void main() {
  testWidgets(
    'le pull-to-refresh synchronise les mines et les dépôts depuis le serveur',
    (tester) async {
      tester.view.physicalSize = const Size(430, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase.memory();
      final remote = _ReferencesRemote();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          dbProvider.overrideWithValue(db),
          remoteDataSourceProvider.overrideWithValue(remote),
          passwordSecretStoreProvider.overrideWithValue(
            _NoPasswordSecretStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aucune mine'), findsOneWidget);
      expect(remote.minesFetchCount, 0);
      expect(remote.depotsFetchCount, 0);

      final refreshIndicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      await refreshIndicator.onRefresh();

      expect(remote.minesFetchCount, 1);
      expect(remote.depotsFetchCount, 1);
      expect((await db.select(db.mines).get()).single.nom, 'Mine synchronisée');
      expect(
        (await db.select(db.depots).get()).single.nom,
        'Dépôt synchronisé',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
