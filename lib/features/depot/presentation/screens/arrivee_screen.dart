import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/error/failure.dart';
import '../../../../shared/capture_photo_screen.dart';
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
            builder: (_) => const CapturePhotoScreen(titre: 'Arrivée dépôt')));
    if (p != null) setState(() => _photo = p);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final photo = _photo;
    if (photo == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Photo d\'arrivée obligatoire')));
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
              messenger.showSnackBar(SnackBar(content: Text(
                  'Arrivée validée au dépôt ${arrivee.depotId}')));
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
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                    _photo == null ? Icons.camera_alt : Icons.check_circle,
                    color: _photo == null ? null : Colors.green),
                title: const Text('Photo d\'arrivée (géolocalisée)'),
                subtitle: _photo == null
                    ? const Text('Non capturée')
                    : Text('GPS ${_photo!.lat.toStringAsFixed(5)}, '
                        '${_photo!.lon.toStringAsFixed(5)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _captureArrivee,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _chauffeurCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nom du chauffeur',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _permisCtrl,
                decoration: const InputDecoration(
                    labelText: 'Numéro de permis',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _lotCtrl,
                decoration: const InputDecoration(
                    labelText: 'Numéro de lot', border: OutlineInputBorder())),
            const SizedBox(height: 24),
            FilledButton.icon(
                icon: const Icon(Icons.check),
                label: Text(_saving ? '...' : 'Valider l\'arrivée'),
                onPressed: _saving ? null : _save),
          ],
        ),
      );
}
