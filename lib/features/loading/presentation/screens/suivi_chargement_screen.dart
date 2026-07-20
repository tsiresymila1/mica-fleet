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
                StepHeader(
                    numero: 2,
                    titre: '${list.length} lot(s) en route',
                    sousTitre: 'Ouvre un lot pour suivre SON camion'),
                const SizedBox(height: 8),
                ...list.map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ActionTile(
                        icon: Icons.inventory_2,
                        color: AppColors.gold,
                        titre: l.id,
                        sousTitre: [
                          l.mineId,
                          if (l.couleur != null) l.couleur!,
                        ].join(' · '),
                        onTap: () async {
                          await context.push('/detail/${l.id}');
                          ref.invalidate(lotsEnCoursProvider(sessionId));
                        },
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
