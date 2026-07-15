import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import '../config/app_config.dart';
import '../db/app_database.dart';
import '../network/dio_client.dart';
import '../../features/sync/data/local_sync_store_impl.dart';
import '../../features/sync/data/mock_remote_data_source.dart';
import '../../features/sync/data/remote_data_source_retrofit.dart';
import '../../features/sync/data/sync_engine.dart';
import '../../features/sync/domain/repositories/remote_data_source.dart';

const kSyncTask = 'mica-periodic-sync';

/// Point d'entrée du worker WorkManager (isolate séparé, même app tuée).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await runBackgroundSync();
    return true;
  });
}

/// Ouvre la base, pousse les opérations en attente et pull le référentiel.
/// Autonome (ne dépend pas de l'UI) → utilisable depuis le worker.
Future<void> runBackgroundSync() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  try {
    final store = DriftLocalSyncStore(db);
    final RemoteDataSource remote = AppConfig.demo
        ? MockRemoteDataSource()
        : RetrofitRemoteDataSource(
            OdooApi(buildDio(baseUrl: AppConfig.odooBaseUrl)));
    final engine = SyncEngine(store, remote, db);
    await store.resetInFlight();
    await engine.sync();
  } finally {
    await db.close();
  }
}

/// Programme la sync périodique en arrière-plan (contrainte réseau + backoff).
Future<void> registerBackgroundSync() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    kSyncTask,
    kSyncTask,
    frequency: const Duration(minutes: 15), // minimum Android
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 1),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
