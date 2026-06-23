import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = ref.read(chaineControllerProvider.notifier);
    if (!ctrl.chaineCoherente) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Chaîne de plaques incohérente (A→B→C)')));
      return;
    }
    final ok = await ctrl.persist(widget.chargementId);
    messenger.showSnackBar(SnackBar(
        content: Text(ok ? 'Transbordements enregistrés' : 'Échec enregistrement')));
  }

  @override
  Widget build(BuildContext context) {
    final chaine = ref.watch(chaineControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Transbordements')),
      body: chaine.isEmpty
          ? const Center(child: Text('Aucun transbordement (transport direct)'))
          : ListView.builder(
              itemCount: chaine.length,
              itemBuilder: (_, i) {
                final m = chaine[i];
                return ListTile(
                  leading: CircleAvatar(child: Text('${m.ordre}')),
                  title: Text(
                      '${m.plaqueAvant ?? '?'} → ${m.plaqueApres ?? '?'}'),
                  subtitle: Text(m.conforme
                      ? 'GPS conforme'
                      : 'GPS hors rayon (${kRayonTransbordementMetres.toInt()} m)'),
                  trailing: Icon(
                      m.conforme ? Icons.check_circle : Icons.error,
                      color: m.conforme ? Colors.green : Colors.orange),
                  onLongPress: () => ref
                      .read(chaineControllerProvider.notifier)
                      .removeMaillon(m.ordre),
                );
              },
            ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
              heroTag: 'addm',
              onPressed: _addMaillon,
              icon: const Icon(Icons.add),
              label: const Text('Maillon')),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
              heroTag: 'savem',
              onPressed: chaine.isEmpty ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Enregistrer')),
        ],
      ),
    );
  }
}
