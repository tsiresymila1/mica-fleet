import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../../domain/entities/arrivee_depot.dart';
import '../providers/depot_provider.dart';

/// Arrivée au dépôt : on valide les lots présents dans le camion.
/// Chaque lot reçoit son numéro de lot et SON score (1 lot = 1 traçabilité).
class ArriveeScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const ArriveeScreen({super.key, required this.sessionId});
  @override
  ConsumerState<ArriveeScreen> createState() => _ArriveeScreenState();
}

class _ArriveeScreenState extends ConsumerState<ArriveeScreen> {
  final _chauffeurCtrl = TextEditingController();
  final _permisCtrl = TextEditingController();
  final _plaqueCtrl = TextEditingController();
  final Map<String, TextEditingController> _numLot = {};
  final Set<String> _selection = {};
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
    for (final c in _numLot.values) {
      c.dispose();
    }
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

  String norm(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  Future<void> _save() async {
    final photo = _photo;
    if (photo == null) {
      await showAppMessage(context, 'Prends d\'abord la photo d\'arrivée',
          kind: AppMsgKind.warning);
      return;
    }
    if (_selection.isEmpty) {
      await showAppMessage(context, 'Choisis les lots arrivés',
          kind: AppMsgKind.warning);
      return;
    }
    if (_chauffeurCtrl.text.trim().isEmpty ||
        _permisCtrl.text.trim().isEmpty) {
      await showAppMessage(context, 'Chauffeur et permis obligatoires',
          kind: AppMsgKind.warning);
      return;
    }
    for (final id in _selection) {
      if ((_numLot[id]?.text ?? '').trim().isEmpty) {
        await showAppMessage(context, 'Numéro de lot manquant pour $id',
            kind: AppMsgKind.warning);
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final depotRepo = ref.read(depotRepoProvider);
      final depots = await depotRepo.activeDepots();
      final depot = ref.read(detectDepotProvider)(depots, photo.lat, photo.lon);
      if (depot == null) {
        if (mounted) {
          await showAppMessage(
              context, 'Aucun dépôt reconnu dans la zone GPS',
              kind: AppMsgKind.error);
        }
        return;
      }
      final transportRepo = ref.read(transportRepoProvider);
      final engine = ref.read(scoringEngineProvider);
      final plaqueArrivee =
          _plaqueCtrl.text.trim().isEmpty ? null : _plaqueCtrl.text.trim();
      final scores = <String, int>{};

      for (final lotId in _selection) {
        final resume = await depotRepo.lotResume(lotId);
        final chaine = await transportRepo.chaineFor(lotId);
        // Plaque attendue = fin de chaîne, sinon plaque de départ du lot.
        final attendue = chaine.isNotEmpty
            ? chaine.last.plaqueApres
            : resume?.plaqueDepart;
        final coherente = plaqueArrivee == null || attendue == null
            ? true
            : norm(plaqueArrivee) == norm(attendue);

        final dist =
            haversineMeters(photo.lat, photo.lon, depot.lat, depot.lon);
        final ratio = resume?.cree == null
            ? 1.0
            : DateTime.now().difference(resume!.cree!).inSeconds /
                const Duration(hours: 72).inSeconds;
        final score = engine.evaluate(ScoringInputs(
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
          transportCoherent: coherente && chaine.every((m) => m.conforme),
          ecartQuantitePct: 0,
          tauxConformite90j: 1.0,
        ));
        scores[lotId] = score.score;

        await depotRepo.persistArrivee(ArriveeDepot(
          lotId: lotId,
          depotId: depot.id,
          chauffeur: _chauffeurCtrl.text.trim(),
          numPermis: _permisCtrl.text.trim(),
          numLot: _numLot[lotId]!.text.trim(),
          gpsLat: photo.lat,
          gpsLon: photo.lon,
          statutGps: 'valide',
          plaqueArrivee: plaqueArrivee,
          plaqueCoherente: coherente,
          scoreTracabilite: score.score,
          photoArriveePath: photo.path,
          photoPermisPath: _permisPhoto?.path,
        ));
      }

      // Plus de lot en route → on arrête le suivi GPS.
      final restants = await depotRepo.lotsEnCours(widget.sessionId);
      if (restants.isEmpty) await ref.read(tripTrackerProvider).stop();

      if (!mounted) return;
      final resume = scores.entries
          .map((e) => '${e.key} : ${e.value}/100')
          .join('\n');
      await showAppMessage(context, 'Arrivée validée\n\n$resume',
          kind: AppMsgKind.success, titre: 'Scores');
      if (mounted) context.go('/home');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lots = ref.watch(lotsEnCoursProvider(widget.sessionId));
    return Scaffold(
      appBar: AppBar(title: const Text('Arrivée au dépôt')),
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
                  labelText: 'Numéro de permis', prefixIcon: Icon(Icons.badge))),
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
              titre: 'Les lots arrivés',
              sousTitre: 'Un numéro de lot par lot'),
          const SizedBox(height: 8),
          lots.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const Text('Impossible de charger les lots'),
            data: (list) => Column(
              children: list.map((l) {
                _numLot.putIfAbsent(l.id, () => TextEditingController());
                final coche = _selection.contains(l.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(children: [
                    CheckboxListTile(
                      value: coche,
                      onChanged: (v) => setState(() => v == true
                          ? _selection.add(l.id)
                          : _selection.remove(l.id)),
                      title: Text(l.id),
                      subtitle: Text([
                        l.mineId,
                        if (l.couleur != null) l.couleur!,
                      ].join(' · ')),
                    ),
                    if (coche)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextField(
                          controller: _numLot[l.id],
                          decoration: const InputDecoration(
                              labelText: 'Numéro de lot',
                              prefixIcon: Icon(Icons.inventory_2),
                              isDense: true),
                        ),
                      ),
                  ]),
                );
              }).toList(),
            ),
          ),
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
