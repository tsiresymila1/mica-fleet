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
          'Dans « Mes lots », recherchez une référence, une mine, un dépôt, une plaque ou une date. Les onglets filtrent les lots par validation. Le poids cumulé correspond aux lots affichés. Le champ « Transport » de chaque carte désigne le dépôt rattaché au lot ; « À renseigner » ou « À attribuer » apparaît quand aucun dépôt n’est encore associé.',
        ),
        _section(
          context,
          Icons.tune,
          'Couleurs des lots',
          'La bande à gauche est verte pour un lot validé, orange pour une validation en attente, rouge pour un lot rejeté et grise pour un brouillon conservé localement.',
        ),
        _section(
          context,
          Icons.cloud_outlined,
          'Icônes des lots',
          'La disquette indique un brouillon local. Le nuage avec une flèche indique un envoi en attente, le nuage en mouvement un envoi de photos en cours, le nuage barré un échec et le nuage coché un lot synchronisé et validé. L’horloge signale une validation en attente ; la croix, un rejet. La validation et la synchronisation sont deux états différents.',
        ),
        _section(
          context,
          Icons.stars_outlined,
          'Score de traçabilité',
          'Le nombre dans le cercle doré est le score de traçabilité attribué par le backoffice après contrôle du lot. Il apparaît seulement lorsque le serveur l’a communiqué. Ce score ne représente ni le poids ni la progression du transport.',
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
          'Les opérations sont enregistrées localement puis envoyées lors de la synchronisation. Vérifiez les icônes de chaque lot et utilisez le bouton de synchronisation de l’accueil quand la connexion revient.',
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
