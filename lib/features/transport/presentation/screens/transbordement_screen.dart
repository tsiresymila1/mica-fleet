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

/// Changement de camion pour UN lot. Chaque lot a sa propre chaîne de camions :
/// deux lots partis ensemble peuvent repartir sur des camions différents.
class TransbordementScreen extends ConsumerStatefulWidget {
  final String lotId;
  const TransbordementScreen({super.key, required this.lotId});
  @override
  ConsumerState<TransbordementScreen> createState() =>
      _TransbordementScreenState();
}

class _TransbordementScreenState extends ConsumerState<TransbordementScreen> {
  final _avantCtrl = TextEditingController();
  final _apresCtrl = TextEditingController();
  CapturedPhoto? _decharge;
  CapturedPhoto? _recharge;
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
    setState(() => _saving = true);
    try {
      final repo = ref.read(transportRepoProvider);
      final chaine = await repo.chaineFor(widget.lotId);
      final maillon = Transbordement(
        ordre: chaine.length + 1,
        plaqueAvant:
            _avantCtrl.text.trim().isEmpty ? null : _avantCtrl.text.trim(),
        plaqueApres:
            _apresCtrl.text.trim().isEmpty ? null : _apresCtrl.text.trim(),
        gpsDechargeLat: _decharge!.lat,
        gpsDechargeLon: _decharge!.lon,
        gpsRechargeLat: _recharge!.lat,
        gpsRechargeLon: _recharge!.lon,
      );
      final nouvelle = ref.read(validateTransbordementProvider)(
          [...chaine, maillon], kRayonTransbordementMetres);
      await repo.persistChaine(widget.lotId, nouvelle);
      if (!mounted) return;
      await showAppMessage(context, 'Changement de camion enregistré',
          kind: AppMsgKind.success);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Camion — ${widget.lotId}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          StepHeader(
              numero: 1,
              titre: 'Le déchargement',
              sousTitre: 'Camion qui portait ce lot'),
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
          const SizedBox(height: 24),
          StepHeader(
              numero: 2,
              titre: 'Le rechargement',
              sousTitre: 'Nouveau camion pour ce lot'),
          const SizedBox(height: 12),
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
