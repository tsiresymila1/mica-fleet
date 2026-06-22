import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../domain/services/plate_ocr_service.dart';

class MlkitPlateOcrService implements PlateOcrService {
  @override
  Future<String?> readPlate(String imagePath) async {
    final recognizer = TextRecognizer();
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      final candidates = result.blocks
          .map((b) => b.text.replaceAll(RegExp(r'[^A-Z0-9]'), ''))
          .where((t) => t.length >= 5 && t.length <= 10);
      return candidates.isEmpty ? null : candidates.first;
    } finally {
      await recognizer.close();
    }
  }
}
