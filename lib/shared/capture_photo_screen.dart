import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/capture/data/capture_service_impl.dart';
import '../features/capture/domain/entities/captured_photo.dart';
import '../features/capture/domain/services/heading_source.dart';
import '../features/capture/domain/services/location_source.dart';
import '../features/capture/presentation/providers/capture_providers.dart';
import 'ui/ui_kit.dart';

/// Écran de capture réutilisable : photo in-app + GPS + hash, blocage mock-location.
/// Retourne un [CapturedPhoto] via Navigator.pop, ou null si annulé.
class CapturePhotoScreen extends ConsumerStatefulWidget {
  final String titre;
  final bool acceptAnyGpsAccuracy;
  const CapturePhotoScreen({
    super.key,
    required this.titre,
    this.acceptAnyGpsAccuracy = false,
  });
  @override
  ConsumerState<CapturePhotoScreen> createState() => _CapturePhotoScreenState();
}

class _CapturePhotoScreenState extends ConsumerState<CapturePhotoScreen> {
  CameraController? _cam;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;
  StreamSubscription<HeadingFix>? _headingSubscription;
  HeadingFix? _liveHeading;
  HeadingFix? _latestReliableHeading;
  DateTime? _latestReliableHeadingAt;
  DateTime? _lastHeadingUiUpdate;
  late final LocationSource _locationSource;

  @override
  void initState() {
    super.initState();
    _locationSource = ref.read(
      widget.acceptAnyGpsAccuracy
          ? vehiclePhotoLocationSourceProvider
          : locationSourceProvider,
    );
    unawaited(_prepareLocation());
    _listenToHeading();
    _init();
  }

  Future<void> _prepareLocation() async {
    final source = _locationSource;
    if (source is! PreparedLocationSource) return;
    try {
      await source.prepare();
    } catch (_) {
      // La capture réessaie et présente l'erreur via le composant global.
    }
  }

  void _listenToHeading() {
    _headingSubscription = ref
        .read(headingSourceProvider)
        .watch()
        .listen(
          (fix) {
            if (!mounted) return;
            final now = DateTime.now();
            if (fix.isReliable) {
              _latestReliableHeading = fix;
              _latestReliableHeadingAt = now;
            }
            // Les capteurs peuvent publier plusieurs dizaines de mesures par seconde.
            // Limiter l'affichage évite de reconstruire la caméra à chaque événement.
            final lastUpdate = _lastHeadingUiUpdate;
            _liveHeading = fix;
            if (lastUpdate != null &&
                now.difference(lastUpdate) <
                    const Duration(milliseconds: 150)) {
              return;
            }
            _lastHeadingUiUpdate = now;
            setState(() {});
          },
          onError: (_, _) {
            if (!mounted) return;
            setState(() {
              _liveHeading = null;
              _latestReliableHeading = null;
              _latestReliableHeadingAt = null;
            });
          },
        );
  }

  Future<void> _init() async {
    try {
      final ctrl = await ref.read(cameraFactoryProvider)();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _cam = ctrl;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erreur caméra : $e';
        _initializing = false;
      });
    }
  }

  @override
  void dispose() {
    final source = _locationSource;
    if (source is PreparedLocationSource) {
      unawaited(source.stopPreparing());
    }
    _headingSubscription?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final cam = _cam;
    if (cam == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      // Let the busy label paint before JPEG compression/hash work starts.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final photo = await CameraCaptureService(
        cam,
        _locationSource,
        ref.read(headingSourceProvider),
      ).capture(headingFix: _recentReliableHeading());
      if (mounted) Navigator.of(context).pop(photo);
    } catch (e) {
      if (mounted) {
        await showAppMessage(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          kind: AppMsgKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  HeadingFix? _recentReliableHeading() {
    final measuredAt = _latestReliableHeadingAt;
    if (measuredAt == null ||
        DateTime.now().difference(measuredAt) > const Duration(seconds: 2)) {
      return null;
    }
    return _latestReliableHeading;
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
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                CameraPreview(_cam!),
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 12,
                                  child: _HeadingBadge(heading: _liveHeading),
                                ),
                              ],
                            )
                          : const SizedBox.shrink()),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  icon: _capturing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt),
                  label: Text(_capturing ? 'Capture en cours…' : 'Capturer'),
                  onPressed: (_capturing || _cam == null) ? null : _capture,
                ),
              ),
            ],
          ),
  );
}

class _HeadingBadge extends StatelessWidget {
  final HeadingFix? heading;

  const _HeadingBadge({required this.heading});

  @override
  Widget build(BuildContext context) {
    final value = heading;
    final reliable = value?.isReliable ?? false;
    final text = value == null
        ? 'Cap indisponible'
        : reliable
        ? 'Cap ${value.degrees.round()}° ${_cardinal(value.degrees)}'
        : 'Calibration de la boussole requise';
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: reliable
              ? Colors.black.withValues(alpha: 0.72)
              : Colors.orange.shade900.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

String _cardinal(double degrees) {
  const directions = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
  return directions[((degrees % 360) / 45).round() % directions.length];
}
