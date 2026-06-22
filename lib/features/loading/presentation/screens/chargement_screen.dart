import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/loading_provider.dart';
import '../../../sync/presentation/sync_provider.dart';

class ChargementScreen extends ConsumerWidget {
  final String fournisseurId;
  const ChargementScreen({super.key, required this.fournisseurId});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Nouveau chargement'), actions: [
          IconButton(
              icon: const Icon(Icons.sync),
              onPressed: () => ref.read(triggerSyncProvider).sync()),
        ]),
        body: Center(
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Créer un chargement'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final r = await ref.read(createChargementProvider)(
                  fournisseurId: fournisseurId, now: DateTime.now());
              r.match(
                (f) => messenger.showSnackBar(
                    const SnackBar(content: Text('Erreur création'))),
                (c) => messenger.showSnackBar(
                    SnackBar(content: Text('Chargement ${c.id} créé'))),
              );
            },
          ),
        ),
      );
}
