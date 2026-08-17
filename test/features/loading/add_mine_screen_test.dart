import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/loading/presentation/screens/add_mine_screen.dart';
import 'package:mica_fleet/features/mines/domain/entities/mine.dart';
import 'package:mica_fleet/features/mines/presentation/providers/mines_provider.dart';

void main() {
  testWidgets(
    'présente le chargement comme deux captures explicites sans caméra permanente',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            minesProvider.overrideWith(
              (ref) async => const [
                Mine(id: '1', nom: 'Mine Antsahabe', lat: -18.91, lon: 47.52),
              ],
            ),
          ],
          child: const MaterialApp(home: AddMineScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chargement à la mine'), findsOneWidget);
      expect(find.text('Photos du chargement — 0/2'), findsOneWidget);
      expect(find.text('Photo de la plaque'), findsOneWidget);
      expect(find.text('Photo du mica'), findsNothing);
      expect(find.text('Photo du camion avec mica'), findsOneWidget);
      expect(
        find.textContaining('Appuyer pour prendre la photo'),
        findsNWidgets(2),
      );

      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Enregistrer le lot'),
      );
      expect(saveButton.onPressed, isNull);
    },
  );
}
