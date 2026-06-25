import 'dart:io';
import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/utils/location.dart';
import '../domain/entities/captured_photo.dart';
import '../domain/services/capture_service.dart';

class CameraCaptureService implements CaptureService {
  final CameraController controller; // ResolutionPreset.medium injecté
  CameraCaptureService(this.controller);

  @override
  Future<CapturedPhoto> capture() async {
    await ensureLocationReady();
    final file = await controller.takePicture();
    final bytes = await File(file.path).readAsBytes();
    final digest = sha256.convert(bytes).toString();
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return CapturedPhoto(
      path: file.path,
      sha256: digest,
      lat: pos.latitude,
      lon: pos.longitude,
      precision: pos.accuracy,
      takenAt: DateTime.now(),
    );
  }
}
