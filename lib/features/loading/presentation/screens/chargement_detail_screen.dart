import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/photo_view.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../sync/presentation/sync_provider.dart';
import '../../../transport/presentation/providers/transport_provider.dart';
import '../../../trip/presentation/trip_provider.dart';
import '../providers/chargement_detail_provider.dart';

/// Supprime un maillon de la chaîne d'un lot (renumérote le reste), après
/// confirmation. Autorisé seulement tant que le lot est en cours.
Future<void> _supprimerMaillon(
    BuildContext context, WidgetRef ref, String lotId, int ordre) async {
  final ok = await showConfirm(
      context, 'Supprimer le changement de camion n°$ordre ?',
      titre: 'Supprimer', confirmLabel: 'Supprimer', danger: true);
  if (!ok) return;
  final repo = ref.read(transportRepoProvider);
  final chaine = await repo.chaineFor(lotId);
  final restante = ref.read(removeTransbordementProvider)(chaine, ordre);
  final validee = ref.read(validateTransbordementProvider)(
      restante, kRayonTransbordementMetres);
  final res = await repo.persistChaine(lotId, validee);
  ref.invalidate(lotDetailProvider(lotId));
  if (context.mounted) {
    await showAppMessage(
        context,
        res.isRight() ? 'Changement supprimé' : 'Suppression impossible',
        kind: res.isRight() ? AppMsgKind.success : AppMsgKind.error);
  }
}

/// Détail d'UN LOT : origine (une mine), ses camions, son arrivée, son score.
class ChargementDetailScreen extends ConsumerWidget {
  final String lotId;
  const ChargementDetailScreen({super.key, required this.lotId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(lotDetailProvider(lotId));
    return Scaffold(
      appBar: AppBar(title: Text(lotId)),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (d) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
          children: [
            if (d.score != null) ...[
              Center(child: _ScoreCircle(score: d.score!)),
              const SizedBox(height: 20),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _kv('Session', d.sessionId),
                  _kv('Date', DateFormat('dd/MM/yyyy HH:mm').format(d.date)),
                  _kv('Statut', d.statut),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _syncPill(d.sync),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            StepHeader(numero: 1, titre: 'Origine (1 mine)'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  GestureDetector(
                    onTap: d.photoPath == null
                        ? null
                        : () => openPhoto(context, d.photoPath!),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: d.photoPath != null &&
                                File(d.photoPath!).existsSync()
                            ? Hero(
                                tag: d.photoPath!,
                                child: Image.file(File(d.photoPath!),
                                    fit: BoxFit.cover))
                            : Container(
                                color: AppColors.line,
                                child: const Icon(Icons.image_not_supported,
                                    color: AppColors.inkSoft)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.mineId,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text([
                          if (d.couleur != null) d.couleur,
                          if (d.plaqueDepart != null) d.plaqueDepart,
                          if (d.quantite != null) '${d.quantite} kg',
                        ].whereType<String>().join('  •  ')),
                        if (d.lat != null)
                          Text(
                              'GPS ${d.lat!.toStringAsFixed(4)}, ${d.lon!.toStringAsFixed(4)}',
                              style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            StepHeader(
                numero: 2,
                titre: 'Camions (${d.transbordements.length} changement(s))'),
            const SizedBox(height: 8),
            if (d.transbordements.isEmpty)
              const _Muted('Transport direct (aucun changement)')
            else
              ...d.transbordements.map((t) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${t.ordre}')),
                      title: Text(
                          '${t.plaqueAvant ?? '?'} → ${t.plaqueApres ?? '?'}'),
                      subtitle: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: StatusPill(
                              kind: t.conforme ? PillKind.ok : PillKind.warn,
                              label: t.conforme ? 'GPS ok' : 'Hors zone'),
                        ),
                      ),
                      // Correction possible tant que le lot n'est pas arrivé.
                      trailing: d.statut == 'en_cours'
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Corriger',
                                onPressed: () async {
                                  await context.push(
                                      '/transbordement/${d.id}?ordre=${t.ordre}');
                                  ref.invalidate(lotDetailProvider(d.id));
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: AppColors.danger),
                                tooltip: 'Supprimer',
                                onPressed: () =>
                                    _supprimerMaillon(context, ref, d.id, t.ordre),
                              ),
                            ])
                          : null,
                    ),
                  )),
            const SizedBox(height: 16),
            StepHeader(numero: 3, titre: 'Arrivée'),
            const SizedBox(height: 8),
            if (d.arrivee == null)
              const _Muted('Pas encore arrivé au dépôt')
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _kv('Dépôt', d.arrivee!.depotId),
                      _kv('Chauffeur', d.arrivee!.chauffeur),
                      _kv('Permis', d.arrivee!.numPermis),
                      _kv('N° de lot', d.arrivee!.numLot),
                      if (d.arrivee!.plaqueArrivee != null)
                        _kv('Plaque', d.arrivee!.plaqueArrivee!),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          StatusPill(
                            kind: d.arrivee!.plaqueCoherente
                                ? PillKind.ok
                                : PillKind.warn,
                            label: d.arrivee!.plaqueCoherente
                                ? 'Plaque cohérente'
                                : 'Plaque différente du départ',
                          ),
                          _gpsPill(d.arrivee!.statutGps),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            StepHeader(numero: 4, titre: 'Trajet parcouru'),
            const SizedBox(height: 8),
            _TrajetCard(sessionId: d.sessionId),
          ],
        ),
      ),
      bottomNavigationBar: detail.maybeWhen(
        data: (d) => d.arrivee == null
            ? SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BigButton(
                      icon: Icons.local_shipping,
                      label: 'Changer de camion',
                      color: AppColors.gold,
                      onPressed: () async {
                        await context.push('/transbordement/$lotId');
                        ref.invalidate(lotDetailProvider(lotId));
                      },
                    ),
                    const SizedBox(height: 8),
                    BigButton(
                      icon: Icons.warehouse,
                      label: 'Arrivée au dépôt',
                      onPressed: () => context.push('/arrivee/$lotId'),
                    ),
                  ],
                ),
              )
            : (d.renvoyable
                ? SafeArea(
                    minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: _SyncButton(lotId: lotId),
                  )
                : null),
        orElse: () => null,
      ),
    );
  }
}

/// Carte de la trace GPS de la session (points espacés >20 m). Départ en vert,
/// arrivée en rouge, tracé bleu entre les deux.
class _TrajetCard extends ConsumerWidget {
  final String sessionId;
  const _TrajetCard({required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(trajetPointsProvider(sessionId));
    return points.when(
      loading: () => const SizedBox(
          height: 60, child: Center(child: CircularProgressIndicator())),
      error: (_, _) => const _Muted('Trajet indisponible'),
      data: (pts) {
        if (pts.length < 2) {
          return const _Muted('Pas de trace GPS enregistrée');
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 220,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(pts),
                  padding: const EdgeInsets.all(30),
                ),
                interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'net.radoran.mica',
                ),
                PolylineLayer(polylines: [
                  Polyline(
                      points: pts,
                      strokeWidth: 4,
                      color: AppColors.primary),
                ]),
                MarkerLayer(markers: [
                  Marker(
                    point: pts.first,
                    width: 34,
                    height: 34,
                    child: const Icon(Icons.trip_origin,
                        color: AppColors.ok, size: 28),
                  ),
                  Marker(
                    point: pts.last,
                    width: 34,
                    height: 34,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on,
                        color: AppColors.danger, size: 34),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pastille de l'état de synchronisation du lot.
Widget _syncPill(SyncEtat s) => switch (s) {
      SyncEtat.synchronise =>
        const StatusPill(kind: PillKind.ok, label: 'Synchronisé'),
      SyncEtat.envoiPhotos =>
        const StatusPill(kind: PillKind.neutral, label: 'Photos en cours'),
      SyncEtat.enAttente =>
        const StatusPill(kind: PillKind.warn, label: 'À envoyer'),
      SyncEtat.echec =>
        const StatusPill(kind: PillKind.danger, label: 'Échec — à renvoyer'),
      SyncEtat.local =>
        const StatusPill(kind: PillKind.neutral, label: 'Non envoyé'),
    };

/// Bouton d'envoi manuel. Désactive pendant l'envoi (anti double-tap) ; le
/// double envoi réel est déjà empêché par le claim atomique + l'idempotence
/// Odoo. Déclenche le même moteur de sync que l'arrière-plan.
class _SyncButton extends ConsumerStatefulWidget {
  final String lotId;
  const _SyncButton({required this.lotId});
  @override
  ConsumerState<_SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends ConsumerState<_SyncButton> {
  bool _envoi = false;

  Future<void> _envoyer() async {
    setState(() => _envoi = true);
    try {
      await ref.read(triggerSyncProvider).sync();
      ref.invalidate(lotDetailProvider(widget.lotId));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) => BigButton(
        icon: _envoi ? Icons.hourglass_top : Icons.cloud_upload,
        label: _envoi ? 'Envoi en cours…' : 'Envoyer maintenant',
        onPressed: _envoi ? null : _envoyer,
      );
}

/// Pastille du statut GPS d'arrivée (valide / hors zone / non vérifiable).
Widget _gpsPill(String statut) => switch (statut) {
      'valide' => const StatusPill(kind: PillKind.ok, label: 'GPS validé'),
      'hors_zone' =>
        const StatusPill(kind: PillKind.warn, label: 'Hors zone dépôt'),
      _ => const StatusPill(
          kind: PillKind.neutral, label: 'GPS non vérifiable'),
    };

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: AppColors.inkSoft)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );

class _Muted extends StatelessWidget {
  final String texte;
  const _Muted(this.texte);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(texte, style: Theme.of(context).textTheme.bodyMedium),
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
