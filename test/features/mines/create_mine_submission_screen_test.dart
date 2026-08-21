import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/di/providers.dart';
import 'package:mica_fleet/features/mines/presentation/screens/create_mine_submission_screen.dart';

void main() {
  testWidgets('ne demande aucune commune et explique la résolution GPS', (
    tester,
  ) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CreateMineSubmissionScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Proposer une mine'), findsWidgets);
    expect(find.text('Commune'), findsNothing);
    expect(find.text('Sélectionner une commune'), findsNothing);
    expect(find.text('Rechercher une commune'), findsNothing);
    expect(find.textContaining('déterminés par le serveur'), findsOneWidget);
    expect(find.textContaining('0/5 minimum'), findsOneWidget);

    final saveButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Enregistrer localement'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(saveButton.onPressed, isNull);
  });
}
