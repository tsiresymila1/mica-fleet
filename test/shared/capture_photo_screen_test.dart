import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mica_fleet/features/capture/domain/services/heading_source.dart';
import 'package:mica_fleet/features/capture/domain/services/location_source.dart';
import 'package:mica_fleet/features/capture/presentation/providers/capture_providers.dart';
import 'package:mica_fleet/shared/capture_photo_screen.dart';

class _Camera extends Mock implements CameraController {}

class _PendingLocation extends LocationSource {
  final pending = Completer<GpsFix>();
  int calls = 0;
  @override
  Future<GpsFix> fix() {
    calls++;
    return pending.future;
  }
}

class _Heading extends HeadingSource {
  @override
  Stream<HeadingFix> watch() => const Stream.empty();
  @override
  Future<HeadingFix?> current() async => null;
}

void main() {
  testWidgets(
    'affiche la capture en cours immédiatement et empêche le double appui',
    (tester) async {
      final camera = _Camera();
      final location = _PendingLocation();
      when(() => camera.value).thenReturn(
        const CameraValue.uninitialized(
          CameraDescription(
            name: 'test',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 0,
          ),
        ).copyWith(isInitialized: true, previewSize: const Size(640, 480)),
      );
      when(() => camera.buildPreview()).thenReturn(const SizedBox.expand());
      when(() => camera.dispose()).thenAnswer((_) async {});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cameraFactoryProvider.overrideWithValue(() async => camera),
            vehiclePhotoLocationSourceProvider.overrideWithValue(location),
            locationSourceProvider.overrideWithValue(_PendingLocation()),
            headingSourceProvider.overrideWithValue(_Heading()),
          ],
          child: const MaterialApp(
            home: CapturePhotoScreen(
              titre: 'Plaque',
              acceptAnyGpsAccuracy: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Capturer'));
      await tester.pump();
      expect(find.text('Capture en cours…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(location.calls, 1);
      await tester.tap(find.text('Capture en cours…'));
      await tester.pump();
      expect(location.calls, 1);

      location.pending.completeError(Exception('GPS indisponible'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('GPS indisponible'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Capturer'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
