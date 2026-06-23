import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/error/failure.dart';
import '../providers/loading_provider.dart';
import '../../../sync/presentation/sync_provider.dart';
import '../../domain/entities/mine_chargement.dart';
import 'add_mine_screen.dart';

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
    // Démarre un nouveau chargement en mémoire dès l'ouverture.
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
          content: Text(f is ValidationFailure ? f.message : 'Échec validation'))),
      (c) {
        messenger.showSnackBar(
            SnackBar(content: Text('Chargement ${c.id} validé et synchronisé')));
        navigator.pop();
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
        title: Text(chargement == null
            ? 'Nouveau chargement'
            : 'Chargement ${chargement.id}'),
        actions: [
          IconButton(
              icon: const Icon(Icons.sync),
              onPressed: () => ref.read(triggerSyncProvider).sync()),
        ],
      ),
      body: chargement == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('${mines.length}/3 mines',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Expanded(
                  child: mines.isEmpty
                      ? const Center(child: Text('Aucune mine ajoutée'))
                      : ListView.builder(
                          itemCount: mines.length,
                          itemBuilder: (_, i) {
                            final m = mines[i];
                            return ListTile(
                              leading: CircleAvatar(child: Text('${i + 1}')),
                              title: Text(m.mineId),
                              subtitle: Text([
                                if (m.couleur != null) m.couleur,
                                if (m.plaqueOcr != null) 'Plaque ${m.plaqueOcr}',
                                if (m.quantiteEstimee != null)
                                  '${m.quantiteEstimee} kg',
                              ].whereType<String>().join(' · ')),
                              trailing: m.photo != null
                                  ? const Icon(Icons.photo, color: Colors.green)
                                  : const Icon(Icons.warning, color: Colors.orange),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: chargement == null
          ? null
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'add',
                  onPressed: peutAjouter ? _addMine : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Mine'),
                ),
                const SizedBox(width: 12),
                FloatingActionButton.extended(
                  heroTag: 'validate',
                  onPressed: mines.isEmpty ? null : _validate,
                  icon: const Icon(Icons.check),
                  label: const Text('Valider'),
                ),
              ],
            ),
    );
  }
}
