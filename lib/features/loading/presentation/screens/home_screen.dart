import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../sync/presentation/sync_provider.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../providers/chargements_list_provider.dart';
import '../providers/loading_provider.dart';

/// Accueil après connexion : historique des chargements + bouton nouveau.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(chargementsListProvider);
    final fournisseur = ref.watch(authControllerProvider);
    final df = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      drawer: _AccountDrawer(
        nom: fournisseur?.nom ?? 'Fournisseur',
        id: fournisseur?.id ?? '',
        onLogout: () async {
          Navigator.of(context).pop(); // ferme le drawer
          final ok = await showConfirm(context, 'Veux-tu te déconnecter ?',
              titre: 'Déconnexion',
              confirmLabel: 'Déconnexion',
              danger: true);
          if (ok) ref.read(authControllerProvider.notifier).logout();
        },
      ),
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
                final tile = ActionTile(
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
                    await context.push('/detail/${c.id}');
                    ref.invalidate(chargementsListProvider);
                  },
                );
                // Finalisé (arrivé) → non supprimable. Sinon swipe pour supprimer.
                if (c.arrive) return tile;
                return Dismissible(
                  key: ValueKey(c.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.delete, color: AppColors.danger),
                  ),
                  confirmDismiss: (_) => showConfirm(
                      context, 'Supprimer le chargement ${c.id} ?',
                      titre: 'Supprimer',
                      confirmLabel: 'Supprimer',
                      danger: true),
                  onDismissed: (_) async {
                    final res = await ref
                        .read(loadingRepoProvider)
                        .deleteChargement(c.id);
                    ref.invalidate(chargementsListProvider);
                    if (context.mounted) {
                      await showAppMessage(
                          context,
                          res.isRight()
                              ? 'Chargement supprimé'
                              : 'Suppression impossible',
                          kind: res.isRight()
                              ? AppMsgKind.success
                              : AppMsgKind.error);
                    }
                  },
                  child: tile,
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
            await context.push('/chargement');
            ref.invalidate(chargementsListProvider);
          },
        ),
      ),
    );
  }
}

class _AccountDrawer extends StatelessWidget {
  final String nom;
  final String id;
  final VoidCallback onLogout;
  const _AccountDrawer(
      {required this.nom, required this.id, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final initiale = nom.trim().isEmpty ? '?' : nom.trim()[0].toUpperCase();
    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // En-tête compte
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.gold,
                    child: Text(initiale,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall!
                            .copyWith(color: Colors.white)),
                  ),
                  const SizedBox(height: 12),
                  Text(nom,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge!
                          .copyWith(color: Colors.white)),
                  Text('ID : $id',
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999)),
                    child: const Text('Connecté',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Compte fournisseur'),
            subtitle: Text(id),
          ),
          if (AppConfig.demo)
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: const Text('Scénarios (test)'),
              subtitle: const Text('Simuler sur cet appareil'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/dev-scenarios');
              },
            ),
          const Spacer(),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.danger),
            title: const Text('Se déconnecter',
                style: TextStyle(color: AppColors.danger)),
            onTap: onLogout,
          ),
          const SizedBox(height: 8),
        ],
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
