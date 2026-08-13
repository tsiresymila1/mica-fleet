import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/geo.dart';
import '../../../../shared/capture_photo_screen.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../../../capture/domain/entities/traceability_photos.dart';
import '../../../capture/presentation/providers/capture_providers.dart';
import '../../../scoring/domain/entities/scoring_inputs.dart';
import '../../../scoring/presentation/scoring_provider.dart';
import '../../../transport/presentation/providers/transport_provider.dart';
import '../../../trip/presentation/sim_session.dart';
import '../../../trip/presentation/trip_provider.dart';
import '../../../loading/presentation/providers/chargements_list_provider.dart';
import '../../domain/entities/depot.dart';
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
  CapturedPhoto? _platePhoto;
  CapturedPhoto? _micaPhoto;
  CapturedPhoto? _truckPhoto;
  CapturedPhoto? _permisPhoto;
  List<Depot> _depots = const [];
  Depot? _selectedDepot;
  bool _depotManuallySelected = false;
  bool _saving = false;
  bool _loadingSchema = true;
  bool _v2 = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(simSessionProvider) != null) {
      _chauffeurCtrl.text = 'Chauffeur Sim';
      _permisCtrl.text = 'SIM-PERMIS';
    }
    _loadSchema();
  }

  Future<void> _loadSchema() async {
    final repo = ref.read(depotRepoProvider);
    final version = await repo.photoSchemaVersionForLot(widget.lotId);
    final depots = await repo.activeDepots();
    if (!mounted) return;
    setState(() {
      _v2 = version >= 2;
      _depots = depots;
      _loadingSchema = false;
    });
  }

  @override
  void dispose() {
    _chauffeurCtrl.dispose();
    _permisCtrl.dispose();
    _plaqueCtrl.dispose();
    _numLotCtrl.dispose();
    super.dispose();
  }

  Future<CapturedPhoto?> _capture(String titre) =>
      Navigator.of(context).push<CapturedPhoto>(
        MaterialPageRoute(builder: (_) => CapturePhotoScreen(titre: titre)),
      );

  Future<void> _captureArrivee() async {
    final p = await _capture('Déchargement dépôt — plaque');
    if (p == null) return;
    final detected = ref
        .read(detectDepotProvider)
        .nearest(_depots, p.lat, p.lon);
    setState(() {
      _platePhoto = p;
      if (!_depotManuallySelected) _selectedDepot = detected?.depot;
    });
    if (_plaqueCtrl.text.trim().isEmpty) {
      final sim = ref.read(simSessionProvider);
      final plaque = sim != null
          ? ref.read(simSessionProvider.notifier).plate
          : await ref.read(plateOcrServiceProvider).readPlate(p.path);
      if (plaque != null && mounted) _plaqueCtrl.text = plaque;
    }
  }

  Future<void> _selectDepot() async {
    if (_depots.isEmpty) {
      await showAppMessage(
        context,
        'Aucun dépôt disponible hors ligne. Lance une synchronisation.',
        kind: AppMsgKind.warning,
      );
      return;
    }
    final selected = await showModalBottomSheet<Depot>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DepotPickerSheet(
        depots: _depots,
        selectedDepotId: _selectedDepot?.id,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedDepot = selected;
      _depotManuallySelected = true;
    });
  }

  String get _depotSubtitle {
    final depot = _selectedDepot;
    if (depot == null) {
      return _depots.isEmpty
          ? 'Aucun dépôt en cache — synchronisation nécessaire'
          : 'Appuyer pour choisir un dépôt';
    }
    final photo = _platePhoto;
    if (photo == null) {
      return _depotManuallySelected
          ? 'Sélection manuelle — le GPS sera vérifié après la photo'
          : 'Le GPS sera vérifié après la photo de plaque';
    }
    final result = ref
        .read(detectDepotProvider)
        .evaluate(depot, photo.lat, photo.lon);
    final source = _depotManuallySelected
        ? 'Sélection manuelle'
        : 'Détecté automatiquement';
    final gps = switch (result.statutGps) {
      'valide' => 'dans la zone',
      'non_verifiable' => 'position non vérifiable',
      _ => 'à ${result.distanceMetres.round()} m',
    };
    return '$source — $gps';
  }

  Future<void> _save() async {
    if (_selectedDepot == null) {
      await showAppMessage(
        context,
        'Choisis le dépôt de destination',
        kind: AppMsgKind.warning,
      );
      return;
    }
    final photo = _platePhoto;
    if (photo == null || (_v2 && (_micaPhoto == null || _truckPhoto == null))) {
      await showAppMessage(
        context,
        'Les 3 photos du déchargement au dépôt sont obligatoires',
        kind: AppMsgKind.warning,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final depotRepo = ref.read(depotRepoProvider);
      final resume = await depotRepo.lotResume(widget.lotId);
      final chaine = await ref
          .read(transportRepoProvider)
          .chaineFor(widget.lotId);

      final res = ref.read(validateArriveeProvider)(
        lotId: widget.lotId,
        depots: _depots,
        depotId: _selectedDepot!.id,
        lat: photo.lat,
        lon: photo.lon,
        chauffeur: _chauffeurCtrl.text.trim(),
        numPermis: _permisCtrl.text.trim(),
        numLot: _numLotCtrl.text.trim(),
        plaqueArrivee: _plaqueCtrl.text.trim().isEmpty
            ? null
            : _plaqueCtrl.text.trim(),
        // Plaque attendue = fin de la chaîne du lot, sinon sa plaque de départ.
        plaqueAttendue: chaine.isNotEmpty
            ? chaine.last.plaqueApres
            : resume?.plaqueDepart,
        photosDecharge: _v2
            ? TraceabilityPhotos(
                plate: photo,
                mica: _micaPhoto!,
                truckWithMica: _truckPhoto!,
              )
            : null,
        photoArriveePath: photo.path,
        photoArriveeHeadingDegrees: photo.headingDegrees,
        photoArriveeHeadingAccuracy: photo.headingAccuracy,
        photoArriveeHeadingReference: photo.headingReference,
        photoPermisPath: _permisPhoto?.path,
        photoPermisHeadingDegrees: _permisPhoto?.headingDegrees,
        photoPermisHeadingAccuracy: _permisPhoto?.headingAccuracy,
        photoPermisHeadingReference: _permisPhoto?.headingReference,
      );

      final arrivee = res.getRight().toNullable();
      if (arrivee == null) {
        final f = res.getLeft().toNullable();
        if (mounted) {
          await showAppMessage(
            context,
            f is ValidationFailure ? f.message : 'Données invalides',
            kind: AppMsgKind.error,
          );
        }
        return;
      }

      final depot = _selectedDepot!;
      final dist = haversineMeters(photo.lat, photo.lon, depot.lat, depot.lon);
      final gpsVerifiable = arrivee.statutGps != 'non_verifiable';

      // Hors zone : on prévient et on laisse forcer (dérive GPS, mais aussi
      // fraude possible → le score sera pénalisé et le statut conservé).
      if (arrivee.statutGps == 'hors_zone') {
        if (!mounted) return;
        final forcer = await showConfirm(
          context,
          'Tu es à ${dist.round()} m de « ${depot.nom} ».\n'
          'Valider quand même ? Le score sera réduit.',
          titre: 'Loin du dépôt',
          confirmLabel: 'Valider',
        );
        if (!forcer) return;
      }

      final ratio = resume?.cree == null
          ? 1.0
          : DateTime.now().difference(resume!.cree!).inSeconds /
                const Duration(hours: 72).inSeconds;
      final score = ref
          .read(scoringEngineProvider)
          .evaluate(
            ScoringInputs(
              gpsMineDansRayon: true,
              photoMineValide: true,
              fournisseurActif: true,
              mineAutorisee: true,
              donneesCompletes: true,
              nombreMines: 1, // un lot = UNE mine
              depotReconnu: true, // un dépôt a été rattaché
              gpsNonFalsifie: true,
              distanceGpsMetres: dist,
              gpsVerifiable: gpsVerifiable,
              ratioDelai: ratio <= 0 ? 1.0 : ratio,
              transportCoherent:
                  arrivee.plaqueCoherente && chaine.every((m) => m.conforme),
              ecartQuantitePct: 0,
              tauxConformite90j: 1.0,
            ),
          );

      final persisted = await depotRepo.persistArrivee(
        arrivee.copyWith(scoreTracabilite: score.score),
      );
      if (persisted.isLeft()) {
        final failure = persisted.getLeft().toNullable();
        if (mounted) {
          await showAppMessage(
            context,
            failure is ValidationFailure
                ? failure.message
                : 'Impossible d’enregistrer l’arrivée',
            kind: AppMsgKind.error,
          );
        }
        return;
      }
      // L'accueil peut encore être présent sous cette route : sa liste doit
      // relire immédiatement le statut et le score enregistrés en base.
      ref.invalidate(lotsListProvider);

      // Plus aucun lot de la session en route → on arrête le suivi GPS.
      if (resume != null) {
        final restants = await depotRepo.lotsEnCours(resume.sessionId);
        if (restants.isEmpty) await ref.read(tripTrackerProvider).stop();
      }

      if (!mounted) return;
      final note = switch (arrivee.statutGps) {
        'hors_zone' => '\n\n⚠ Loin du dépôt (${dist.round()} m)',
        'non_verifiable' => '\n\nℹ Position du dépôt non renseignée',
        _ => '',
      };
      await showAppMessage(
        context,
        '${widget.lotId}\n\nScore : ${score.score}/100$note',
        kind: AppMsgKind.success,
        titre: 'Lot arrivé',
      );
      if (mounted) context.go('/home');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSchema) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text('Arrivée — ${widget.lotId}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          StepHeader(
            numero: 1,
            titre: 'Le dépôt',
            sousTitre: 'Détecté par GPS et modifiable si nécessaire',
          ),
          const SizedBox(height: 12),
          ActionTile(
            icon: _selectedDepot == null
                ? Icons.warehouse_outlined
                : Icons.warehouse,
            color: _selectedDepot == null ? AppColors.primary : AppColors.ok,
            titre: _selectedDepot?.nom ?? 'Choisir le dépôt',
            sousTitre: _depotSubtitle,
            onTap: _selectDepot,
            trailing: const Icon(Icons.unfold_more, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 24),
          StepHeader(
            numero: 2,
            titre: _v2 ? 'Les 3 photos du déchargement' : 'La photo d’arrivée',
            sousTitre: _v2
                ? 'Plaque, mica et camion avec mica'
                : 'Capture historique v1',
          ),
          const SizedBox(height: 12),
          ActionTile(
            icon: _platePhoto == null ? Icons.camera_alt : Icons.verified,
            color: _platePhoto == null ? AppColors.primary : AppColors.ok,
            titre: _platePhoto == null
                ? 'Photo de la plaque'
                : 'Photo de la plaque ✓',
            sousTitre: _platePhoto == null
                ? 'Utilisée pour la reconnaissance de plaque'
                : 'GPS ${_platePhoto!.lat.toStringAsFixed(4)}, ${_platePhoto!.lon.toStringAsFixed(4)}',
            onTap: _captureArrivee,
          ),
          if (_v2) ...[
            const SizedBox(height: 8),
            ActionTile(
              icon: _micaPhoto == null ? Icons.camera_alt : Icons.verified,
              color: _micaPhoto == null ? AppColors.primary : AppColors.ok,
              titre: _micaPhoto == null ? 'Photo du mica' : 'Photo du mica ✓',
              sousTitre: _micaPhoto == null
                  ? 'Vue rapprochée du produit'
                  : 'GPS ${_micaPhoto!.lat.toStringAsFixed(4)}, ${_micaPhoto!.lon.toStringAsFixed(4)}',
              onTap: () async {
                final p = await _capture('Déchargement dépôt — mica');
                if (p != null) setState(() => _micaPhoto = p);
              },
            ),
            const SizedBox(height: 8),
            ActionTile(
              icon: _truckPhoto == null ? Icons.camera_alt : Icons.verified,
              color: _truckPhoto == null ? AppColors.primary : AppColors.ok,
              titre: _truckPhoto == null
                  ? 'Photo du camion avec mica'
                  : 'Photo du camion avec mica ✓',
              sousTitre: _truckPhoto == null
                  ? 'Vue d’ensemble du camion chargé'
                  : 'GPS ${_truckPhoto!.lat.toStringAsFixed(4)}, ${_truckPhoto!.lon.toStringAsFixed(4)}',
              onTap: () async {
                final p = await _capture(
                  'Déchargement dépôt — camion avec mica',
                );
                if (p != null) setState(() => _truckPhoto = p);
              },
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _plaqueCtrl,
            decoration: const InputDecoration(
              labelText: 'Plaque du camion (arrivée)',
              prefixIcon: Icon(Icons.directions_car),
            ),
          ),
          const SizedBox(height: 24),
          StepHeader(numero: 3, titre: 'Le chauffeur'),
          const SizedBox(height: 12),
          TextField(
            controller: _chauffeurCtrl,
            decoration: const InputDecoration(
              labelText: 'Nom du chauffeur',
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _permisCtrl,
            decoration: const InputDecoration(
              labelText: 'Numéro de permis',
              prefixIcon: Icon(Icons.badge),
            ),
          ),
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
            numero: 4,
            titre: 'Le numéro de lot',
            sousTitre: 'Donné par le dépôt',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _numLotCtrl,
            decoration: const InputDecoration(
              labelText: 'Numéro de lot',
              prefixIcon: Icon(Icons.inventory_2),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: BigButton(
          icon: Icons.check,
          label: _saving ? 'Validation…' : 'Valider l\'arrivée',
          onPressed: _saving ? null : _save,
        ),
      ),
    );
  }
}

class _DepotPickerSheet extends StatefulWidget {
  final List<Depot> depots;
  final String? selectedDepotId;

  const _DepotPickerSheet({
    required this.depots,
    required this.selectedDepotId,
  });

  @override
  State<_DepotPickerSheet> createState() => _DepotPickerSheetState();
}

class _DepotPickerSheetState extends State<_DepotPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = _query.trim().toLowerCase();
    final filtered = widget.depots
        .where((depot) => depot.nom.toLowerCase().contains(normalized))
        .toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sélectionner un dépôt',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Rechercher un dépôt',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Aucun dépôt trouvé')),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final depot = filtered[index];
                      final selected = depot.id == widget.selectedDepotId;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.warehouse,
                          color: selected ? AppColors.ok : AppColors.primary,
                        ),
                        title: Text(depot.nom),
                        subtitle: Text(
                          'Rayon GPS : ${depot.rayonMetres.round()} m',
                        ),
                        trailing: selected
                            ? const Icon(Icons.check, color: AppColors.ok)
                            : null,
                        onTap: () => Navigator.of(context).pop(depot),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
