import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../transport/presentation/screens/transbordement_screen.dart';
import '../../../depot/presentation/screens/arrivee_screen.dart';

/// Hub d'un chargement validé : accès transbordements et arrivée au dépôt.
class SuiviChargementScreen extends StatelessWidget {
  final String chargementId;
  const SuiviChargementScreen({super.key, required this.chargementId});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mon transport')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.ok.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.check_circle, color: AppColors.ok, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Chargement enregistré',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(chargementId,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: StepHeader(numero: 2, titre: 'Pendant le transport'),
            ),
            ActionTile(
              icon: Icons.local_shipping,
              color: AppColors.gold,
              titre: 'Changer de camion',
              sousTitre: 'Si tu transvases la marchandise',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      TransbordementScreen(chargementId: chargementId))),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 12, bottom: 12),
              child: StepHeader(numero: 3, titre: 'À l\'arrivée'),
            ),
            ActionTile(
              icon: Icons.warehouse,
              color: AppColors.primary,
              titre: 'Arrivée au dépôt',
              sousTitre: 'Chauffeur, permis, lot et photo',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ArriveeScreen(chargementId: chargementId))),
            ),
          ],
        ),
      );
}
