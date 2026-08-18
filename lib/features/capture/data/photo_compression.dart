import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as path;

const int _defaultPhotoQuality = 88;
const int _defaultMaxPhotoDimension = 1600;

Future<String> compressCapturedPhotoPath({
  required String sourcePath,
  int quality = _defaultPhotoQuality,
  int maxDimension = _defaultMaxPhotoDimension,
}) async {
  final sourceFile = File(sourcePath);
  if (!await sourceFile.exists()) return sourcePath;

  final outputPath = path.join(
    Directory.systemTemp.path,
    'mica-compress-${DateTime.now().millisecondsSinceEpoch}.jpg',
  );

  try {
    final compressed = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      outputPath,
      quality: quality,
      minWidth: maxDimension,
      minHeight: maxDimension,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (compressed == null) return sourcePath;

    final compressedFile = File(compressed.path);
    if (!await compressedFile.exists()) return sourcePath;

    final sourceSize = await sourceFile.length();
    final compressedSize = await compressedFile.length();
    if (compressedSize >= sourceSize) {
      await _safeDelete(compressedFile);
      return sourcePath;
    }

    await _safeDelete(sourceFile);
    return compressed.path;
  } catch (_) {
    return sourcePath;
  }
}

Future<void> _safeDelete(File file) async {
  try {
    await file.delete();
  } catch (_) {
    // Ignore cleanup failures to avoid blocking capture.
  }
}
