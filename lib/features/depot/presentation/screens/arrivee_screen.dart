import 'dart:convert';
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
import '../../../scoring/domain/entities/score_result.dart';
import '../../../scoring/domain/entities/scoring_inputs.dart';
import '../../../scoring/presentation/scoring_provider.dart';
import '../../../transport/presentation/providers/transport_provider.dart';
import '../providers/depot_provider.dart';

/// Validation de l'arrivée au dépôt : photo GPS, plaque (OCR), permis (photo),
/// chauffeur/permis/lot, détection dépôt, cohérence immatriculation, score.
class ArriveeScreen extends ConsumerStatefulWidget {
  final String chargementId;
  const ArriveeScreen({super.key, required this.chargementId});
  @override
  ConsumerState<ArriveeScreen> createState() => _ArriveeScreenState();
}

class _ArriveeScreenState extends ConsumerState<ArriveeScreen> {
  final _chauffeurCtrl = TextEditingController();
  final _permisCtrl = TextEditingController();
  final _lotCtrl = TextEditingController();
  final _plaqueCtrl = TextEditingController();
  final Map<String, TextEditingController> _lotParCouleur = {};
  List<String> _couleurs = [];
  CapturedPhoto? _photo;
  CapturedPhoto? _permisPhoto;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final resume = await ref
          .read(depotRepoProvider)
          .chargementResume(widget.chargementId);
      if (!mounted) return;
      setState(() {
        _couleurs = resume.couleurs;
        for (final c in _couleurs) {
          _lotParCouleur[c] = TextEditingController();
        }
      });
    });
  }

  @override
  void dispose() {
    _chauffeurCtrl.dispose();
    _permisCtrl.dispose();
    _lotCtrl.dispose();
    _plaqueCtrl.dispose();
    for (final c in _lotParCouleur.values) {
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
      final plaque = await ref.read(plateOcrServiceProvider).readPlate(p.path);
      if (plaque != null && mounted) _plaqueCtrl.text = plaque;
    }
  }

  /// Dernière plaque connue : fin de chaîne de transbordement, sinon plaque du chargement.
  Future<String?> _plaqueAttendue() async {
    final chaine =
        await ref.read(transportRepoProvider).chaineFor(widget.chargementId);
    if (chaine.isNotEmpty) return chaine.last.plaqueApres;
    final resume =
        await ref.read(depotRepoProvider).chargementResume(widget.chargementId);
    return resume.plaque;
  }

  Future<ScoreResult> _computeScore(
      {required double lat,
      required double lon,
      required bool plaqueCoherente}) async {
    final resume =
        await ref.read(depotRepoProvider).chargementResume(widget.chargementId);
    final depots = await ref.read(depotRepoProvider).activeDepots();
    final depot = ref.read(detectDepotProvider)(depots, lat, lon);
    final chaine =
        await ref.read(transportRepoProvider).chaineFor(widget.chargementId);
    final chaineOk = chaine.every((m) => m.conforme);

    final dist =
        depot == null ? 999.0 : haversineMeters(lat, lon, depot.lat, depot.lon);
    final ratio = resume.cree == null
        ? 1.0
        : DateTime.now().difference(resume.cree!).inSeconds /
            const Duration(hours: 72).inSeconds;

    final inputs = ScoringInputs(
      gpsMineDansRayon: true,
      photoMineValide: true,
      fournisseurActif: true,
      mineAutorisee: true,
      donneesCompletes: true,
      nombreMines: resume.nbMines == 0 ? 1 : resume.nbMines,
      depotReconnu: depot != null,
      gpsNonFalsifie: true,
      distanceGpsMetres: dist,
      ratioDelai: ratio <= 0 ? 1.0 : ratio,
      transportCoherent: plaqueCoherente && chaineOk,
      ecartQuantitePct: 0, // contre-pesage non saisi → supposé conforme
      tauxConformite90j: 1.0, // historique non disponible offline → neutre
    );
    return ref.read(scoringEngineProvider).evaluate(inputs);
  }

  Future<void> _save() async {
    final photo = _photo;
    if (photo == null) {
      await showAppMessage(context, 'Prends d\'abord la photo',
          kind: AppMsgKind.warning);
      return;
    }
    // Lots : un par couleur si le chargement a des couleurs, sinon champ unique.
    String numLot;
    String? lotsJson;
    if (_couleurs.isEmpty) {
      numLot = _lotCtrl.text;
    } else {
      final map = {
        for (final c in _couleurs) c: _lotParCouleur[c]!.text.trim()
      };
      if (map.values.any((v) => v.isEmpty)) {
        await showAppMessage(context, 'Renseigne un numéro de lot par couleur',
            kind: AppMsgKind.warning);
        return;
      }
      numLot = map.entries.map((e) => '${e.key}: ${e.value}').join(', ');
      lotsJson = jsonEncode(map);
    }
    setState(() => _saving = true);
    try {
      final depots = await ref.read(depotRepoProvider).activeDepots();
      final attendue = await _plaqueAttendue();
      final validation = ref.read(validateArriveeProvider)(
        chargementId: widget.chargementId,
        depots: depots,
        lat: photo.lat,
        lon: photo.lon,
        chauffeur: _chauffeurCtrl.text,
        numPermis: _permisCtrl.text,
        numLot: numLot,
        plaqueArrivee:
            _plaqueCtrl.text.trim().isEmpty ? null : _plaqueCtrl.text.trim(),
        plaqueAttendue: attendue,
        photoArriveePath: photo.path,
        photoPermisPath: _permisPhoto?.path,
      );
      await validation.match(
        (f) async {
          if (mounted) {
            await showAppMessage(
                context, f is ValidationFailure ? f.message : 'Échec',
                kind: AppMsgKind.error);
          }
        },
        (arrivee) async {
          final score = await _computeScore(
              lat: photo.lat,
              lon: photo.lon,
              plaqueCoherente: arrivee.plaqueCoherente);
          final res = await ref.read(depotRepoProvider).persistArrivee(
              arrivee.copyWith(
                  scoreTracabilite: score.score, lotsJson: lotsJson));
          if (!mounted) return;
          await res.match(
            (f) async => showAppMessage(context, 'Échec enregistrement',
                kind: AppMsgKind.error),
            (_) async {
              if (!arrivee.plaqueCoherente) {
                await showAppMessage(
                    context, 'Attention : plaque différente du départ',
                    kind: AppMsgKind.warning);
              }
              if (mounted) {
                context.pushReplacement('/score',
                    extra: (
                      resultat: score,
                      chargementId: widget.chargementId
                    ));
              }
            },
          );
        },
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Arrivée au dépôt')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: [
            StepHeader(
                numero: 1,
                titre: 'La photo',
                sousTitre: 'Camion déchargé au dépôt'),
            const SizedBox(height: 12),
            ActionTile(
              icon: _photo == null ? Icons.camera_alt : Icons.verified,
              color: _photo == null ? AppColors.primary : AppColors.ok,
              titre: _photo == null ? 'Prendre la photo' : 'Photo prise',
              sousTitre: _photo == null
                  ? 'Avec position GPS'
                  : 'GPS ${_photo!.lat.toStringAsFixed(4)}, '
                      '${_photo!.lon.toStringAsFixed(4)}',
              onTap: _captureArrivee,
              trailing: _photo == null
                  ? null
                  : const StatusPill(kind: PillKind.ok, label: 'OK'),
            ),
            const SizedBox(height: 12),
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
              icon: _permisPhoto == null
                  ? Icons.add_a_photo
                  : Icons.check_circle,
              color: _permisPhoto == null ? AppColors.inkSoft : AppColors.ok,
              titre: 'Photo du permis',
              sousTitre: 'Optionnel',
              onTap: () async {
                final p = await _capture('Photo permis');
                if (p != null) setState(() => _permisPhoto = p);
              },
            ),
            const SizedBox(height: 24),
            StepHeader(numero: 3, titre: 'Les lots'),
            const SizedBox(height: 12),
            if (_couleurs.isEmpty)
              TextField(
                  controller: _lotCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Numéro de lot',
                      prefixIcon: Icon(Icons.inventory_2)))
            else
              for (final c in _couleurs) ...[
                TextField(
                    controller: _lotParCouleur[c],
                    decoration: InputDecoration(
                        labelText: 'Lot — $c',
                        prefixIcon: const Icon(Icons.inventory_2))),
                const SizedBox(height: 12),
              ],
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
