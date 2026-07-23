import 'dart:io';
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

/// Changement de camion pour UN lot. Chaque lot a sa propre chaîne de camions.
/// En mode édition ([ordre] fourni), on corrige un maillon existant sans en
/// créer un nouveau (autorisé tant que le lot n'est pas arrivé).
class TransbordementScreen extends ConsumerStatefulWidget {
  final String lotId;
  final int? ordre; // non null = édition d'un maillon existant
  const TransbordementScreen({super.key, required this.lotId, this.ordre});
  @override
  ConsumerState<TransbordementScreen> createState() =>
      _TransbordementScreenState();
}

class _TransbordementScreenState extends ConsumerState<TransbordementScreen> {
  final _avantCtrl = TextEditingController();
  final _apresCtrl = TextEditingController();
  CapturedPhoto? _decharge;
  CapturedPhoto? _recharge;
  // En édition : photo/GPS déjà enregistrés, réutilisés si non repris.
  String? _dechargePathInit, _rechargePathInit;
  double? _dechargeLatInit, _dechargeLonInit, _rechargeLatInit, _rechargeLonInit;
  bool _saving = false;
  bool _loading = false;

  bool get _edition => widget.ordre != null;

  @override
  void initState() {
    super.initState();
    if (_edition) _chargerMaillon();
  }

  Future<void> _chargerMaillon() async {
    setState(() => _loading = true);
    final chaine = await ref.read(transportRepoProvider).chaineFor(widget.lotId);
    final m = chaine.where((x) => x.ordre == widget.ordre).firstOrNull;
    if (m != null && mounted) {
      _avantCtrl.text = m.plaqueAvant ?? '';
      _apresCtrl.text = m.plaqueApres ?? '';
      _dechargePathInit = m.photoDechargePath;
      _rechargePathInit = m.photoRechargePath;
      _dechargeLatInit = m.gpsDechargeLat;
      _dechargeLonInit = m.gpsDechargeLon;
      _rechargeLatInit = m.gpsRechargeLat;
      _rechargeLonInit = m.gpsRechargeLon;
    }
    if (mounted) setState(() => _loading = false);
  }

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

  // Path/GPS effectifs d'un côté : la nouvelle photo si reprise, sinon l'init.
  ({String? path, double? lat, double? lon}) _cote(
      CapturedPhoto? neuve, String? pathInit, double? latInit, double? lonInit) {
    if (neuve != null) return (path: neuve.path, lat: neuve.lat, lon: neuve.lon);
    return (path: pathInit, lat: latInit, lon: lonInit);
  }

  Future<void> _save() async {
    final d = _cote(_decharge, _dechargePathInit, _dechargeLatInit,
        _dechargeLonInit);
    final r = _cote(_recharge, _rechargePathInit, _rechargeLatInit,
        _rechargeLonInit);
    if (d.path == null || r.path == null) {
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
        ordre: widget.ordre ?? chaine.length + 1,
        plaqueAvant:
            _avantCtrl.text.trim().isEmpty ? null : _avantCtrl.text.trim(),
        plaqueApres:
            _apresCtrl.text.trim().isEmpty ? null : _apresCtrl.text.trim(),
        gpsDechargeLat: d.lat,
        gpsDechargeLon: d.lon,
        gpsRechargeLat: r.lat,
        gpsRechargeLon: r.lon,
        photoDechargePath: d.path,
        photoRechargePath: r.path,
      );
      // Édition : on remplace le maillon de même ordre ; création : on ajoute.
      final nouvelleChaine = _edition
          ? chaine.map((m) => m.ordre == widget.ordre ? maillon : m).toList()
          : [...chaine, maillon];
      final validee = ref.read(validateTransbordementProvider)(
          nouvelleChaine, kRayonTransbordementMetres);
      await repo.persistChaine(widget.lotId, validee);
      if (!mounted) return;
      await showAppMessage(
          context, _edition ? 'Changement corrigé' : 'Changement enregistré',
          kind: AppMsgKind.success);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
          title: Text(_edition
              ? 'Corriger le camion ${widget.ordre}'
              : 'Camion — ${widget.lotId}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          StepHeader(
              numero: 1,
              titre: 'Le déchargement',
              sousTitre: 'Camion qui portait ce lot'),
          const SizedBox(height: 12),
          _PhotoTile(
            fait: _decharge != null || _dechargePathInit != null,
            titreVide: 'Photo déchargement',
            photo: _decharge,
            pathInit: _dechargePathInit,
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
          _PhotoTile(
            fait: _recharge != null || _rechargePathInit != null,
            titreVide: 'Photo rechargement',
            photo: _recharge,
            pathInit: _rechargePathInit,
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

/// Tuile photo : verte si une photo existe (nouvelle ou déjà enregistrée).
class _PhotoTile extends StatelessWidget {
  final bool fait;
  final String titreVide;
  final CapturedPhoto? photo;
  final String? pathInit;
  final VoidCallback onTap;
  const _PhotoTile({
    required this.fait,
    required this.titreVide,
    required this.photo,
    required this.pathInit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sous = photo != null
        ? 'GPS ${photo!.lat.toStringAsFixed(4)}, ${photo!.lon.toStringAsFixed(4)}'
        : (pathInit != null ? 'Photo enregistrée — retoucher' : 'Camion');
    return ActionTile(
      icon: fait ? Icons.check_circle : Icons.camera_alt,
      color: fait ? AppColors.ok : AppColors.primary,
      titre: fait ? '$titreVide ✓' : titreVide,
      sousTitre: sous,
      onTap: onTap,
      trailing: (photo?.path ?? pathInit) != null &&
              File(photo?.path ?? pathInit!).existsSync()
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(File(photo?.path ?? pathInit!),
                  width: 40, height: 40, fit: BoxFit.cover),
            )
          : null,
    );
  }
}
