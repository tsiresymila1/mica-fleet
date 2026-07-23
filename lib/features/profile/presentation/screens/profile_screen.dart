import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../depot/presentation/providers/depot_provider.dart';
import '../../../mines/presentation/providers/mines_provider.dart';

/// Profil du fournisseur connecté : ses mines et ses dépôts autorisés
/// (référentiel synchronisé depuis Odoo). Lecture seule.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fournisseur = ref.watch(authControllerProvider);
    final mines = ref.watch(minesProvider);
    final depots = ref.watch(activeDepotsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mon compte')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(minesProvider);
          ref.invalidate(activeDepotsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            _Identite(
                nom: fournisseur?.nom ?? 'Fournisseur',
                id: fournisseur?.id ?? ''),
            const SizedBox(height: 24),
            StepHeader(
                numero: 1, titre: 'Mes mines', sousTitre: 'Lieux de chargement'),
            const SizedBox(height: 8),
            mines.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const _Muted('Référentiel indisponible'),
              data: (list) => list.isEmpty
                  ? const _Muted('Aucune mine')
                  : Column(
                      children: list
                          .map((m) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ActionTile(
                                  icon: Icons.terrain,
                                  color: AppColors.gold,
                                  titre: m.nom,
                                  sousTitre: [
                                    if (m.commune != null) m.commune!,
                                    if (m.region != null) m.region!,
                                  ].join(' · '),
                                  trailing: _Coord(lat: m.lat, lon: m.lon),
                                ),
                              ))
                          .toList(),
                    ),
            ),
            const SizedBox(height: 24),
            StepHeader(
                numero: 2, titre: 'Mes dépôts', sousTitre: 'Lieux de livraison'),
            const SizedBox(height: 8),
            depots.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const _Muted('Référentiel indisponible'),
              data: (list) => list.isEmpty
                  ? const _Muted('Aucun dépôt')
                  : Column(
                      children: list
                          .map((d) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ActionTile(
                                  icon: Icons.warehouse,
                                  color: AppColors.primary,
                                  titre: d.nom,
                                  trailing: _Coord(lat: d.lat, lon: d.lon),
                                ),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Identite extends StatelessWidget {
  final String nom;
  final String id;
  const _Identite({required this.nom, required this.id});

  @override
  Widget build(BuildContext context) {
    final initiale = nom.trim().isEmpty ? '?' : nom.trim()[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.gold,
          child: Text(initiale,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall!
                  .copyWith(color: Colors.white)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nom,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge!
                      .copyWith(color: Colors.white)),
              Text('ID : $id', style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ]),
    );
  }
}

/// GPS compact à droite d'une tuile.
class _Coord extends StatelessWidget {
  final double lat;
  final double lon;
  const _Coord({required this.lat, required this.lon});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place, size: 16, color: AppColors.inkSoft),
          Text('${lat.toStringAsFixed(3)}\n${lon.toStringAsFixed(3)}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      );
}

class _Muted extends StatelessWidget {
  final String texte;
  const _Muted(this.texte);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(texte, style: Theme.of(context).textTheme.bodyMedium),
      );
}
