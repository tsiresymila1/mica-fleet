import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../providers/loading_provider.dart';
import '../../../sync/presentation/sync_provider.dart';
import '../../domain/entities/mine_chargement.dart';
import 'add_mine_screen.dart';
import 'suivi_chargement_screen.dart';

class ChargementScreen extends ConsumerStatefulWidget {
  final String fournisseurId;
  const ChargementScreen({super.key, required this.fournisseurId});
  @override
  ConsumerState<ChargementScreen> createState() => _ChargementScreenState();
}

class _ChargementScreenState extends ConsumerState<ChargementScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref
        .read(chargementControllerProvider.notifier)
        .startNew(widget.fournisseurId));
  }

  Future<void> _addMine() async {
    final messenger = ScaffoldMessenger.of(context);
    final mine = await Navigator.of(context).push<MineChargement>(
        MaterialPageRoute(builder: (_) => const AddMineScreen()));
    if (mine == null) return;
    final res = ref.read(chargementControllerProvider.notifier).addMine(mine);
    res.match(
      (f) => messenger.showSnackBar(SnackBar(
          content: Text(f is ValidationFailure ? f.message : 'Erreur'))),
      (_) {},
    );
  }

  Future<void> _validate() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final res = await ref
        .read(chargementControllerProvider.notifier)
        .validateAndPersist();
    res.match(
      (f) => messenger.showSnackBar(SnackBar(
          content:
              Text(f is ValidationFailure ? f.message : 'Échec validation'))),
      (c) {
        messenger.showSnackBar(
            SnackBar(content: Text('Chargement ${c.id} enregistré')));
        navigator.pushReplacement(MaterialPageRoute(
            builder: (_) => SuiviChargementScreen(chargementId: c.id)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chargement = ref.watch(chargementControllerProvider);
    final mines = chargement?.mines ?? const <MineChargement>[];
    final peutAjouter = chargement?.peutAjouterMine ?? false;

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
                    titre: 'Mes mines',
                    sousTitre: 'Ajoute de 1 à 3 mines avec photo',
                  ),
                ),
                // Compteur de progression visuel (pastilles)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                          height: 8,
                          decoration: BoxDecoration(
                            color: i < mines.length
                                ? AppColors.primary
                                : AppColors.line,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: mines.isEmpty
                      ? _EmptyMines()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                          itemCount: mines.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final m = mines[i];
                            return ActionTile(
                              icon: Icons.landscape,
                              color: AppColors.primary,
                              titre: 'Mine ${i + 1}',
                              sousTitre: [
                                if (m.couleur != null) m.couleur,
                                if (m.plaqueOcr != null) m.plaqueOcr,
                                if (m.quantiteEstimee != null)
                                  '${m.quantiteEstimee} kg',
                              ].whereType<String>().join('  •  '),
                              trailing: StatusPill(
                                kind: m.photo != null
                                    ? PillKind.ok
                                    : PillKind.warn,
                                label: m.photo != null ? 'Photo' : 'Manque',
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
                    onPressed: peutAjouter ? _addMine : null,
                    icon: const Icon(Icons.add_a_photo, size: 24),
                    label: const Text('Ajouter'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BigButton(
                    icon: Icons.check,
                    label: 'Valider',
                    onPressed: mines.isEmpty ? null : _validate,
                  ),
                ),
              ]),
            ),
    );
  }
}

class _EmptyMines extends StatelessWidget {
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
            Text('pour photographier la première mine',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}
