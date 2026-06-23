import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'core/db/app_database.dart';
import 'core/db/dev_seed.dart';
import 'core/di/providers.dart';
import 'features/auth/presentation/screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  if (kDebugMode) await DevSeeder(db).seedIfEmpty();
  final container =
      ProviderContainer(overrides: [dbProvider.overrideWithValue(db)]);

  // Sync au retour réseau
  Connectivity().onConnectivityChanged.listen((status) {
    if (status.any((s) => s != ConnectivityResult.none)) {
      container.read(syncEngineProvider).sync();
    }
  });

  runApp(UncontrolledProviderScope(
      container: container, child: const MicaFleetApp()));
}

class MicaFleetApp extends StatelessWidget {
  const MicaFleetApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mica Fleet',
        theme: ThemeData(
            colorSchemeSeed: const Color(0xFF1F4E79), useMaterial3: true),
        home: const LoginScreen(),
      );
}
