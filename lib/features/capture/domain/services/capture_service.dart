import '../entities/captured_photo.dart';

abstract class CaptureService {
  /// Prend une photo IN-APP (jamais galerie), compresse, calcule GPS + hash.
  Future<CapturedPhoto> capture();
}
