import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Aide')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
      children: [
        Text(
          'Comment utiliser RADORAN',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Retrouvez les informations utiles pour suivre vos chargements et vos sites.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        _section(
          context,
          Icons.search,
          'Retrouver un chargement',
          'Dans « Mes lots », recherchez une référence, une mine, une plaque ou une date. Les onglets filtrent les lots par validation. Le poids cumulé correspond aux lots affichés.',
        ),
        _section(
          context,
          Icons.tune,
          'Comprendre les repères',
          'La bordure verte indique un lot validé, l’orange un lot en attente, la rouge un lot rejeté et la grise un brouillon local. L’icône de nuage indique l’état de synchronisation, qui est distinct de la validation.',
        ),
        _section(
          context,
          Icons.location_on_outlined,
          'Mines et dépôts',
          'Passez d’un onglet à l’autre et recherchez un site par ses informations disponibles. Pour une mine, vous pouvez rechercher son nom, sa référence, sa région, son district, sa commune ou son fokontany. Touchez une mine pour consulter ses lots.',
        ),
        _section(
          context,
          Icons.add_a_photo_outlined,
          'Proposer une mine',
          'Indiquez son nom et prenez au moins cinq photos des positions. Les données de localisation sont enregistrées avec les photos pour la validation, mais les coordonnées ne sont pas affichées dans l’application. La mine sera utilisable après validation.',
        ),
        _section(
          context,
          Icons.cloud_outlined,
          'Travailler hors connexion',
          'Les opérations sont enregistrées localement puis envoyées lors de la synchronisation. Vérifiez l’icône de nuage sur les lots et utilisez le bouton de synchronisation de l’accueil quand la connexion revient.',
        ),
      ],
    ),
  );

  Widget _section(
    BuildContext context,
    IconData icon,
    String title,
    String body,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(body, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
