import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../trip/presentation/sim_session.dart';
import '../../../trip/presentation/trip_provider.dart';
import '../../domain/entities/transbordement.dart';
import '../providers/transport_provider.dart';
import 'add_maillon_screen.dart';

/// Gère la chaîne dynamique 0..N de transbordements d'un chargement.
class TransbordementScreen extends ConsumerStatefulWidget {
  final String chargementId;
  const TransbordementScreen({super.key, required this.chargementId});
  @override
  ConsumerState<TransbordementScreen> createState() =>
      _TransbordementScreenState();
}

class _TransbordementScreenState extends ConsumerState<TransbordementScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(chaineControllerProvider.notifier).load(widget.chargementId));
  }

  Future<void> _addMaillon() async {
    final maillon = await Navigator.of(context).push<Transbordement>(
        MaterialPageRoute(builder: (_) => const AddMaillonScreen()));
    if (maillon == null) return;
    ref.read(chaineControllerProvider.notifier).addMaillon(maillon);
  }

  Future<void> _save() async {
    final ctrl = ref.read(chaineControllerProvider.notifier);
    if (!ctrl.chaineCoherente) {
      await showAppMessage(context, 'Les plaques ne se suivent pas',
          kind: AppMsgKind.warning);
      return;
    }
    final ok = await ctrl.persist(widget.chargementId);
    // En simulation : enregistre la trace transbordement → dépôt.
    if (ok && ref.read(simSessionProvider) != null) {
      final sim = ref.read(simSessionProvider.notifier);
      final tracker = ref.read(tripTrackerProvider);
      for (final p in sim.legTransbordementToDepot()) {
        await tracker.recordPoint(widget.chargementId, p.lat, p.lon,
            simule: true);
      }
      sim.advance(); // → étape dépôt
    }
    if (!mounted) return;
    await showAppMessage(
        context, ok ? 'Transbordements enregistrés' : 'Échec',
        kind: ok ? AppMsgKind.success : AppMsgKind.error);
  }

  @override
  Widget build(BuildContext context) {
    final chaine = ref.watch(chaineControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Changements de camion')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: StepHeader(
                numero: 1,
                titre: 'La chaîne',
                sousTitre: 'Un bloc par changement de camion'),
          ),
          Expanded(
            child: chaine.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                              color: AppColors.gold.withValues(alpha: 0.12),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.local_shipping,
                              size: 44, color: AppColors.gold),
                        ),
                        const SizedBox(height: 16),
                        Text('Aucun changement',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text('Transport direct vers le dépôt',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                    itemCount: chaine.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final m = chaine[i];
                      return ActionTile(
                        icon: Icons.swap_horiz,
                        color: m.conforme ? AppColors.ok : AppColors.warn,
                        titre: '${m.plaqueAvant ?? '?'} → ${m.plaqueApres ?? '?'}',
                        sousTitre: 'Bloc ${m.ordre} · appui long pour retirer',
                        trailing: StatusPill(
                          kind: m.conforme ? PillKind.ok : PillKind.warn,
                          label: m.conforme ? 'GPS ok' : 'Hors zone',
                        ),
                        onLongPress: () => ref
                            .read(chaineControllerProvider.notifier)
                            .removeMaillon(m.ordre),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
                onPressed: _addMaillon,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: BigButton(
                icon: Icons.save,
                label: 'Enregistrer',
                onPressed: chaine.isEmpty ? null : _save),
          ),
        ]),
      ),
    );
  }
}
