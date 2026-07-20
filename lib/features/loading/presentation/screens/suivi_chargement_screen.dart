import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../transport/presentation/providers/transport_provider.dart';

/// Hub d'une session validée : ses lots + accès transbordement / arrivée.
class SuiviChargementScreen extends ConsumerWidget {
  final String sessionId;
  const SuiviChargementScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lots = ref.watch(lotsEnCoursProvider(sessionId));
    return Scaffold(
      appBar: AppBar(title: const Text('Mon transport')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppColors.ok.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.check_circle, color: AppColors.ok, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Chargement enregistré',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(sessionId,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          lots.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const SizedBox.shrink(),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${list.length} lot(s) en route',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...list.map((l) => ActionTile(
                      icon: Icons.inventory_2,
                      color: AppColors.gold,
                      titre: l.id,
                      sousTitre: [
                        l.mineId,
                        if (l.couleur != null) l.couleur!,
                      ].join(' · '),
                      onTap: () => context.push('/detail/${l.id}'),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: StepHeader(numero: 2, titre: 'Pendant le transport'),
          ),
          ActionTile(
            icon: Icons.local_shipping,
            color: AppColors.gold,
            titre: 'Changer de camion',
            sousTitre: 'Choisis les lots qui changent',
            onTap: () async {
              await context.push('/transbordement/$sessionId');
              ref.invalidate(lotsEnCoursProvider(sessionId));
            },
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 12, bottom: 12),
            child: StepHeader(numero: 3, titre: 'À l\'arrivée'),
          ),
          ActionTile(
            icon: Icons.warehouse,
            color: AppColors.primary,
            titre: 'Arrivée au dépôt',
            sousTitre: 'Valide les lots arrivés (1 n° de lot par lot)',
            onTap: () async {
              await context.push('/arrivee/$sessionId');
              ref.invalidate(lotsEnCoursProvider(sessionId));
            },
          ),
        ],
      ),
    );
  }
}
