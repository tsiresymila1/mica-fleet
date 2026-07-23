import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../sync/presentation/sync_provider.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../providers/chargement_detail_provider.dart' show SyncEtat;
import '../providers/chargements_list_provider.dart';
import '../providers/loading_provider.dart';

/// Accueil : historique des LOTS (unité de traçabilité) + nouveau chargement.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(lotsListProvider);
    final fournisseur = ref.watch(authControllerProvider);
    final df = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      drawer: _AccountDrawer(
        nom: fournisseur?.nom ?? 'Fournisseur',
        id: fournisseur?.id ?? '',
        onLogout: () async {
          Navigator.of(context).pop();
          final ok = await showConfirm(context, 'Veux-tu te déconnecter ?',
              titre: 'Déconnexion',
              confirmLabel: 'Déconnexion',
              danger: true);
          if (ok) ref.read(authControllerProvider.notifier).logout();
        },
      ),
      appBar: AppBar(
        title: const Text('Mes lots'),
        actions: [
          IconButton(
            tooltip: 'Synchroniser',
            icon: const Icon(Icons.sync),
            onPressed: () async {
              await ref.read(triggerSyncProvider).sync();
              ref.invalidate(lotsListProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(lotsListProvider),
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
                final l = items[i];
                final tile = ActionTile(
                  icon: l.arrive ? Icons.verified : Icons.local_shipping,
                  color: l.arrive ? AppColors.ok : AppColors.gold,
                  titre: l.id,
                  sousTitre: [
                    l.mineId,
                    if (l.couleur != null) l.couleur!,
                    df.format(l.date),
                  ].join('  •  '),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SyncIcon(l.sync),
                      if (l.score != null)
                        _ScoreBadge(score: l.score!)
                      else
                        StatusPill(
                            kind: l.arrive ? PillKind.ok : PillKind.neutral,
                            label: l.arrive ? 'Arrivé' : 'En route'),
                    ],
                  ),
                  onTap: () async {
                    await context.push('/detail/${l.id}');
                    ref.invalidate(lotsListProvider);
                  },
                );
                if (l.arrive) return tile;
                return Dismissible(
                  key: ValueKey(l.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.delete, color: AppColors.danger),
                  ),
                  confirmDismiss: (_) => showConfirm(context,
                      'Supprimer le chargement ${l.sessionId} et tous ses lots ?',
                      titre: 'Supprimer',
                      confirmLabel: 'Supprimer',
                      danger: true),
                  onDismissed: (_) async {
                    final res = await ref
                        .read(loadingRepoProvider)
                        .deleteChargement(l.sessionId);
                    ref.invalidate(lotsListProvider);
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
            ref.invalidate(lotsListProvider);
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Mon compte'),
            subtitle: const Text('Mes mines et dépôts'),
            onTap: () {
              Navigator.of(context).pop();
              context.push('/profil');
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Synchronisation'),
            subtitle: const Text('Historique des envois'),
            onTap: () {
              Navigator.of(context).pop();
              context.push('/sync');
            },
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

/// Petite icône d'état de sync dans la liste (rien à montrer si local).
class _SyncIcon extends StatelessWidget {
  final SyncEtat sync;
  const _SyncIcon(this.sync);
  @override
  Widget build(BuildContext context) {
    final (icon, color, tip) = switch (sync) {
      SyncEtat.local => (null, null, null),
      SyncEtat.synchronise => (Icons.cloud_done, AppColors.ok, 'Synchronisé'),
      SyncEtat.envoiPhotos => (
          Icons.cloud_sync,
          AppColors.inkSoft,
          'Photos en cours'
        ),
      SyncEtat.enAttente => (Icons.cloud_upload, AppColors.warn, 'À envoyer'),
      SyncEtat.echec => (Icons.cloud_off, AppColors.danger, 'Échec'),
    };
    if (icon == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(message: tip!, child: Icon(icon, color: color, size: 20)),
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
                Text('Aucun lot',
                    style: Theme.of(context).textTheme.titleMedium),
                Text('Appuie sur « Nouveau chargement »',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      );
}
