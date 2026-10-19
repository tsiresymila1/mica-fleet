import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/loading/presentation/screens/add_mine_screen.dart';
import 'package:mica_fleet/features/mines/domain/entities/mine.dart';
import 'package:mica_fleet/features/mines/domain/entities/mine_submission.dart';
import 'package:mica_fleet/features/mines/presentation/providers/mine_submissions_provider.dart';
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
              (ref) async => [
                Mine(
                  id: '1',
                  nom: 'Mine Antsahabe',
                  lat: -18.91,
                  lon: 47.52,
                  createdAt: DateTime.utc(2026, 8, 20),
                  reference: 'REF-1',
                  district: 'Ambilobe',
                  commune: 'Ambakirano',
                  fokontany: 'Antsahabe',
                ),
              ],
            ),
            mineSubmissionsProvider.overrideWith(
              (ref) async => [
                MineSubmission(
                  payloadId: 'local-mine-uuid',
                  deviceUuid: 'local-device-uuid',
                  nom: 'Mine locale hors ligne',
                  state: MineSubmissionState.localPending,
                  createdAt: DateTime.utc(2026, 8, 15),
                  updatedAt: DateTime.utc(2026, 8, 15),
                  photos: const [],
                ),
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
      expect(find.text('Couleur du mica'), findsNothing);
      expect(
        find.textContaining('Appuyer pour prendre la photo'),
        findsNWidgets(2),
      );

      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Enregistrer le lot'),
      );
      expect(saveButton.onPressed, isNull);
      expect(find.text('Quantité estimée (kg) *'), findsOneWidget);
      tester.state<FormState>(find.byType(Form)).validate();
      await tester.pump();
      expect(find.text('Saisis une quantité supérieure à 0'), findsOneWidget);

      expect(find.text('Aucune mine sélectionnée'), findsOneWidget);
      await tester.tap(find.text('Choisir la mine d’origine'));
      await tester.pumpAndSettle();

      expect(find.text('Rechercher une mine'), findsOneWidget);
      expect(find.textContaining('REF-1'), findsWidgets);
      expect(find.textContaining('Antsahabe'), findsWidgets);
      expect(find.textContaining('Ambakirano'), findsWidgets);
      expect(find.textContaining('Ambilobe'), findsWidgets);
      expect(find.text('Mine locale hors ligne'), findsOneWidget);
      expect(find.textContaining('Créée manuellement'), findsOneWidget);
    },
  );

  testWidgets(
    'aucune mine par défaut et choix triés du plus récent au plus ancien',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            minesProvider.overrideWith(
              (ref) async => [
                Mine(
                  id: 'older',
                  nom: 'Mine ancienne',
                  lat: -18.91,
                  lon: 47.52,
                  createdAt: DateTime.utc(2026, 8, 10),
                ),
                const Mine(
                  id: 'without-date',
                  nom: 'Mine sans date',
                  lat: -18.91,
                  lon: 47.52,
                ),
                Mine(
                  id: 'newer',
                  nom: 'Mine récente',
                  lat: -18.91,
                  lon: 47.52,
                  createdAt: DateTime.utc(2026, 8, 20),
                ),
              ],
            ),
            mineSubmissionsProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(home: AddMineScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aucune mine sélectionnée'), findsOneWidget);
      expect(find.text('Mine récente'), findsNothing);
      expect(find.text('Mine ancienne'), findsNothing);
      expect(find.text('Mine sans date'), findsNothing);
      await tester.tap(find.text('Choisir la mine d’origine'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Mine récente')).dy,
        lessThan(tester.getTopLeft(find.text('Mine ancienne')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Mine ancienne')).dy,
        lessThan(tester.getTopLeft(find.text('Mine sans date')).dy),
      );
      await tester.tap(find.text('Mine récente'));
      await tester.pumpAndSettle();
      expect(find.text('Mine récente'), findsOneWidget);
      expect(find.text('Aucune mine sélectionnée'), findsNothing);
    },
  );

  testWidgets(
    'n’affiche qu’une fois une proposition ayant déjà un id serveur',
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
                Mine(
                  id: '77',
                  nom: 'Mine déjà envoyée',
                  lat: -18.91,
                  lon: 47.52,
                ),
              ],
            ),
            mineSubmissionsProvider.overrideWith(
              (ref) async => [
                MineSubmission(
                  payloadId: 'local-payload',
                  deviceUuid: 'local-device',
                  nom: 'Mine déjà envoyée',
                  state: MineSubmissionState.pendingValidation,
                  serverId: 77,
                  createdAt: DateTime.utc(2026, 8, 21),
                  updatedAt: DateTime.utc(2026, 8, 21),
                  photos: const [],
                ),
              ],
            ),
          ],
          child: const MaterialApp(home: AddMineScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mine déjà envoyée'), findsNothing);
      await tester.tap(find.text('Choisir la mine d’origine'));
      await tester.pumpAndSettle();

      expect(find.text('Mine déjà envoyée'), findsOneWidget);
      expect(find.textContaining('Créée manuellement'), findsNothing);
    },
  );
}
