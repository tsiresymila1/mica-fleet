import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/capture_photo_screen.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../providers/depot_provider.dart';

/// Validation de l'arrivée au dépôt : photo GPS, chauffeur/permis/lot, détection dépôt.
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
  CapturedPhoto? _photo;
  bool _saving = false;

  @override
  void dispose() {
    _chauffeurCtrl.dispose();
    _permisCtrl.dispose();
    _lotCtrl.dispose();
    super.dispose();
  }

  Future<void> _captureArrivee() async {
    final p = await Navigator.of(context).push<CapturedPhoto>(
        MaterialPageRoute(
            builder: (_) => const CapturePhotoScreen(titre: 'Photo arrivée')));
    if (p != null) setState(() => _photo = p);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final photo = _photo;
    if (photo == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Prends d\'abord la photo')));
      return;
    }
    setState(() => _saving = true);
    try {
      final depots = await ref.read(depotRepoProvider).activeDepots();
      final validation = ref.read(validateArriveeProvider)(
        chargementId: widget.chargementId,
        depots: depots,
        lat: photo.lat,
        lon: photo.lon,
        chauffeur: _chauffeurCtrl.text,
        numPermis: _permisCtrl.text,
        numLot: _lotCtrl.text,
      );
      await validation.match(
        (f) async => messenger.showSnackBar(SnackBar(
            content: Text(f is ValidationFailure ? f.message : 'Échec'))),
        (arrivee) async {
          final res = await ref
              .read(depotRepoProvider)
              .persistArrivee(arrivee.copyWith(photoArriveePath: photo.path));
          res.match(
            (f) => messenger.showSnackBar(
                const SnackBar(content: Text('Échec enregistrement'))),
            (_) {
              messenger.showSnackBar(
                  const SnackBar(content: Text('Arrivée validée')));
              navigator.pop();
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
            TextField(
                controller: _lotCtrl,
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
