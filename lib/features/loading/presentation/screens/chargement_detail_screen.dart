import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../providers/chargement_detail_provider.dart';
import 'suivi_chargement_screen.dart';

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
              _kv('Statut', d.statut),
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
              ...d.transbordements.map((t) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${t.ordre}')),
                      title: Text('${t.plaqueAvant ?? '?'} → ${t.plaqueApres ?? '?'}'),
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
              _ArriveeCard(a: d.arrivee!),
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
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          SuiviChargementScreen(chargementId: chargementId))),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: m.photoPath != null && File(m.photoPath!).existsSync()
                      ? Image.file(File(m.photoPath!), fit: BoxFit.cover)
                      : Container(
                          color: AppColors.line,
                          child: const Icon(Icons.image_not_supported,
                              color: AppColors.inkSoft)),
                ),
              ),
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

class _ArriveeCard extends StatelessWidget {
  final ArriveeLine a;
  const _ArriveeCard({required this.a});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kv('Dépôt', a.depotId),
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
            ],
          ),
        ),
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
