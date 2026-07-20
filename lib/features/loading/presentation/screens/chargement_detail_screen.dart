import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/photo_view.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../providers/chargement_detail_provider.dart';

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
                      trailing: StatusPill(
                          kind: t.conforme ? PillKind.ok : PillKind.warn,
                          label: t.conforme ? 'GPS ok' : 'Hors zone'),
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StatusPill(
                          kind: d.arrivee!.plaqueCoherente
                              ? PillKind.ok
                              : PillKind.warn,
                          label: d.arrivee!.plaqueCoherente
                              ? 'Plaque cohérente'
                              : 'Plaque différente du départ',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
            : null,
        orElse: () => null,
      ),
    );
  }
}

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
