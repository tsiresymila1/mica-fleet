import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/loading_provider.dart';
import '../../../sync/presentation/sync_provider.dart';
import '../../domain/entities/lot.dart';
import 'add_mine_screen.dart';
import 'suivi_chargement_screen.dart';

class ChargementScreen extends ConsumerStatefulWidget {
  const ChargementScreen({super.key});
  @override
  ConsumerState<ChargementScreen> createState() => _ChargementScreenState();
}

class _ChargementScreenState extends ConsumerState<ChargementScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final id = ref.read(authControllerProvider)?.id;
      if (id != null) {
        ref.read(chargementControllerProvider.notifier).startNew(id);
      }
    });
  }

  Future<void> _addLot() async {
    final lot = await Navigator.of(context)
        .push<Lot>(MaterialPageRoute(builder: (_) => const AddMineScreen()));
    if (lot == null) return;
    final res = ref.read(chargementControllerProvider.notifier).addLot(lot);
    res.match(
      (f) {
        if (mounted) {
          showAppMessage(context, f is ValidationFailure ? f.message : 'Erreur',
              kind: AppMsgKind.warning);
        }
      },
      (_) {},
    );
  }

  Future<void> _validate() async {
    final res = await ref
        .read(chargementControllerProvider.notifier)
        .validateAndPersist();
    if (!mounted) return;
    res.match(
      (f) => showAppMessage(
          context, f is ValidationFailure ? f.message : 'Échec validation',
          kind: AppMsgKind.error),
      (c) async {
        await showAppMessage(
            context, '${c.lots.length} lot(s) enregistré(s) — ${c.id}',
            kind: AppMsgKind.success);
        if (mounted) context.pushReplacement('/suivi/${c.id}');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chargement = ref.watch(chargementControllerProvider);
    final lots = chargement?.lots ?? const <Lot>[];
    final peutAjouter = chargement?.peutAjouterLot ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chargement'),
        actions: [
          IconButton(
              tooltip: 'Synchroniser',
              icon: const Icon(Icons.sync),
              onPressed: () => ref.read(triggerSyncProvider).sync()),
        ],
      ),
      body: chargement == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: StepHeader(
                    numero: 1,
                    titre: 'Mes lots',
                    sousTitre: '1 mine = 1 lot (quantité figée au départ)',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                          height: 8,
                          decoration: BoxDecoration(
                            color: i < lots.length
                                ? AppColors.primary
                                : AppColors.line,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    onChanged: (v) => ref
                        .read(chargementControllerProvider.notifier)
                        .setLotReference(v),
                    decoration: const InputDecoration(
                      labelText: 'Référence de lot (optionnel)',
                      prefixIcon: Icon(Icons.folder_outlined),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: lots.isEmpty
                      ? _EmptyLots()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                          itemCount: lots.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final l = lots[i];
                            return ActionTile(
                              icon: Icons.inventory_2,
                              color: AppColors.primary,
                              titre: 'Lot ${i + 1} · ${l.mineId}',
                              sousTitre: [
                                if (l.couleur != null) l.couleur,
                                if (l.plaqueDepart != null) l.plaqueDepart,
                                if (l.quantiteEstimee != null)
                                  '${l.quantiteEstimee} kg',
                              ].whereType<String>().join('  •  '),
                              trailing: StatusPill(
                                kind: l.photo != null
                                    ? PillKind.ok
                                    : PillKind.warn,
                                label: l.photo != null ? 'Photo' : 'Manque',
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: chargement == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: peutAjouter ? _addLot : null,
                    icon: const Icon(Icons.add_a_photo, size: 24),
                    label: const Text('Ajouter'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BigButton(
                    icon: Icons.check,
                    label: 'Valider',
                    onPressed: lots.isEmpty ? null : _validate,
                  ),
                ),
              ]),
            ),
    );
  }
}

class _EmptyLots extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle),
              child: const Icon(Icons.add_a_photo,
                  size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text('Appuie sur « Ajouter »',
                style: Theme.of(context).textTheme.titleMedium),
            Text('pour créer le premier lot',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}
