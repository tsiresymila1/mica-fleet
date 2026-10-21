import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../sync/presentation/sync_provider.dart';
import '../../../sync/presentation/widgets/sync_icon_button.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../providers/chargement_detail_provider.dart' show SyncEtat;
import '../providers/chargements_list_provider.dart';
import '../providers/loading_provider.dart';

Future<void> _deleteLotFromList(
  BuildContext context,
  WidgetRef ref,
  String lotId,
) async {
  final ok = await showConfirm(
    context,
    'Supprimer le lot $lotId ?',
    titre: 'Supprimer',
    confirmLabel: 'Supprimer',
    danger: true,
  );
  if (!ok) return;
  final res = await ref.read(loadingRepoProvider).deleteLot(lotId);
  if (!context.mounted) return;
  ref.invalidate(lotsListProvider);
  await showAppMessage(
    context,
    res.isRight() ? 'Lot supprimé localement' : 'Suppression impossible',
    kind: res.isRight() ? AppMsgKind.success : AppMsgKind.error,
  );
}

/// Accueil : historique des LOTS (unité de traçabilité) + nouveau chargement.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _filter = 'all';
  final _searchController = TextEditingController();
  bool _newestFirst = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liste = ref.watch(lotsListProvider);
    final fournisseur = ref.watch(authControllerProvider);
    final df = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      drawer: _AccountDrawer(
        nom: fournisseur?.nom ?? 'Fournisseur',
        id: fournisseur?.id ?? '',
        onLogout: () async {
          Navigator.of(context).pop();
          final ok = await showConfirm(
            context,
            'Veux-tu te déconnecter ?',
            titre: 'Déconnexion',
            confirmLabel: 'Déconnexion',
            danger: true,
          );
          if (ok) ref.read(authControllerProvider.notifier).logout();
        },
      ),
      appBar: AppBar(
        centerTitle: true,
        title: Image.asset(
          'assets/logos/radoran_logo.png',
          width: 158,
          height: 38,
          fit: BoxFit.contain,
        ),
        actions: [
          SyncIconButton(
            onPressed: () async {
              showAppToast(context, 'Synchronisation lancée');
              await ref.read(triggerSyncProvider).sync();
              ref.invalidate(lotsListProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.read(triggerSyncProvider).sync(),
        child: liste.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (items) {
            final query = _searchController.text.trim().toLowerCase();
            final filtered = items.where((item) {
              if (_filter != 'all' && item.validationStatus != _filter) {
                return false;
              }
              return query.isEmpty ||
                  [
                    item.id,
                    item.serverReference,
                    item.mineName,
                    item.plate,
                    item.validationStatus,
                    switch (item.validationStatus) {
                      'validated' => 'validé',
                      'rejected' => 'rejeté',
                      _ =>
                        item.sync == SyncEtat.local
                            ? 'brouillon'
                            : 'en attente',
                    },
                    item.validationReason,
                    item.arrive ? 'arrivé' : 'en route',
                    item.tonnage?.toString(),
                    df.format(item.date),
                  ].whereType<String>().join(' ').toLowerCase().contains(query);
            }).toList();
            if (!_newestFirst) {
              filtered.sort((a, b) => a.date.compareTo(b.date));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(15, 12, 15, 120),
              itemCount: filtered.length + (filtered.isEmpty ? 2 : 1),
              separatorBuilder: (_, _) => const SizedBox(height: 11),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Mes lots',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                                Text(
                                  'Suivi de vos chargements',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF1F7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Poids cumulé · ${NumberFormat.decimalPattern('fr').format(filtered.fold<double>(0, (sum, lot) => sum + (lot.tonnage ?? 0)))} kg',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _filterTab('all', 'Tous'),
                          _filterTab('pending', 'Attente'),
                          _filterTab('validated', 'Validés'),
                          _filterTab('rejected', 'Rejetés'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText:
                                    'Rechercher un lot, une mine, une plaque…',
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: _newestFirst
                                ? 'Plus anciens'
                                : 'Plus récents',
                            onPressed: () =>
                                setState(() => _newestFirst = !_newestFirst),
                            icon: const Icon(Icons.swap_vert),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            '${filtered.length} lot${filtered.length > 1 ? 's' : ''} affiché${filtered.length > 1 ? 's' : ''}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          Text(
                            _newestFirst ? 'Plus récents' : 'Plus anciens',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  );
                }
                if (filtered.isEmpty) {
                  return items.isEmpty
                      ? const _Empty()
                      : const Center(child: Text('Aucun lot trouvé'));
                }
                final l = filtered[i - 1];
                final tile = _LotCard(
                  lot: l,
                  onTap: () async {
                    await context.push('/detail/${l.id}');
                    ref.invalidate(lotsListProvider);
                  },
                  onLongPress: () async {
                    if (l.arrive || l.remoteOnly) {
                      await showAppMessage(
                        context,
                        l.arrive
                            ? 'Ce lot est déjà arrivé, suppression locale impossible.'
                            : 'Ce lot vient du serveur, il est en synchronisation distante.',
                        kind: AppMsgKind.warning,
                      );
                      return;
                    }
                    _deleteLotFromList(context, ref, l.id);
                  },
                );
                if (l.arrive || l.remoteOnly) return tile;
                return Dismissible(
                  key: ValueKey(l.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete, color: AppColors.danger),
                  ),
                  confirmDismiss: (_) => showConfirm(
                    context,
                    'Supprimer le chargement ${l.sessionId} et tous ses lots ?',
                    titre: 'Supprimer',
                    confirmLabel: 'Supprimer',
                    danger: true,
                  ),
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
                            : AppMsgKind.error,
                      );
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

  Widget _filterTab(String value, String label) => Expanded(
    child: Padding(
      padding: const EdgeInsets.only(right: 6),
      child: SizedBox(
        height: 37,
        child: OutlinedButton(
          onPressed: () => setState(() => _filter = value),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: _filter == value
                ? AppColors.primary
                : Colors.white,
            foregroundColor: _filter == value
                ? Colors.white
                : AppColors.inkSoft,
            side: BorderSide(
              color: _filter == value ? AppColors.primary : AppColors.line,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
      ),
    ),
  );
}

class _AccountDrawer extends StatelessWidget {
  static const _dividerColor = Color(0xFFF1F3F7);

  final String nom;
  final String id;
  final VoidCallback onLogout;
  const _AccountDrawer({
    required this.nom,
    required this.id,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final initiales = nom
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final width = MediaQuery.sizeOf(context).width * 0.88;
    return Drawer(
      width: width > 337 ? 337 : width,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(22)),
      ),
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(19, 16, 19, 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _dividerColor)),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'assets/logos/radoran_logo.png',
                    width: 170,
                    height: 46,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF0FC),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          initiales,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nom,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ID : $id',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.inkSoft),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              children: [
                _section('OPÉRATIONS'),
                _entry(
                  context,
                  Icons.layers_outlined,
                  'Mes lots',
                  'Suivi des chargements',
                  () => Navigator.of(context).pop(),
                  selected: true,
                ),
                _entry(
                  context,
                  Icons.place_outlined,
                  'Mes mines et dépôts',
                  'Origines et sites autorisés',
                  () => _go(context, '/sites'),
                ),
                _entry(
                  context,
                  Icons.add,
                  'Proposer une mine',
                  'Ajout manuel et validation',
                  () => _go(context, '/mines-manual/new'),
                ),
                _section('DONNÉES ET COMPTE'),
                if (AppConfig.demo)
                  _entry(
                    context,
                    Icons.cloud_upload_outlined,
                    'Synchronisation',
                    'Historique des envois',
                    () => _go(context, '/sync'),
                  ),
                _entry(
                  context,
                  Icons.person_outline,
                  'Mon compte',
                  'Profil et informations',
                  () => _go(context, '/profil'),
                ),
                _section('APPLICATION'),
                _entry(
                  context,
                  Icons.help_outline,
                  'Aide',
                  'Guides et support',
                  () => _go(context, '/aide'),
                ),
                if (AppConfig.demo) ...[
                  _entry(
                    context,
                    Icons.science_outlined,
                    'Scénarios (test)',
                    'Simuler sur cet appareil',
                    () => _go(context, '/dev-scenarios'),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(19, 10, 19, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _dividerColor)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                    tileColor: const Color(0xFFFFF3F5),
                    leading: const Icon(Icons.logout, color: AppColors.danger),
                    title: const Text(
                      'Se déconnecter',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: onLogout,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'RADORAN · Traçabilité du mica',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _go(BuildContext context, String route) {
    Navigator.of(context).pop();
    context.push(route);
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(13, 8, 13, 5),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w800,
        color: AppColors.inkSoft,
      ),
    ),
  );

  Widget _entry(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: ListTile(
      selected: selected,
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      minVerticalPadding: 4,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      tileColor: selected ? const Color(0xFFEAF0FC) : null,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDCE7FA) : const Color(0xFFF0F2F8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: selected ? AppColors.primary : AppColors.ink,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 10.5,
          color: AppColors.inkSoft,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        size: 18,
        color: AppColors.inkSoft,
      ),
      onTap: onTap,
    ),
  );
}

class _LotCard extends StatelessWidget {
  const _LotCard({
    required this.lot,
    required this.onTap,
    required this.onLongPress,
  });

  final LotListItem lot;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (lot.validationStatus) {
      'validated' => const Color(0xFF169365),
      'rejected' => const Color(0xFFD74858),
      _ =>
        lot.sync == SyncEtat.local
            ? const Color(0xFF94A3BF)
            : const Color(0xFFD99A28),
    };
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  key: ValueKey('lot-status-${lot.id}'),
                  width: 5,
                  color: statusColor,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lot.serverReference ?? lot.id,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('dd/MM/yyyy').format(lot.date),
                              style: textTheme.labelSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Mine : ${lot.mineName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fact(
                              context,
                              'POIDS',
                              lot.tonnage == null
                                  ? '—'
                                  : '${NumberFormat.decimalPattern('fr').format(lot.tonnage)} kg',
                            ),
                            _fact(
                              context,
                              'PLAQUE',
                              lot.plate?.isNotEmpty == true ? lot.plate! : '—',
                            ),
                            _transportFact(context, statusColor),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fact(BuildContext context, String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 9,
            letterSpacing: 0.7,
            color: AppColors.inkSoft,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _transportFact(BuildContext context, Color statusColor) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TRANSPORT',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 9,
            letterSpacing: 0.7,
            color: AppColors.inkSoft,
          ),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 3,
          children: [
            Text(
              lot.arrive ? 'Arrivé' : 'En route',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Tooltip(
              message: switch (lot.validationStatus) {
                'validated' => 'Lot validé',
                'rejected' => 'Lot rejeté',
                _ =>
                  lot.sync == SyncEtat.local ? 'Brouillon local' : 'En attente',
              },
              child: Icon(
                switch (lot.validationStatus) {
                  'validated' => Icons.cloud_done_outlined,
                  'rejected' => Icons.cancel_outlined,
                  _ =>
                    lot.sync == SyncEtat.local
                        ? Icons.save_outlined
                        : Icons.schedule,
                },
                color: statusColor,
                size: 18,
              ),
            ),
            if (lot.score != null) _ScoreBadge(score: lot.score!),
            _SyncIcon(lot.sync),
          ],
        ),
      ],
    ),
  );
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
        'Photos en cours',
      ),
      SyncEtat.enAttente => (Icons.cloud_upload, AppColors.warn, 'À envoyer'),
      SyncEtat.echec => (Icons.cloud_off, AppColors.danger, 'Échec'),
    };
    if (icon == null) return const SizedBox.shrink();
    return Tooltip(
      message: tip!,
      child: Icon(icon, color: color, size: 17),
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
      width: 25,
      height: 25,
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: couleur, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        '$score',
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: couleur,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 260,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2,
              size: 44,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text('Aucun lot', style: Theme.of(context).textTheme.titleMedium),
          Text(
            'Appuie sur « Nouveau chargement »',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}
