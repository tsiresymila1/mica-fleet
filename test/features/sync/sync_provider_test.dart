import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/di/providers.dart';
import 'package:mica_fleet/features/depot/presentation/providers/depot_provider.dart';
import 'package:mica_fleet/features/mines/presentation/providers/mines_provider.dart';
import 'package:mica_fleet/features/sync/domain/entities/sync_operation.dart';
import 'package:mica_fleet/features/sync/domain/repositories/remote_data_source.dart';
import 'package:mica_fleet/features/sync/presentation/sync_provider.dart';

class _ReferencesRemote implements RemoteDataSource {
  @override
  Future<List<RemoteMine>> fetchMines() async => [
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

  @override
  Future<List<RemoteDepot>> fetchDepots() async => const [
    RemoteDepot('8', 'Dépôt synchronisé', -18.8, 47.4, 20, true),
  ];

  @override
  Future<List<RemoteLot>> fetchLots() async => const [];

  @override
  Future<List<RemoteCommune>> fetchCommunes() async => const [];

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

class _BlockingRemote extends _ReferencesRemote {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<RemoteMine>> fetchMines() async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return super.fetchMines();
  }
}

void main() {
  test('la sync invalide les providers mines et dépôts', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        dbProvider.overrideWithValue(db),
        remoteDataSourceProvider.overrideWithValue(_ReferencesRemote()),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(minesProvider.future), isEmpty);
    expect(await container.read(activeDepotsProvider.future), isEmpty);

    await container.read(triggerSyncProvider).sync();

    expect((await container.read(minesProvider.future)).single.id, '7');
    expect((await container.read(activeDepotsProvider.future)).single.id, '8');
  });

  test('expose l’activité pendant toute la synchronisation', () async {
    final db = AppDatabase.memory();
    final remote = _BlockingRemote();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        dbProvider.overrideWithValue(db),
        remoteDataSourceProvider.overrideWithValue(remote),
      ],
    );
    addTearDown(container.dispose);

    final synchronization = container.read(triggerSyncProvider).sync();
    await remote.started.future;

    expect(container.read(syncInProgressProvider), isTrue);

    remote.release.complete();
    await synchronization;

    expect(container.read(syncInProgressProvider), isFalse);
  });
}
