import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/capture_photo_screen.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../../../capture/domain/entities/traceability_photos.dart';
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
  CapturedPhoto? _dechargePlaque, _dechargeMica, _dechargeCamion;
  CapturedPhoto? _rechargePlaque, _rechargeMica, _rechargeCamion;
  // En édition : photo/GPS déjà enregistrés, réutilisés si non repris.
  String? _dechargePathInit, _rechargePathInit;
  double? _dechargeLatInit,
      _dechargeLonInit,
      _rechargeLatInit,
      _rechargeLonInit;
  double? _dechargeHeadingInit, _dechargeHeadingAccuracyInit;
  double? _rechargeHeadingInit, _rechargeHeadingAccuracyInit;
  String? _dechargeHeadingReferenceInit, _rechargeHeadingReferenceInit;
  bool _saving = false;
  bool _loading = true;
  bool _v2 = false;

  bool get _edition => widget.ordre != null;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final repo = ref.read(transportRepoProvider);
    _v2 = await repo.photoSchemaVersionForLot(widget.lotId) >= 2;
    final chaine = _edition
        ? await repo.chaineFor(widget.lotId)
        : <Transbordement>[];
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
      _dechargeHeadingInit = m.photoDechargeHeadingDegrees;
      _dechargeHeadingAccuracyInit = m.photoDechargeHeadingAccuracy;
      _dechargeHeadingReferenceInit = m.photoDechargeHeadingReference;
      _rechargeHeadingInit = m.photoRechargeHeadingDegrees;
      _rechargeHeadingAccuracyInit = m.photoRechargeHeadingAccuracy;
      _rechargeHeadingReferenceInit = m.photoRechargeHeadingReference;
      _dechargePlaque = m.photosDecharge?.plate;
      _dechargeMica = m.photosDecharge?.mica;
      _dechargeCamion = m.photosDecharge?.truckWithMica;
      _rechargePlaque = m.photosRecharge?.plate;
      _rechargeMica = m.photosRecharge?.mica;
      _rechargeCamion = m.photosRecharge?.truckWithMica;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _avantCtrl.dispose();
    _apresCtrl.dispose();
    super.dispose();
  }

  Future<CapturedPhoto?> _capture(String titre) =>
      Navigator.of(context).push<CapturedPhoto>(
        MaterialPageRoute(builder: (_) => CapturePhotoScreen(titre: titre)),
      );

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

  // Métadonnées effectives : nouvelle photo, ou valeurs persistées en édition.
  ({
    String? path,
    double? lat,
    double? lon,
    double? heading,
    double? headingAccuracy,
    String? headingReference,
  })
  _cote(
    CapturedPhoto? neuve,
    String? pathInit,
    double? latInit,
    double? lonInit,
    double? headingInit,
    double? headingAccuracyInit,
    String? headingReferenceInit,
  ) {
    if (neuve != null) {
      return (
        path: neuve.path,
        lat: neuve.lat,
        lon: neuve.lon,
        heading: neuve.headingDegrees,
        headingAccuracy: neuve.headingAccuracy,
        headingReference: neuve.headingReference,
      );
    }
    return (
      path: pathInit,
      lat: latInit,
      lon: lonInit,
      heading: headingInit,
      headingAccuracy: headingAccuracyInit,
      headingReference: headingReferenceInit,
    );
  }

  Future<void> _save() async {
    final photosDecharge = _photoSet(
      _dechargePlaque,
      _dechargeMica,
      _dechargeCamion,
    );
    final photosRecharge = _photoSet(
      _rechargePlaque,
      _rechargeMica,
      _rechargeCamion,
    );
    final d = _cote(
      _dechargePlaque ?? _decharge,
      _dechargePathInit,
      _dechargeLatInit,
      _dechargeLonInit,
      _dechargeHeadingInit,
      _dechargeHeadingAccuracyInit,
      _dechargeHeadingReferenceInit,
    );
    final r = _cote(
      _rechargePlaque ?? _recharge,
      _rechargePathInit,
      _rechargeLatInit,
      _rechargeLonInit,
      _rechargeHeadingInit,
      _rechargeHeadingAccuracyInit,
      _rechargeHeadingReferenceInit,
    );
    final incomplete = _v2
        ? photosDecharge == null || photosRecharge == null
        : d.path == null || r.path == null;
    if (incomplete) {
      await showAppMessage(
        context,
        'Les 3 photos du déchargement et les 3 photos du rechargement sont obligatoires',
        kind: AppMsgKind.warning,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(transportRepoProvider);
      final chaine = await repo.chaineFor(widget.lotId);
      final maillon = Transbordement(
        ordre: widget.ordre ?? chaine.length + 1,
        plaqueAvant: _avantCtrl.text.trim().isEmpty
            ? null
            : _avantCtrl.text.trim(),
        plaqueApres: _apresCtrl.text.trim().isEmpty
            ? null
            : _apresCtrl.text.trim(),
        gpsDechargeLat: d.lat,
        gpsDechargeLon: d.lon,
        gpsRechargeLat: r.lat,
        gpsRechargeLon: r.lon,
        photoDechargePath: d.path,
        photoDechargeHeadingDegrees: d.heading,
        photoDechargeHeadingAccuracy: d.headingAccuracy,
        photoDechargeHeadingReference: d.headingReference,
        photoRechargePath: r.path,
        photoRechargeHeadingDegrees: r.heading,
        photoRechargeHeadingAccuracy: r.headingAccuracy,
        photoRechargeHeadingReference: r.headingReference,
        photosDecharge: _v2 ? photosDecharge : null,
        photosRecharge: _v2 ? photosRecharge : null,
      );
      // Édition : on remplace le maillon de même ordre ; création : on ajoute.
      final nouvelleChaine = _edition
          ? chaine.map((m) => m.ordre == widget.ordre ? maillon : m).toList()
          : [...chaine, maillon];
      final validee = ref.read(validateTransbordementProvider)(
        nouvelleChaine,
        kRayonTransbordementMetres,
      );
      await repo.persistChaine(widget.lotId, validee);
      if (!mounted) return;
      await showAppMessage(
        context,
        _edition ? 'Changement corrigé' : 'Changement enregistré',
        kind: AppMsgKind.success,
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  TraceabilityPhotos? _photoSet(
    CapturedPhoto? plate,
    CapturedPhoto? mica,
    CapturedPhoto? truck,
  ) {
    if (plate == null || mica == null || truck == null) return null;
    return TraceabilityPhotos(plate: plate, mica: mica, truckWithMica: truck);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _edition
              ? 'Corriger le camion ${widget.ordre}'
              : 'Camion — ${widget.lotId}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          StepHeader(
            numero: 1,
            titre: 'Le déchargement',
            sousTitre: 'Camion qui portait ce lot',
          ),
          const SizedBox(height: 12),
          if (!_v2)
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
            )
          else ...[
            _PhotoTile(
              fait: _dechargePlaque != null,
              titreVide: 'Photo de la plaque',
              photo: _dechargePlaque,
              pathInit: null,
              onTap: () async {
                final p = await _capture('Déchargement — plaque');
                if (p != null) {
                  setState(() => _dechargePlaque = p);
                  await _fillAvant(p.path);
                }
              },
            ),
            const SizedBox(height: 8),
            _PhotoTile(
              fait: _dechargeMica != null,
              titreVide: 'Photo du mica',
              photo: _dechargeMica,
              pathInit: null,
              onTap: () async {
                final p = await _capture('Déchargement — mica');
                if (p != null) setState(() => _dechargeMica = p);
              },
            ),
            const SizedBox(height: 8),
            _PhotoTile(
              fait: _dechargeCamion != null,
              titreVide: 'Photo du camion avec mica',
              photo: _dechargeCamion,
              pathInit: null,
              onTap: () async {
                final p = await _capture('Déchargement — camion avec mica');
                if (p != null) setState(() => _dechargeCamion = p);
              },
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _avantCtrl,
            decoration: const InputDecoration(
              labelText: 'Plaque camion avant',
              prefixIcon: Icon(Icons.directions_car),
            ),
          ),
          const SizedBox(height: 24),
          StepHeader(
            numero: 2,
            titre: 'Le rechargement',
            sousTitre: 'Nouveau camion pour ce lot',
          ),
          const SizedBox(height: 12),
          if (!_v2)
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
            )
          else ...[
            _PhotoTile(
              fait: _rechargePlaque != null,
              titreVide: 'Photo de la plaque',
              photo: _rechargePlaque,
              pathInit: null,
              onTap: () async {
                final p = await _capture('Rechargement — plaque');
                if (p != null) {
                  setState(() => _rechargePlaque = p);
                  await _fillApres(p.path);
                }
              },
            ),
            const SizedBox(height: 8),
            _PhotoTile(
              fait: _rechargeMica != null,
              titreVide: 'Photo du mica',
              photo: _rechargeMica,
              pathInit: null,
              onTap: () async {
                final p = await _capture('Rechargement — mica');
                if (p != null) setState(() => _rechargeMica = p);
              },
            ),
            const SizedBox(height: 8),
            _PhotoTile(
              fait: _rechargeCamion != null,
              titreVide: 'Photo du camion avec mica',
              photo: _rechargeCamion,
              pathInit: null,
              onTap: () async {
                final p = await _capture('Rechargement — camion avec mica');
                if (p != null) setState(() => _rechargeCamion = p);
              },
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _apresCtrl,
            decoration: const InputDecoration(
              labelText: 'Plaque camion après',
              prefixIcon: Icon(Icons.directions_car),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: BigButton(
          icon: Icons.save,
          label: _saving ? 'Enregistrement…' : 'Enregistrer',
          onPressed: _saving ? null : _save,
        ),
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
      trailing:
          (photo?.path ?? pathInit) != null &&
              File(photo?.path ?? pathInit!).existsSync()
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(photo?.path ?? pathInit!),
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            )
          : null,
    );
  }
}
