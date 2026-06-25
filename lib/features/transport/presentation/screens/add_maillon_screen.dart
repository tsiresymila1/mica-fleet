import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/capture_photo_screen.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../../../capture/presentation/providers/capture_providers.dart';
import '../../domain/entities/transbordement.dart';

/// Saisie d'un maillon de transbordement : plaques avant/après + GPS déchargement/rechargement.
/// Retourne un [Transbordement] (ordre fixé par le contrôleur) ou null.
class AddMaillonScreen extends ConsumerStatefulWidget {
  const AddMaillonScreen({super.key});
  @override
  ConsumerState<AddMaillonScreen> createState() => _AddMaillonScreenState();
}

class _AddMaillonScreenState extends ConsumerState<AddMaillonScreen> {
  final _avantCtrl = TextEditingController();
  final _apresCtrl = TextEditingController();
  CapturedPhoto? _decharge;
  CapturedPhoto? _recharge;

  @override
  void dispose() {
    _avantCtrl.dispose();
    _apresCtrl.dispose();
    super.dispose();
  }

  Future<CapturedPhoto?> _capture(String titre) => Navigator.of(context)
      .push<CapturedPhoto>(MaterialPageRoute(
          builder: (_) => CapturePhotoScreen(titre: titre)));

  /// OCR sur la photo, préremplit le champ plaque si vide.
  Future<void> _ocrInto(TextEditingController ctrl, String path) async {
    if (ctrl.text.trim().isNotEmpty) return;
    final plaque = await ref.read(plateOcrServiceProvider).readPlate(path);
    if (plaque != null && mounted) ctrl.text = plaque;
  }

  void _save() {
    if (_decharge == null || _recharge == null) {
      showAppMessage(
          context, 'Photos déchargement et rechargement obligatoires',
          kind: AppMsgKind.warning);
      return;
    }
    Navigator.of(context).pop(Transbordement(
      ordre: 0,
      plaqueAvant: _avantCtrl.text.trim().isEmpty ? null : _avantCtrl.text.trim(),
      plaqueApres: _apresCtrl.text.trim().isEmpty ? null : _apresCtrl.text.trim(),
      gpsDechargeLat: _decharge!.lat,
      gpsDechargeLon: _decharge!.lon,
      gpsRechargeLat: _recharge!.lat,
      gpsRechargeLon: _recharge!.lon,
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Nouveau transbordement')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
                controller: _avantCtrl,
                decoration: const InputDecoration(
                    labelText: 'Plaque camion avant',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            _CaptureTile(
              label: 'Photo déchargement',
              photo: _decharge,
              onTap: () async {
                final p = await _capture('Déchargement');
                if (p != null) {
                  setState(() => _decharge = p);
                  await _ocrInto(_avantCtrl, p.path);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _apresCtrl,
                decoration: const InputDecoration(
                    labelText: 'Plaque camion après',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            _CaptureTile(
              label: 'Photo rechargement',
              photo: _recharge,
              onTap: () async {
                final p = await _capture('Rechargement');
                if (p != null) {
                  setState(() => _recharge = p);
                  await _ocrInto(_apresCtrl, p.path);
                }
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Enregistrer le maillon'),
                onPressed: _save),
          ],
        ),
      );
}

class _CaptureTile extends StatelessWidget {
  final String label;
  final CapturedPhoto? photo;
  final VoidCallback onTap;
  const _CaptureTile(
      {required this.label, required this.photo, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(photo == null ? Icons.camera_alt : Icons.check_circle,
              color: photo == null ? null : Colors.green),
          title: Text(label),
          subtitle: photo == null
              ? const Text('Non capturée')
              : Text('GPS ${photo!.lat.toStringAsFixed(5)}, '
                  '${photo!.lon.toStringAsFixed(5)}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
