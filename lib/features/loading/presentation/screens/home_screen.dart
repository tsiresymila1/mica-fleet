import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../sync/presentation/sync_provider.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../providers/chargements_list_provider.dart';
import 'chargement_screen.dart';
import 'chargement_detail_screen.dart';

/// Accueil après connexion : historique des chargements + bouton nouveau.
class HomeScreen extends ConsumerWidget {
  final String fournisseurId;
  const HomeScreen({super.key, required this.fournisseurId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(chargementsListProvider);
    final df = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes chargements'),
        actions: [
          IconButton(
            tooltip: 'Synchroniser',
            icon: const Icon(Icons.sync),
            onPressed: () async {
              await ref.read(triggerSyncProvider).sync();
              ref.invalidate(chargementsListProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(chargementsListProvider),
        child: liste.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (items) {
            if (items.isEmpty) return _Empty();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final c = items[i];
                return ActionTile(
                  icon: c.arrive ? Icons.verified : Icons.local_shipping,
                  color: c.arrive ? AppColors.ok : AppColors.gold,
                  titre: c.id,
                  sousTitre:
                      '${df.format(c.date)}  •  ${c.nbMines} mine(s)',
                  trailing: c.score != null
                      ? _ScoreBadge(score: c.score!)
                      : StatusPill(
                          kind: c.arrive ? PillKind.ok : PillKind.neutral,
                          label: c.arrive ? 'Arrivé' : 'En cours'),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            ChargementDetailScreen(chargementId: c.id)));
                    ref.invalidate(chargementsListProvider);
                  },
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: BigButton(
          icon: Icons.add,
          label: 'Nouveau chargement',
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    ChargementScreen(fournisseurId: fournisseurId)));
            ref.invalidate(chargementsListProvider);
          },
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final int score;
  const _ScoreBadge({required this.score});
  @override
  Widget build(BuildContext context) {
    final couleur = score >= 80
        ? AppColors.ok
        : score > 0
            ? AppColors.warn
            : AppColors.danger;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: couleur, width: 2)),
      alignment: Alignment.center,
      child: Text('$score',
          style: Theme.of(context)
              .textTheme
              .titleMedium!
              .copyWith(color: couleur, fontWeight: FontWeight.w700)),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.inventory_2,
                      size: 44, color: AppColors.primary),
                ),
                const SizedBox(height: 16),
                Text('Aucun chargement',
                    style: Theme.of(context).textTheme.titleMedium),
                Text('Appuie sur « Nouveau chargement »',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      );
}
