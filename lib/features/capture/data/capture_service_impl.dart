import 'dart:io';
import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import '../domain/entities/captured_photo.dart';
import 'photo_compression.dart';
import '../domain/services/capture_service.dart';
import '../domain/services/heading_source.dart';
import '../domain/services/location_source.dart';

class CameraCaptureService implements CaptureService {
  final CameraController controller; // ResolutionPreset.medium injecté
  final LocationSource location;
  final HeadingSource heading;
  CameraCaptureService(this.controller, this.location, this.heading);

  @override
  Future<CapturedPhoto> capture({HeadingFix? headingFix}) async {
    final fix = await location.fix();
    if (fix.mocked) {
      throw Exception('Position GPS simulée détectée — capture refusée');
    }
    final headingFuture = headingFix == null
        ? heading.current()
        : Future<HeadingFix?>.value(headingFix);
    final file = await controller.takePicture();
    final compressedPath = await compressCapturedPhotoPath(
      sourcePath: file.path,
    );
    final capturedHeadingFix = await headingFuture;
    final bytes = await File(compressedPath).readAsBytes();
    final digest = sha256.convert(bytes).toString();
    return CapturedPhoto(
      path: compressedPath,
      sha256: digest,
      lat: fix.lat,
      lon: fix.lon,
      precision: fix.accuracy,
      takenAt: DateTime.now(),
      headingDegrees: capturedHeadingFix?.degrees,
      headingAccuracy: capturedHeadingFix?.accuracy,
      headingReference: capturedHeadingFix?.reference,
    );
  }
}
