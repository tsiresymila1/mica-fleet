import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/di/providers.dart';
import 'package:mica_fleet/features/depot/presentation/providers/depot_provider.dart';
import 'package:mica_fleet/features/mines/presentation/providers/mine_submissions_provider.dart';
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
  Future<List<RemoteCommune>> fetchCommunes() async => const [
    RemoteCommune(24091, 'Andilana', null, true),
  ];

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
  test('la sync invalide les providers des trois référentiels', () async {
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
    expect(await container.read(communesProvider.future), isEmpty);

    await container.read(triggerSyncProvider).sync();

    expect((await container.read(minesProvider.future)).single.id, '7');
    expect((await container.read(activeDepotsProvider.future)).single.id, '8');
    expect((await container.read(communesProvider.future)).single.id, 24091);
  });
}
