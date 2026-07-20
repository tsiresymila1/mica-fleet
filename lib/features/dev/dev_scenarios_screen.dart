import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/ui/ui_kit.dart';
import '../auth/presentation/providers/auth_provider.dart';
import '../loading/presentation/providers/chargements_list_provider.dart';
import '../mines/presentation/providers/mines_provider.dart';
import '../trip/domain/trip_simulator.dart';
import '../trip/presentation/sim_session.dart';
import 'dev_scenario_service.dart';

final devScenarioServiceProvider =
    Provider((ref) => DevScenarioService(ref.watch(dbProvider)));

/// Menu de test (DEBUG) : simuler des scénarios sur un vrai appareil.
class DevScenariosScreen extends ConsumerWidget {
  const DevScenariosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(devScenarioServiceProvider);

    Future<void> run(Future<String> Function() action) async {
      try {
        final msg = await action();
        ref.invalidate(minesProvider);
        ref.invalidate(lotsListProvider);
        if (context.mounted) {
          await showAppMessage(context, msg, kind: AppMsgKind.success);
        }
      } catch (e) {
        if (context.mounted) {
          await showAppMessage(
              context, e.toString().replaceFirst('Exception: ', ''),
              kind: AppMsgKind.error);
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scénarios (test)')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ActionTile(
            icon: Icons.my_location,
            titre: 'Placer les mines ici',
            sousTitre: '3 mines + dépôt autour de ma position GPS',
            onTap: () => run(() async {
              final p = await svc.seedAroundMe();
              return 'Mines placées à ${p.lat.toStringAsFixed(4)}, '
                  '${p.lon.toStringAsFixed(4)}. Le flux marche ici.';
            }),
          ),
          const SizedBox(height: 12),
          ActionTile(
            icon: Icons.auto_mode,
            color: AppColors.gold,
            titre: 'Simulation guidée',
            sousTitre: 'Trajet auto (plaque + GPS simulés) mine → dépôt',
            onTap: () async {
              final ep = await svc.simEndpoints();
              if (ep == null) {
                if (context.mounted) {
                  await showAppMessage(context,
                      'Utilise d\'abord « Placer les mines ici »',
                      kind: AppMsgKind.warning);
                }
                return;
              }
              ref.read(simSessionProvider.notifier).start(
                  SimPoint(ep.dLat, ep.dLon), SimPoint(ep.aLat, ep.aLon));
              if (context.mounted) context.push('/chargement');
            },
          ),
          const SizedBox(height: 12),
          ActionTile(
            icon: Icons.playlist_add,
            titre: 'Injecter des chargements démo',
            sousTitre: 'Scores 100 / 60 + un en cours (supprimable)',
            onTap: () {
              final id = ref.read(authControllerProvider)?.id ?? 'F001';
              run(() async {
                await svc.injectDemoChargements(id);
                return '3 chargements de démo créés.';
              });
            },
          ),
          const SizedBox(height: 12),
          ActionTile(
            icon: Icons.delete_sweep,
            color: AppColors.danger,
            titre: 'Tout effacer',
            sousTitre: 'Supprime tous les chargements',
            onTap: () async {
              final ok = await showConfirm(
                  context, 'Effacer tous les chargements ?',
                  danger: true, confirmLabel: 'Effacer');
              if (ok) {
                await run(() async {
                  await svc.clearChargements();
                  return 'Chargements effacés.';
                });
              }
            },
          ),
        ],
      ),
    );
  }
}
