import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/shared/ui/photo_view.dart';
import 'package:mica_fleet/shared/ui/ui_kit.dart';

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

  testWidgets('une URL serveur est cliquable et ouvre le zoom', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PhotoThumb(
            path: 'https://example.test/web/image/42?access_token=test',
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.zoom_in), findsOneWidget);
    openPhoto(
      tester.element(find.byType(PhotoThumb)),
      'https://example.test/web/image/42?access_token=test',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets(
    'la miniature ouvre le preview sans déclencher la recapture de la ligne',
    (tester) async {
      var captures = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionTile(
              icon: Icons.camera_alt,
              color: Colors.green,
              titre: 'Photo de la plaque',
              onTap: () => captures++,
              trailing: const PhotoThumb(
                path: 'assets/logos/mica_logo.png',
                size: 48,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PhotoThumb));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(captures, 0);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photo de la plaque'));
      await tester.pumpAndSettle();
      expect(captures, 1);
      expect(find.byType(InteractiveViewer), findsNothing);
    },
  );
}
