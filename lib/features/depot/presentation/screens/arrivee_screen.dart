import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/geo.dart';
import '../../../../shared/capture_photo_screen.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../../../capture/presentation/providers/capture_providers.dart';
import '../../../scoring/domain/entities/scoring_inputs.dart';
import '../../../scoring/presentation/scoring_provider.dart';
import '../../../transport/presentation/providers/transport_provider.dart';
import '../../../trip/presentation/sim_session.dart';
import '../../../trip/presentation/trip_provider.dart';
import '../providers/depot_provider.dart';

/// Arrivée au dépôt d'UN lot : son chauffeur, son numéro de lot, son score.
/// Rien n'est partagé entre lots — ils peuvent arriver sur des camions
/// différents, à des moments différents.
class ArriveeScreen extends ConsumerStatefulWidget {
  final String lotId;
  const ArriveeScreen({super.key, required this.lotId});
  @override
  ConsumerState<ArriveeScreen> createState() => _ArriveeScreenState();
}

class _ArriveeScreenState extends ConsumerState<ArriveeScreen> {
  final _chauffeurCtrl = TextEditingController();
  final _permisCtrl = TextEditingController();
  final _plaqueCtrl = TextEditingController();
  final _numLotCtrl = TextEditingController();
  CapturedPhoto? _photo;
  CapturedPhoto? _permisPhoto;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(simSessionProvider) != null) {
      _chauffeurCtrl.text = 'Chauffeur Sim';
      _permisCtrl.text = 'SIM-PERMIS';
    }
  }

  @override
  void dispose() {
    _chauffeurCtrl.dispose();
    _permisCtrl.dispose();
    _plaqueCtrl.dispose();
    _numLotCtrl.dispose();
    super.dispose();
  }

  Future<CapturedPhoto?> _capture(String titre) => Navigator.of(context)
      .push<CapturedPhoto>(
          MaterialPageRoute(builder: (_) => CapturePhotoScreen(titre: titre)));

  Future<void> _captureArrivee() async {
    final p = await _capture('Photo arrivée');
    if (p == null) return;
    setState(() => _photo = p);
    if (_plaqueCtrl.text.trim().isEmpty) {
      final sim = ref.read(simSessionProvider);
      final plaque = sim != null
          ? ref.read(simSessionProvider.notifier).plate
          : await ref.read(plateOcrServiceProvider).readPlate(p.path);
      if (plaque != null && mounted) _plaqueCtrl.text = plaque;
    }
  }

  Future<void> _save() async {
    final photo = _photo;
    if (photo == null) {
      await showAppMessage(context, 'Prends d\'abord la photo d\'arrivée',
          kind: AppMsgKind.warning);
      return;
    }

    setState(() => _saving = true);
    try {
      final depotRepo = ref.read(depotRepoProvider);
      final resume = await depotRepo.lotResume(widget.lotId);
      final chaine =
          await ref.read(transportRepoProvider).chaineFor(widget.lotId);

      final res = ref.read(validateArriveeProvider)(
        lotId: widget.lotId,
        depots: await depotRepo.activeDepots(),
        lat: photo.lat,
        lon: photo.lon,
        chauffeur: _chauffeurCtrl.text.trim(),
        numPermis: _permisCtrl.text.trim(),
        numLot: _numLotCtrl.text.trim(),
        plaqueArrivee:
            _plaqueCtrl.text.trim().isEmpty ? null : _plaqueCtrl.text.trim(),
        // Plaque attendue = fin de la chaîne du lot, sinon sa plaque de départ.
        plaqueAttendue:
            chaine.isNotEmpty ? chaine.last.plaqueApres : resume?.plaqueDepart,
        photoArriveePath: photo.path,
        photoPermisPath: _permisPhoto?.path,
      );

      final arrivee = res.getRight().toNullable();
      if (arrivee == null) {
        final f = res.getLeft().toNullable();
        if (mounted) {
          await showAppMessage(context,
              f is ValidationFailure ? f.message : 'Données invalides',
              kind: AppMsgKind.error);
        }
        return;
      }

      final depots = await depotRepo.activeDepots();
      final depot = depots.firstWhere((d) => d.id == arrivee.depotId);
      final dist = haversineMeters(photo.lat, photo.lon, depot.lat, depot.lon);
      final ratio = resume?.cree == null
          ? 1.0
          : DateTime.now().difference(resume!.cree!).inSeconds /
              const Duration(hours: 72).inSeconds;
      final score = ref.read(scoringEngineProvider).evaluate(ScoringInputs(
            gpsMineDansRayon: true,
            photoMineValide: true,
            fournisseurActif: true,
            mineAutorisee: true,
            donneesCompletes: true,
            nombreMines: 1, // un lot = UNE mine
            depotReconnu: true,
            gpsNonFalsifie: true,
            distanceGpsMetres: dist,
            ratioDelai: ratio <= 0 ? 1.0 : ratio,
            transportCoherent:
                arrivee.plaqueCoherente && chaine.every((m) => m.conforme),
            ecartQuantitePct: 0,
            tauxConformite90j: 1.0,
          ));

      await depotRepo
          .persistArrivee(arrivee.copyWith(scoreTracabilite: score.score));

      // Plus aucun lot de la session en route → on arrête le suivi GPS.
      if (resume != null) {
        final restants = await depotRepo.lotsEnCours(resume.sessionId);
        if (restants.isEmpty) await ref.read(tripTrackerProvider).stop();
      }

      if (!mounted) return;
      await showAppMessage(
          context, '${widget.lotId}\n\nScore : ${score.score}/100',
          kind: AppMsgKind.success, titre: 'Lot arrivé');
      if (mounted) context.go('/home');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Arrivée — ${widget.lotId}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          StepHeader(numero: 1, titre: 'La photo', sousTitre: 'Camion au dépôt'),
          const SizedBox(height: 12),
          ActionTile(
            icon: _photo == null ? Icons.camera_alt : Icons.verified,
            color: _photo == null ? AppColors.primary : AppColors.ok,
            titre: _photo == null ? 'Prendre la photo' : 'Photo prise',
            sousTitre: _photo == null
                ? 'Avec position GPS'
                : 'GPS ${_photo!.lat.toStringAsFixed(4)}, ${_photo!.lon.toStringAsFixed(4)}',
            onTap: _captureArrivee,
          ),
          const SizedBox(height: 8),
          TextField(
              controller: _plaqueCtrl,
              decoration: const InputDecoration(
                  labelText: 'Plaque du camion (arrivée)',
                  prefixIcon: Icon(Icons.directions_car))),
          const SizedBox(height: 24),
          StepHeader(numero: 2, titre: 'Le chauffeur'),
          const SizedBox(height: 12),
          TextField(
              controller: _chauffeurCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nom du chauffeur',
                  prefixIcon: Icon(Icons.person))),
          const SizedBox(height: 12),
          TextField(
              controller: _permisCtrl,
              decoration: const InputDecoration(
                  labelText: 'Numéro de permis',
                  prefixIcon: Icon(Icons.badge))),
          const SizedBox(height: 12),
          ActionTile(
            icon: _permisPhoto == null ? Icons.add_a_photo : Icons.check_circle,
            color: _permisPhoto == null ? AppColors.inkSoft : AppColors.ok,
            titre: 'Photo du permis',
            sousTitre: 'Optionnel',
            onTap: () async {
              final p = await _capture('Photo permis');
              if (p != null) setState(() => _permisPhoto = p);
            },
          ),
          const SizedBox(height: 24),
          StepHeader(
              numero: 3,
              titre: 'Le numéro de lot',
              sousTitre: 'Donné par le dépôt'),
          const SizedBox(height: 12),
          TextField(
              controller: _numLotCtrl,
              decoration: const InputDecoration(
                  labelText: 'Numéro de lot',
                  prefixIcon: Icon(Icons.inventory_2))),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: BigButton(
            icon: Icons.check,
            label: _saving ? 'Validation…' : 'Valider l\'arrivée',
            onPressed: _saving ? null : _save),
      ),
    );
  }
}
