import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/geo.dart';
import '../../../../shared/ui/photo_view.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../trip/presentation/trip_provider.dart';
import '../providers/chargement_detail_provider.dart';

/// Détail en lecture seule d'un chargement : mines, transbordements, arrivée, score.
class ChargementDetailScreen extends ConsumerWidget {
  final String chargementId;
  const ChargementDetailScreen({super.key, required this.chargementId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(chargementDetailProvider(chargementId));
    return Scaffold(
      appBar: AppBar(title: Text(chargementId)),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (d) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
          children: [
            if (d.arrivee?.score != null) ...[
              Center(child: _ScoreCircle(score: d.arrivee!.score!)),
              const SizedBox(height: 20),
            ],
            _Section('Infos', [
              _kv('Date', DateFormat('dd/MM/yyyy HH:mm').format(d.date)),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Statut', style: TextStyle(color: AppColors.inkSoft)),
                const Spacer(),
                StatusPill(
                  kind: d.arrivee != null ? PillKind.ok : PillKind.neutral,
                  label: d.arrivee != null ? 'Arrivé au dépôt' : 'En cours',
                ),
              ]),
              const SizedBox(height: 8),
              _kv('Mines', '${d.mines.length}'),
            ]),
            const SizedBox(height: 16),
            StepHeader(numero: 1, titre: 'Mines (${d.mines.length})'),
            const SizedBox(height: 8),
            ...d.mines.map((m) => _MineCard(m: m)),
            const SizedBox(height: 16),
            StepHeader(
                numero: 2,
                titre: 'Transbordements (${d.transbordements.length})'),
            const SizedBox(height: 8),
            if (d.transbordements.isEmpty)
              const _Muted('Transport direct (aucun changement)')
            else
              ...d.transbordements.map((t) => _TransCard(t: t)),
            const SizedBox(height: 16),
            StepHeader(numero: 3, titre: 'Arrivée'),
            const SizedBox(height: 8),
            if (d.arrivee == null)
              const _Muted('Pas encore arrivé au dépôt')
            else
              _ArriveeCard(a: d.arrivee!),
            const SizedBox(height: 16),
            StepHeader(numero: 4, titre: 'Parcours'),
            const SizedBox(height: 8),
            _TrajetSection(chargementId: chargementId),
          ],
        ),
      ),
      bottomNavigationBar: detail.maybeWhen(
        data: (d) => d.arrivee == null
            ? SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: BigButton(
                  icon: Icons.local_shipping,
                  label: 'Continuer le transport',
                  color: AppColors.gold,
                  onPressed: () => context.push('/suivi/$chargementId'),
                ),
              )
            : null,
        orElse: () => null,
      ),
    );
  }
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: AppColors.inkSoft)),
          Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );

class _Section extends StatelessWidget {
  final String titre;
  final List<Widget> rows;
  const _Section(this.titre, this.rows);
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
        ),
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

class _MineCard extends StatelessWidget {
  final MineLine m;
  const _MineCard({required this.m});
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              PhotoThumb(path: m.photoPath),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.mineId,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text([
                      if (m.couleur != null) m.couleur,
                      if (m.plaque != null) m.plaque,
                      if (m.quantite != null) '${m.quantite} kg',
                    ].whereType<String>().join('  •  ')),
                    if (m.lat != null)
                      Text(
                          'GPS ${m.lat!.toStringAsFixed(4)}, ${m.lon!.toStringAsFixed(4)}',
                          style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _TransCard extends StatelessWidget {
  final TransLine t;
  const _TransCard({required this.t});
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          shape: const Border(),
          leading: CircleAvatar(child: Text('${t.ordre}')),
          title: Text('${t.plaqueAvant ?? '?'} → ${t.plaqueApres ?? '?'}'),
          subtitle: Text(t.conforme ? 'GPS conforme' : 'GPS hors zone'),
          trailing: StatusPill(
              kind: t.conforme ? PillKind.ok : PillKind.warn,
              label: t.conforme ? 'OK' : '!'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Row(children: [
              Expanded(child: _LabeledThumb('Déchargement', t.photoDecharge)),
              const SizedBox(width: 12),
              Expanded(child: _LabeledThumb('Rechargement', t.photoRecharge)),
            ]),
          ],
        ),
      );
}

class _ArriveeCard extends StatelessWidget {
  final ArriveeLine a;
  const _ArriveeCard({required this.a});
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          shape: const Border(),
          initiallyExpanded: true,
          leading: const Icon(Icons.warehouse, color: AppColors.primary),
          title: Text('Dépôt ${a.depotId}'),
          subtitle: Text(a.chauffeur),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _kv('Chauffeur', a.chauffeur),
            _kv('Permis', a.numPermis),
            _kv('Lot', a.numLot),
            if (a.plaqueArrivee != null) _kv('Plaque', a.plaqueArrivee!),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                kind: a.plaqueCoherente ? PillKind.ok : PillKind.warn,
                label: a.plaqueCoherente
                    ? 'Plaque cohérente'
                    : 'Plaque différente du départ',
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _LabeledThumb('Arrivée', a.photoArrivee)),
              const SizedBox(width: 12),
              Expanded(child: _LabeledThumb('Permis', a.photoPermis)),
            ]),
          ],
        ),
      );
}

class _LabeledThumb extends StatelessWidget {
  final String label;
  final String? path;
  const _LabeledThumb(this.label, this.path);
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          PhotoThumb(path: path, size: 120),
        ],
      );
}

class _TrajetSection extends ConsumerWidget {
  final String chargementId;
  const _TrajetSection({required this.chargementId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pts = ref.watch(trajetPointsProvider(chargementId));
    return pts.when(
      loading: () => const SizedBox(
          height: 80, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => const _Muted('Parcours indisponible'),
      data: (points) {
        if (points.length < 2) {
          return const _Muted('Aucun trajet enregistré');
        }
        double dist = 0;
        for (var i = 1; i < points.length; i++) {
          dist += haversineMeters(points[i - 1].latitude, points[i - 1].longitude,
              points[i].latitude, points[i].longitude);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 220,
                child: FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.all(30)),
                    interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.radoran.mica_fleet',
                    ),
                    PolylineLayer(polylines: [
                      Polyline(
                          points: points,
                          strokeWidth: 4,
                          color: AppColors.primary),
                    ]),
                    MarkerLayer(markers: [
                      _pin(points.first, AppColors.gold, Icons.play_arrow),
                      _pin(points.last, AppColors.danger, Icons.flag),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('${points.length} points · ${(dist / 1000).toStringAsFixed(1)} km',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        );
      },
    );
  }

  Marker _pin(LatLng p, Color color, IconData icon) => Marker(
        point: p,
        width: 32,
        height: 32,
        child: Icon(icon, color: color, size: 28),
      );
}

class _ScoreCircle extends StatelessWidget {
  final int score;
  const _ScoreCircle({required this.score});
  @override
  Widget build(BuildContext context) {
    final couleur = score >= 80
        ? AppColors.ok
        : score > 0
            ? AppColors.warn
            : AppColors.danger;
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: couleur.withValues(alpha: 0.12),
          border: Border.all(color: couleur, width: 6)),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$score',
              style: Theme.of(context)
                  .textTheme
                  .displaySmall!
                  .copyWith(color: couleur, fontSize: 40)),
          const Text('/ 100', style: TextStyle(color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}
