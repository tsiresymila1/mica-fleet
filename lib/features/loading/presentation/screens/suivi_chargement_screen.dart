import 'package:flutter/material.dart';
import '../../../transport/presentation/screens/transbordement_screen.dart';
import '../../../depot/presentation/screens/arrivee_screen.dart';

/// Hub d'un chargement validé : accès transbordements et arrivée au dépôt.
class SuiviChargementScreen extends StatelessWidget {
  final String chargementId;
  const SuiviChargementScreen({super.key, required this.chargementId});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Suivi $chargementId')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.local_shipping),
                title: const Text('Transbordements'),
                subtitle: const Text('Chaîne de changements de camion (0..N)'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        TransbordementScreen(chargementId: chargementId))),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.warehouse),
                title: const Text('Arrivée au dépôt'),
                subtitle: const Text('Validation chauffeur, permis, lot, GPS'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ArriveeScreen(chargementId: chargementId))),
              ),
            ),
          ],
        ),
      );
}
