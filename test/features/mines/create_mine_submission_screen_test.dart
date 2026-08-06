import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/di/providers.dart';
import 'package:mica_fleet/features/mines/presentation/screens/create_mine_submission_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() => db.close());

  testWidgets('ouvre un sheet de communes avec recherche', (tester) async {
    await db
        .into(db.communes)
        .insert(
          CommunesCompanion.insert(id: const Value(24091), nom: 'Andilana'),
        );
    await db
        .into(db.communes)
        .insert(
          CommunesCompanion.insert(id: const Value(24092), nom: 'Ambatomena'),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CreateMineSubmissionScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Proposer une mine'), findsWidgets);
    expect(find.text('Sélectionner une commune'), findsOneWidget);
    await tester.tap(find.text('Sélectionner une commune'));
    await tester.pumpAndSettle();

    expect(find.text('Choisir une commune'), findsOneWidget);
    expect(find.text('Rechercher une commune'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Rechercher une commune'),
      'Andi',
    );
    await tester.pump();
    expect(find.text('Andilana'), findsOneWidget);
    expect(find.text('Ambatomena'), findsNothing);

    await tester.tap(find.text('Andilana'));
    await tester.pumpAndSettle();
    expect(find.text('Choisir une commune'), findsNothing);
    expect(find.text('Andilana'), findsOneWidget);
    expect(find.textContaining('5 photo(s) restante(s)'), findsOneWidget);
    expect(find.text('Enregistrer localement'), findsOneWidget);

    final saveButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Enregistrer localement'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('signale que le cache commune est vide hors ligne', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CreateMineSubmissionScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Aucune commune disponible'), findsOneWidget);
  });
}
