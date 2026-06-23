import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../capture/data/capture_service_impl.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../../../capture/presentation/providers/capture_providers.dart';
import '../../../mines/domain/entities/mine.dart';
import '../../../mines/presentation/providers/mines_provider.dart';
import '../../domain/entities/mine_chargement.dart';

/// Saisie d'une mine : sélection mine, photo in-app (GPS+hash), OCR plaque, données produit.
/// Retourne un [MineChargement] via Navigator.pop, ou null si annulé.
class AddMineScreen extends ConsumerStatefulWidget {
  const AddMineScreen({super.key});
  @override
  ConsumerState<AddMineScreen> createState() => _AddMineScreenState();
}

class _AddMineScreenState extends ConsumerState<AddMineScreen> {
  CameraController? _cam;
  bool _initializing = true;
  String? _initError;

  Mine? _mine;
  CapturedPhoto? _photo;
  bool _capturing = false;
  String _plaque = '';
  final _refCtrl = TextEditingController();
  final _couleurCtrl = TextEditingController();
  final _qteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() {
          _initError = 'Aucune caméra disponible';
          _initializing = false;
        });
        return;
      }
      final ctrl = CameraController(cams.first, ResolutionPreset.medium,
          enableAudio: false);
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _cam = ctrl;
        _initializing = false;
      });
    } catch (e) {
      setState(() {
        _initError = 'Erreur caméra : $e';
        _initializing = false;
      });
    }
  }

  @override
  void dispose() {
    _cam?.dispose();
    _refCtrl.dispose();
    _couleurCtrl.dispose();
    _qteCtrl.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final cam = _cam;
    if (cam == null) return;
    setState(() => _capturing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Anti-fraude : refuse si position simulée.
      final mock =
          await ref.read(mockLocationGuardProvider).isMockLocationActive();
      if (mock) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Position GPS simulée détectée — capture refusée')));
        return;
      }
      final photo = await CameraCaptureService(cam).capture();
      final plaque = await ref.read(plateOcrServiceProvider).readPlate(photo.path);
      if (!mounted) return;
      setState(() {
        _photo = photo;
        if (plaque != null) _plaque = plaque;
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec capture : $e')));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _save() {
    if (_mine == null || _photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mine et photo obligatoires')));
      return;
    }
    Navigator.of(context).pop(MineChargement(
      mineId: _mine!.id,
      reference: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
      couleur: _couleurCtrl.text.trim().isEmpty ? null : _couleurCtrl.text.trim(),
      quantiteEstimee: double.tryParse(_qteCtrl.text.replaceAll(',', '.')),
      plaqueOcr: _plaque.isEmpty ? null : _plaque,
      photo: _photo,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final minesAsync = ref.watch(minesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter une mine')),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Aperçu caméra / photo capturée
                  AspectRatio(
                    aspectRatio: 3 / 4,
                    child: _photo != null
                        ? _PhotoInfo(photo: _photo!)
                        : _initError != null
                            ? Center(child: Text(_initError!))
                            : (_cam != null
                                ? CameraPreview(_cam!)
                                : const SizedBox.shrink()),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: Text(_photo == null ? 'Prendre la photo' : 'Reprendre'),
                    onPressed: (_capturing || _cam == null) ? null : _capture,
                  ),
                  const SizedBox(height: 16),
                  minesAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Erreur mines : $e'),
                    data: (mines) => DropdownButtonFormField<Mine>(
                      initialValue: _mine,
                      decoration: const InputDecoration(
                          labelText: 'Mine', border: OutlineInputBorder()),
                      items: mines
                          .map((m) => DropdownMenuItem(value: m, child: Text(m.nom)))
                          .toList(),
                      onChanged: (m) => setState(() => _mine = m),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                        labelText: 'Plaque (OCR)', border: const OutlineInputBorder(),
                        hintText: _plaque),
                    controller: TextEditingController(text: _plaque),
                    onChanged: (v) => _plaque = v,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _refCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Référence produit',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _couleurCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Couleur', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _qteCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Quantité estimée (kg)',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Enregistrer la mine'),
                    onPressed: _save,
                  ),
                ],
              ),
            ),
    );
  }
}

class _PhotoInfo extends StatelessWidget {
  final CapturedPhoto photo;
  const _PhotoInfo({required this.photo});
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black12,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 8),
            Text('GPS : ${photo.lat.toStringAsFixed(5)}, '
                '${photo.lon.toStringAsFixed(5)} (±${photo.precision.toStringAsFixed(0)} m)'),
            Text('Hash : ${photo.sha256.substring(0, 16)}…'),
          ],
        ),
      );
}
