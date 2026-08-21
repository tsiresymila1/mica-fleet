import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/di/providers.dart';
import 'package:mica_fleet/features/auth/domain/entities/fournisseur.dart';
import 'package:mica_fleet/features/auth/presentation/providers/auth_provider.dart';
import 'package:mica_fleet/features/mines/presentation/screens/mine_submissions_screen.dart';

class _SignedInAuthController extends AuthController {
  @override
  Fournisseur? build() => const Fournisseur(id: 'eddy', nom: 'Eddy');
}

void main() {
  testWidgets('propose un envoi manuel pour une mine locale', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 5, 8);
    await db
        .into(db.mineSubmissions)
        .insert(
          MineSubmissionsCompanion.insert(
            payloadId: 'payload-local',
            deviceUuid: 'device-local',
            nom: 'Mine hors ligne',
            agentLogin: const Value('eddy'),
            createdAt: now,
            updatedAt: now,
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          authControllerProvider.overrideWith(_SignedInAuthController.new),
        ],
        child: const MaterialApp(home: MineSubmissionsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Référence : —'), findsOneWidget);
    expect(find.textContaining('Créée le : 05/08/2026'), findsOneWidget);
    expect(find.textContaining('Note : —'), findsOneWidget);
    await tester.tap(find.text('Mine hors ligne'));
    await tester.pumpAndSettle();

    expect(find.text('Envoyer maintenant'), findsOneWidget);
  });

  testWidgets('affiche Envoyée, ouvre le détail puis supprime localement', (
    tester,
  ) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final submissionDirectory = Directory.systemTemp.createTempSync(
      'mica_submission_detail_',
    );
    final photo = File('${submissionDirectory.path}/position_1.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    addTearDown(() {
      if (submissionDirectory.existsSync()) {
        submissionDirectory.deleteSync(recursive: true);
      }
    });
    final now = DateTime.utc(2026, 8, 5, 8);
    await db
        .into(db.mineSubmissions)
        .insert(
          MineSubmissionsCompanion.insert(
            payloadId: 'payload-detail',
            deviceUuid: 'device-detail',
            nom: 'Mine terrain',
            communeId: const Value(24091),
            state: const Value('pending_validation'),
            serverId: const Value(42),
            agentLogin: const Value('eddy'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.mineSubmissionPhotos)
        .insert(
          MineSubmissionPhotosCompanion.insert(
            payloadId: 'payload-detail',
            key: 'position_1',
            path: photo.path,
            hash: 'photo-hash',
            lat: -18.91,
            lon: 47.52,
            gpsAccuracy: 4,
            headingDegrees: const Value(125),
            headingReference: const Value('magnetic'),
            capturedAt: now,
            uploaded: const Value(true),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          authControllerProvider.overrideWith(_SignedInAuthController.new),
        ],
        child: const MaterialApp(home: MineSubmissionsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Envoyée'), findsOneWidget);
    await tester.tap(find.text('Mine terrain'));
    await tester.pumpAndSettle();

    expect(find.text('Détails de la proposition'), findsOneWidget);
    expect(find.textContaining('Cap 125°'), findsOneWidget);
    expect(find.text('Supprimer de cet appareil'), findsOneWidget);

    await tester.ensureVisible(find.text('Supprimer de cet appareil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer de cet appareil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    expect(await db.select(db.mineSubmissions).get(), isEmpty);
    expect(find.text('Aucune mine proposée'), findsOneWidget);
  });
}
