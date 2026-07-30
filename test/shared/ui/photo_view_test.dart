import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/shared/ui/photo_view.dart';

void main() {
  testWidgets('une photo existante est cliquable et ouvre le zoom', (
    tester,
  ) async {
    final file = File('${Directory.systemTemp.path}/mica_photo_view_test.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lE'
          'QVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PhotoThumb(path: file.path)),
      ),
    );
    expect(find.byIcon(Icons.zoom_in), findsOneWidget);

    await tester.tap(find.byType(PhotoThumb));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('une photo absente affiche le placeholder sans navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PhotoThumb(path: '/photo/introuvable.jpg')),
      ),
    );

    expect(find.byIcon(Icons.image_not_supported), findsOneWidget);
    expect(find.byIcon(Icons.zoom_in), findsNothing);
  });
}
