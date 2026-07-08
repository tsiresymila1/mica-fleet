import 'dart:io';
import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import '../domain/entities/captured_photo.dart';
import '../domain/services/capture_service.dart';
import '../domain/services/location_source.dart';

class CameraCaptureService implements CaptureService {
  final CameraController controller; // ResolutionPreset.medium injecté
  final LocationSource location;
  CameraCaptureService(this.controller, this.location);

  @override
  Future<CapturedPhoto> capture() async {
    final fix = await location.fix();
    final file = await controller.takePicture();
    final bytes = await File(file.path).readAsBytes();
    final digest = sha256.convert(bytes).toString();
    return CapturedPhoto(
      path: file.path,
      sha256: digest,
      lat: fix.lat,
      lon: fix.lon,
      precision: fix.accuracy,
      takenAt: DateTime.now(),
    );
  }
}
