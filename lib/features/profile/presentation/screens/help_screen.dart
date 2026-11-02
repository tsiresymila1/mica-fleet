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
        Text('Guide rapide', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Les repères utiles pour suivre vos lots.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        _section(context, 'Retrouver un lot', Icons.search, [
          _item(
            context,
            _number(context, '1'),
            'Rechercher',
            'Référence, mine, dépôt, plaque ou date.',
          ),
          _item(
            context,
            _number(context, '2'),
            'Filtrer',
            'Choisissez Tous, Attente, Validés ou Rejetés.',
          ),
          _item(
            context,
            _number(context, '3'),
            'Ouvrir',
            'Touchez un lot pour consulter son détail et ses photos.',
          ),
        ]),
        _section(context, 'Lire une carte', Icons.inventory_2_outlined, [
          Text(
            'EXEMPLE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          _exampleCard(context),
          const SizedBox(height: 14),
          _item(
            context,
            const Icon(Icons.local_shipping_outlined, color: AppColors.primary),
            'Transport = dépôt',
            'Le dépôt rattaché au lot. « À renseigner » apparaît avant l’arrivée ; « -- » indique qu’aucun dépôt n’est encore associé.',
          ),
          _item(
            context,
            const Icon(Icons.scale_outlined, color: AppColors.primary),
            'Poids cumulé',
            'En haut de Mes lots : somme des lots affichés après filtrage.',
          ),
        ]),
        _section(
          context,
          'Bande à gauche · validation',
          Icons.format_color_fill_outlined,
          [
            _item(context, _stripe(AppColors.ok), 'Vert', 'Lot validé'),
            _item(
              context,
              _stripe(AppColors.warn),
              'Orange',
              'Validation en attente',
            ),
            _item(context, _stripe(AppColors.danger), 'Rouge', 'Lot rejeté'),
            _item(
              context,
              _stripe(const Color(0xFF94A3BF)),
              'Gris',
              'Brouillon local',
            ),
          ],
        ),
        _section(
          context,
          'Icône à droite · état du lot',
          Icons.cloud_outlined,
          [
            _item(
              context,
              const Icon(Icons.save_outlined, color: Color(0xFF94A3BF)),
              'Disquette',
              'Brouillon sur cet appareil',
            ),
            _item(
              context,
              const Icon(Icons.cloud_upload, color: AppColors.warn),
              'Nuage avec flèche',
              'En attente de synchronisation',
            ),
            _item(
              context,
              const Icon(Icons.cloud_sync, color: AppColors.inkSoft),
              'Nuage en mouvement',
              'Photos en cours d’envoi',
            ),
            _item(
              context,
              const Icon(Icons.cloud_off, color: AppColors.danger),
              'Nuage barré',
              'Envoi échoué : relancez la synchronisation',
            ),
            _item(
              context,
              Image.asset(
                'assets/icons/lot_cloud_check.png',
                width: 24,
                height: 20,
                fit: BoxFit.contain,
              ),
              'Nuage coché',
              'Lot synchronisé et validé',
            ),
            _item(
              context,
              const Icon(Icons.schedule, color: AppColors.warn),
              'Horloge',
              'Validation en attente',
            ),
            _item(
              context,
              const Icon(Icons.close, color: AppColors.danger),
              'Croix',
              'Lot rejeté',
            ),
          ],
        ),
        _section(context, 'Score de traçabilité', Icons.stars_outlined, [
          _item(
            context,
            _score(context),
            'Exemple de score',
            'Attribué par le backoffice après contrôle. Il apparaît quand le serveur le communique.',
          ),
          Text(
            'Ce nombre n’est ni le poids ni la progression du transport.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ]),
        _section(context, 'Autres actions', Icons.apps_outlined, [
          _item(
            context,
            const Icon(Icons.location_on_outlined, color: AppColors.primary),
            'Mines et dépôts',
            'Passez d’un onglet à l’autre, puis recherchez un site.',
          ),
          _item(
            context,
            const Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
            'Proposer une mine',
            'Saisissez son nom et prenez cinq photos. Elle sera utilisable après validation.',
          ),
          _item(
            context,
            const Icon(Icons.wifi_off_outlined, color: AppColors.primary),
            'Hors connexion',
            'Vos saisies restent sur l’appareil. Synchronisez depuis l’accueil quand le réseau revient.',
          ),
        ]),
      ],
    ),
  );

  Widget _section(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> children,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: AppColors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );

  Widget _item(
    BuildContext context,
    Widget symbol,
    String title,
    String description,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 28, height: 28, child: Center(child: symbol)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _number(BuildContext context, String number) => CircleAvatar(
    radius: 13,
    backgroundColor: AppColors.primaryLight,
    child: Text(
      number,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _stripe(Color color) => Container(
    width: 5,
    height: 26,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );

  Widget _exampleCard(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.paper,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(10),
    ),
    child: IntrinsicHeight(
      child: Row(
        children: [
          Container(width: 5, color: AppColors.ok),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'LOT-001',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 11,
                        color: AppColors.inkSoft,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '14/10 · 07:15',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.inkSoft,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Mine : Mine Kely',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const Divider(height: 17),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _exampleFact(context, 'POIDS', '5 000 kg'),
                            ),
                            Expanded(
                              child: _exampleFact(
                                context,
                                'PLAQUE',
                                '2168 TBG',
                              ),
                            ),
                            Expanded(
                              child: _exampleFact(
                                context,
                                'TRANSPORT',
                                'Dépôt AMB',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Column(
                        children: [
                          _score(context),
                          const SizedBox(height: 4),
                          Image.asset(
                            'assets/icons/lot_cloud_check.png',
                            width: 22,
                            height: 18,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _exampleFact(BuildContext context, String label, String value) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.inkSoft,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );

  Widget _score(BuildContext context) => Container(
    width: 34,
    height: 34,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7EB),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFD39A2F), width: 2),
    ),
    child: Text(
      '65',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: const Color(0xFFCF8F16),
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
