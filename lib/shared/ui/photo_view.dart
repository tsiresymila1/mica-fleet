import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Ouvre une photo en plein écran, zoomable (InteractiveViewer).
/// Animation : la vignette « grandit » vers le plein écran (Hero) + fond en fondu.
void openPhoto(BuildContext context, String path) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => _PhotoViewer(path: path),
    transitionsBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  ));
}

class _PhotoViewer extends StatelessWidget {
  final String path;
  const _PhotoViewer({required this.path});
  @override
  Widget build(BuildContext context) {
    final exists = File(path).existsSync();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: exists
            ? Hero(
                tag: path,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Image.file(File(path), fit: BoxFit.contain),
                ),
              )
            : const Text('Image indisponible',
                style: TextStyle(color: Colors.white70)),
      ),
    );
  }
}

/// Vignette photo cliquable → ouvre le viewer plein écran. Placeholder si absente.
class PhotoThumb extends StatelessWidget {
  final String? path;
  final double size;
  const PhotoThumb({super.key, required this.path, this.size = 64});
  @override
  Widget build(BuildContext context) {
    final ok = path != null && File(path!).existsSync();
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: ok
            ? Hero(
                tag: path!,
                child: Image.file(File(path!), fit: BoxFit.cover))
            : Container(
                color: AppColors.line,
                child: const Icon(Icons.image_not_supported,
                    color: AppColors.inkSoft)),
      ),
    );
    if (!ok) return thumb;
    return GestureDetector(
      onTap: () => openPhoto(context, path!),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          thumb,
          Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4)),
            child: const Icon(Icons.zoom_in, size: 14, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
