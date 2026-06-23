import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/capture/data/capture_service_impl.dart';
import '../features/capture/domain/entities/captured_photo.dart';
import '../features/capture/presentation/providers/capture_providers.dart';

/// Écran de capture réutilisable : photo in-app + GPS + hash, blocage mock-location.
/// Retourne un [CapturedPhoto] via Navigator.pop, ou null si annulé.
class CapturePhotoScreen extends ConsumerStatefulWidget {
  final String titre;
  const CapturePhotoScreen({super.key, required this.titre});
  @override
  ConsumerState<CapturePhotoScreen> createState() => _CapturePhotoScreenState();
}

class _CapturePhotoScreenState extends ConsumerState<CapturePhotoScreen> {
  CameraController? _cam;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() {
          _error = 'Aucune caméra disponible';
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
        _error = 'Erreur caméra : $e';
        _initializing = false;
      });
    }
  }

  @override
  void dispose() {
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final cam = _cam;
    if (cam == null) return;
    setState(() => _capturing = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final mock =
          await ref.read(mockLocationGuardProvider).isMockLocationActive();
      if (mock) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Position GPS simulée détectée — capture refusée')));
        return;
      }
      final photo = await CameraCaptureService(cam).capture();
      navigator.pop(photo);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec capture : $e')));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.titre)),
        body: _initializing
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: _error != null
                        ? Center(child: Text(_error!))
                        : (_cam != null
                            ? CameraPreview(_cam!)
                            : const SizedBox.shrink()),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Capturer'),
                      onPressed:
                          (_capturing || _cam == null) ? null : _capture,
                    ),
                  ),
                ],
              ),
      );
}
