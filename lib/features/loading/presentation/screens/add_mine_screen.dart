import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../capture/data/capture_service_impl.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../../../capture/presentation/providers/capture_providers.dart';
import '../../../mines/domain/entities/mine.dart';
import '../../../mines/presentation/providers/mines_provider.dart';
import '../../../trip/presentation/sim_session.dart';
import '../../domain/entities/lot.dart';

/// Saisie d'une mine : photo in-app (GPS+hash), OCR plaque, mine + données produit.
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
  final _refCtrl = TextEditingController();
  final _couleurCtrl = TextEditingController();
  final _qteCtrl = TextEditingController();
  final _plaqueCtrl = TextEditingController();

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
          _initError = 'Aucune caméra';
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
        _initError = 'Erreur caméra';
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
    _plaqueCtrl.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final cam = _cam;
    if (cam == null) return;
    setState(() => _capturing = true);
    try {
      final mock =
          await ref.read(mockLocationGuardProvider).isMockLocationActive();
      if (mock) {
        if (mounted) {
          await showAppMessage(context, 'GPS faux détecté — photo refusée',
              kind: AppMsgKind.warning);
        }
        return;
      }
      final photo =
          await CameraCaptureService(cam, ref.read(locationSourceProvider))
              .capture();
      // Simulation : la plaque est « lue » après la photo (comme l'OCR).
      final sim = ref.read(simSessionProvider);
      final plaque = sim != null
          ? ref.read(simSessionProvider.notifier).plate
          : await ref.read(plateOcrServiceProvider).readPlate(photo.path);
      if (!mounted) return;
      setState(() {
        _photo = photo;
        if (plaque != null) _plaqueCtrl.text = plaque;
      });
    } catch (e) {
      if (mounted) {
        await showAppMessage(
            context, e.toString().replaceFirst('Exception: ', ''),
            kind: AppMsgKind.error);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _save() {
    if (_mine == null || _photo == null) {
      showAppMessage(context, 'Choisis la mine et prends la photo',
          kind: AppMsgKind.warning);
      return;
    }
    // L'id définitif du lot est attribué par AddLotToChargement (<session>-L<n>).
    Navigator.of(context).pop(Lot(
      id: '',
      mineId: _mine!.id,
      reference: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
      couleur:
          _couleurCtrl.text.trim().isEmpty ? null : _couleurCtrl.text.trim(),
      quantiteEstimee: double.tryParse(_qteCtrl.text.replaceAll(',', '.')),
      plaqueDepart:
          _plaqueCtrl.text.trim().isEmpty ? null : _plaqueCtrl.text.trim(),
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              children: [
                StepHeader(
                    numero: 1,
                    titre: 'La photo',
                    sousTitre: 'Camion + plaque + mica visibles'),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: _photo != null
                        ? _PhotoInfo(photo: _photo!)
                        : _initError != null
                            ? Container(
                                color: AppColors.line,
                                child: Center(child: Text(_initError!)))
                            : (_cam != null
                                ? CameraPreview(_cam!)
                                : const SizedBox.shrink()),
                  ),
                ),
                const SizedBox(height: 12),
                BigButton(
                  icon: _photo == null ? Icons.camera_alt : Icons.refresh,
                  label: _photo == null ? 'Prendre la photo' : 'Reprendre',
                  color: _photo == null ? null : AppColors.gold,
                  onPressed: (_capturing || _cam == null) ? null : _capture,
                ),
                const SizedBox(height: 24),
                StepHeader(numero: 2, titre: 'La mine'),
                const SizedBox(height: 12),
                minesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) =>
                      const Text('Impossible de charger les mines'),
                  data: (mines) {
                    if (ref.read(simSessionProvider) != null &&
                        _mine == null &&
                        mines.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _mine = mines.first);
                      });
                    }
                    return DropdownButtonFormField<Mine>(
                      initialValue: _mine,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Choisir la mine',
                        prefixIcon: Icon(Icons.landscape)),
                    items: mines
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m.nom)))
                        .toList(),
                    onChanged: (m) => setState(() => _mine = m),
                    );
                  },
                ),
                const SizedBox(height: 24),
                StepHeader(numero: 3, titre: 'Les détails'),
                const SizedBox(height: 12),
                TextField(
                  controller: _plaqueCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Plaque du camion',
                      prefixIcon: Icon(Icons.directions_car)),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: _couleurCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Couleur du mica',
                        prefixIcon: Icon(Icons.palette))),
                const SizedBox(height: 12),
                TextField(
                    controller: _refCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Référence (si connue)',
                        prefixIcon: Icon(Icons.tag))),
                const SizedBox(height: 12),
                TextField(
                    controller: _qteCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Quantité estimée (kg)',
                        prefixIcon: Icon(Icons.scale))),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: BigButton(
            icon: Icons.check, label: 'Enregistrer', onPressed: _save),
      ),
    );
  }
}

class _PhotoInfo extends StatelessWidget {
  final CapturedPhoto photo;
  const _PhotoInfo({required this.photo});
  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.primary.withValues(alpha: 0.06),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified, color: AppColors.ok, size: 64),
            const SizedBox(height: 12),
            const StatusPill(kind: PillKind.ok, label: 'Photo prise'),
            const SizedBox(height: 12),
            Text(
                'GPS ${photo.lat.toStringAsFixed(4)}, '
                '${photo.lon.toStringAsFixed(4)}',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}
