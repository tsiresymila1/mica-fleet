import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/capture_photo_screen.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../../../capture/presentation/providers/capture_providers.dart';
import '../../../trip/presentation/sim_session.dart';
import '../../domain/entities/transbordement.dart';
import '../providers/transport_provider.dart';

/// Changement de camion : on choisit QUELS LOTS montent sur le camion suivant.
/// Chaque lot sélectionné reçoit un maillon dans sa propre chaîne.
class TransbordementScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const TransbordementScreen({super.key, required this.sessionId});
  @override
  ConsumerState<TransbordementScreen> createState() =>
      _TransbordementScreenState();
}

class _TransbordementScreenState extends ConsumerState<TransbordementScreen> {
  final _avantCtrl = TextEditingController();
  final _apresCtrl = TextEditingController();
  CapturedPhoto? _decharge;
  CapturedPhoto? _recharge;
  final Set<String> _selection = {};
  bool _saving = false;

  @override
  void dispose() {
    _avantCtrl.dispose();
    _apresCtrl.dispose();
    super.dispose();
  }

  Future<CapturedPhoto?> _capture(String titre) => Navigator.of(context)
      .push<CapturedPhoto>(
          MaterialPageRoute(builder: (_) => CapturePhotoScreen(titre: titre)));

  Future<void> _fillAvant(String path) async {
    if (_avantCtrl.text.trim().isNotEmpty) return;
    final sim = ref.read(simSessionProvider);
    final p = sim != null
        ? ref.read(simSessionProvider.notifier).plate
        : await ref.read(plateOcrServiceProvider).readPlate(path);
    if (p != null && mounted) _avantCtrl.text = p;
  }

  Future<void> _fillApres(String path) async {
    if (_apresCtrl.text.trim().isNotEmpty) return;
    final sim = ref.read(simSessionProvider);
    final p = sim != null
        ? ref.read(simSessionProvider.notifier).rotateTruck()
        : await ref.read(plateOcrServiceProvider).readPlate(path);
    if (p != null && mounted) _apresCtrl.text = p;
  }

  Future<void> _save() async {
    if (_decharge == null || _recharge == null) {
      await showAppMessage(
          context, 'Photos déchargement et rechargement obligatoires',
          kind: AppMsgKind.warning);
      return;
    }
    if (_selection.isEmpty) {
      await showAppMessage(context, 'Choisis au moins un lot à transborder',
          kind: AppMsgKind.warning);
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(transportRepoProvider);
      final valider = ref.read(validateTransbordementProvider);
      for (final lotId in _selection) {
        final chaine = await repo.chaineFor(lotId);
        final maillon = Transbordement(
          ordre: chaine.length + 1,
          plaqueAvant: _avantCtrl.text.trim().isEmpty
              ? null
              : _avantCtrl.text.trim(),
          plaqueApres: _apresCtrl.text.trim().isEmpty
              ? null
              : _apresCtrl.text.trim(),
          gpsDechargeLat: _decharge!.lat,
          gpsDechargeLon: _decharge!.lon,
          gpsRechargeLat: _recharge!.lat,
          gpsRechargeLon: _recharge!.lon,
        );
        final nouvelle =
            valider([...chaine, maillon], kRayonTransbordementMetres);
        await repo.persistChaine(lotId, nouvelle);
      }
      ref.invalidate(lotsEnCoursProvider(widget.sessionId));
      if (!mounted) return;
      await showAppMessage(
          context, '${_selection.length} lot(s) transbordé(s)',
          kind: AppMsgKind.success);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lots = ref.watch(lotsEnCoursProvider(widget.sessionId));
    return Scaffold(
      appBar: AppBar(title: const Text('Changement de camion')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          StepHeader(
              numero: 1,
              titre: 'Le camion',
              sousTitre: 'Photos + plaques avant / après'),
          const SizedBox(height: 12),
          ActionTile(
            icon: _decharge == null ? Icons.camera_alt : Icons.check_circle,
            color: _decharge == null ? AppColors.primary : AppColors.ok,
            titre: 'Photo déchargement',
            sousTitre: _decharge == null
                ? 'Camion qui décharge'
                : 'GPS ${_decharge!.lat.toStringAsFixed(4)}, ${_decharge!.lon.toStringAsFixed(4)}',
            onTap: () async {
              final p = await _capture('Déchargement');
              if (p != null) {
                setState(() => _decharge = p);
                await _fillAvant(p.path);
              }
            },
          ),
          const SizedBox(height: 8),
          TextField(
              controller: _avantCtrl,
              decoration: const InputDecoration(
                  labelText: 'Plaque camion avant',
                  prefixIcon: Icon(Icons.directions_car))),
          const SizedBox(height: 16),
          ActionTile(
            icon: _recharge == null ? Icons.camera_alt : Icons.check_circle,
            color: _recharge == null ? AppColors.primary : AppColors.ok,
            titre: 'Photo rechargement',
            sousTitre: _recharge == null
                ? 'Nouveau camion'
                : 'GPS ${_recharge!.lat.toStringAsFixed(4)}, ${_recharge!.lon.toStringAsFixed(4)}',
            onTap: () async {
              final p = await _capture('Rechargement');
              if (p != null) {
                setState(() => _recharge = p);
                await _fillApres(p.path);
              }
            },
          ),
          const SizedBox(height: 8),
          TextField(
              controller: _apresCtrl,
              decoration: const InputDecoration(
                  labelText: 'Plaque camion après',
                  prefixIcon: Icon(Icons.directions_car))),
          const SizedBox(height: 24),
          StepHeader(
              numero: 2,
              titre: 'Les lots',
              sousTitre: 'Coche ceux qui montent sur le nouveau camion'),
          const SizedBox(height: 8),
          lots.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const Text('Impossible de charger les lots'),
            data: (list) => list.isEmpty
                ? const _Muted('Aucun lot en route')
                : Column(
                    children: list
                        .map((l) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: CheckboxListTile(
                                value: _selection.contains(l.id),
                                onChanged: (v) => setState(() => v == true
                                    ? _selection.add(l.id)
                                    : _selection.remove(l.id)),
                                title: Text(l.id),
                                subtitle: Text([
                                  l.mineId,
                                  if (l.couleur != null) l.couleur!,
                                ].join(' · ')),
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: BigButton(
            icon: Icons.save,
            label: _saving ? 'Enregistrement…' : 'Enregistrer',
            onPressed: _saving ? null : _save),
      ),
    );
  }
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
