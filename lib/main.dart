import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:go_router/go_router.dart';
import 'core/config/app_config.dart';
import 'core/db/app_database.dart';
import 'core/db/dev_seed.dart';
import 'core/di/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  if (AppConfig.demo) await DevSeeder(db).seedIfEmpty();
  final container =
      ProviderContainer(overrides: [dbProvider.overrideWithValue(db)]);

  // Restaure la session existante (garde du routeur).
  final session = await container.read(authRepositoryProvider).currentSession();
  container.read(authControllerProvider.notifier).setSession(session);

  final router = container.read(routerProvider);

  // Tap sur une notification de rappel → ouvre le détail du chargement.
  await container.read(notificationServiceProvider).init(
        onTap: (chargementId) => router.go('/detail/$chargementId'),
      );

  // Reprend les opérations bloquées (app tuée en plein push).
  await container.read(localSyncStoreProvider).resetInFlight();

  // Sync initiale au démarrage : charge le référentiel + pousse les en-attente.
  // (onConnectivityChanged ne se déclenche pas à froid si déjà en ligne.)
  container.read(syncEngineProvider).sync();

  // Sync au retour réseau
  Connectivity().onConnectivityChanged.listen((status) {
    if (status.any((s) => s != ConnectivityResult.none)) {
      container.read(syncEngineProvider).sync();
    }
  });

  runApp(UncontrolledProviderScope(
      container: container, child: MicaFleetApp(router: router)));
}

class MicaFleetApp extends StatelessWidget {
  final GoRouter router;
  const MicaFleetApp({super.key, required this.router});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Mica Fleet',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        routerConfig: router,
      );
}
