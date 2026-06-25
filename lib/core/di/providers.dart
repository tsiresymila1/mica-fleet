import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import '../network/dio_client.dart';
import '../notifications/notification_service.dart';
import '../../features/journal/data/journal_service.dart';
import '../../features/sync/data/mock_remote_data_source.dart';
import '../../features/sync/data/local_sync_store_impl.dart';
import '../../features/sync/data/remote_data_source_retrofit.dart';
import '../../features/sync/data/sync_engine.dart';
import '../../features/sync/domain/repositories/local_sync_store.dart';
import '../../features/sync/domain/repositories/remote_data_source.dart';

final dbProvider =
    Provider<AppDatabase>((ref) => throw UnimplementedError('override in main'));

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

final journalServiceProvider =
    Provider<JournalService>((ref) => JournalService(ref.watch(dbProvider)));

final localSyncStoreProvider =
    Provider<LocalSyncStore>((ref) => DriftLocalSyncStore(ref.watch(dbProvider)));

final odooBaseUrlProvider =
    Provider<String>((ref) => 'https://odoo.example/api');

final remoteDataSourceProvider = Provider<RemoteDataSource>((ref) {
  // Démo : faux backend en debug (sync réussit sans Odoo). Retrofit en release.
  if (kDebugMode) return MockRemoteDataSource();
  final dio = buildDio(baseUrl: ref.watch(odooBaseUrlProvider));
  return RetrofitRemoteDataSource(OdooApi(dio));
});

final syncEngineProvider = Provider<SyncEngine>((ref) => SyncEngine(
      ref.watch(localSyncStoreProvider),
      ref.watch(remoteDataSourceProvider),
      ref.watch(dbProvider),
    ));
