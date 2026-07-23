import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../sync_history_provider.dart';
import '../sync_provider.dart';

/// Historique de synchronisation : chaque envoi vers Odoo, son état et ses
/// tentatives. Bouton pour relancer la synchronisation des éléments en attente.
class SyncHistoryScreen extends ConsumerWidget {
  const SyncHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final histo = ref.watch(syncHistoryProvider);
    final df = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Synchronisation'),
        actions: [
          IconButton(
            tooltip: 'Tout synchroniser',
            icon: const Icon(Icons.sync),
            onPressed: () async {
              await ref.read(triggerSyncProvider).sync();
              ref.invalidate(syncHistoryProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(syncHistoryProvider),
        child: histo.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (items) {
            if (items.isEmpty) return _Empty();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final h = items[i];
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.push('/sync-detail/${h.opId}'),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  h.entityId,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium!
                                      .copyWith(fontSize: 15),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: AppColors.inkSoft,
                              ),
                              _statutPill(h.status),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _ligne('Créé', df.format(h.createdAt)),
                          if (h.syncedAt != null)
                            _ligne('Envoyé', df.format(h.syncedAt!)),
                          if (h.odooId != null)
                            _ligne('Réf. Odoo', '#${h.odooId}'),
                          if (h.status != 'synced' && h.attempts > 0)
                            _ligne('Tentatives', '${h.attempts}'),
                          if (h.status != 'synced' && h.nextRetryAt != null)
                            _ligne('Prochain essai', df.format(h.nextRetryAt!)),
                          if (h.lastError != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              h.lastError!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium!
                                  .copyWith(color: AppColors.danger),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

Widget _statutPill(String s) => switch (s) {
  'synced' => const StatusPill(kind: PillKind.ok, label: 'Envoyé'),
  'failed' => const StatusPill(kind: PillKind.danger, label: 'Échec'),
  'syncing' => const StatusPill(kind: PillKind.neutral, label: 'En cours'),
  _ => const StatusPill(kind: PillKind.warn, label: 'En attente'),
};

Widget _ligne(String k, String v) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 2),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(k, style: const TextStyle(color: AppColors.inkSoft)),
      Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  ),
);

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const SizedBox(height: 120),
      Center(
        child: Column(
          children: [
            const Icon(Icons.cloud_queue, size: 64, color: AppColors.inkSoft),
            const SizedBox(height: 12),
            Text(
              'Aucune synchronisation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Les lots validés apparaîtront ici',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ],
  );
}
