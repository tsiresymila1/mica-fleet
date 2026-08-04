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

  testWidgets('affiche un select de communes recherchable', (tester) async {
    await db
        .into(db.communes)
        .insert(
          CommunesCompanion.insert(id: const Value(24091), nom: 'Andilana'),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CreateMineSubmissionScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Proposer une mine'), findsWidgets);
    final communeSelect = tester.widget<DropdownMenu<int>>(
      find.byType(DropdownMenu<int>),
    );
    expect(communeSelect.enableFilter, isTrue);
    expect(communeSelect.enableSearch, isTrue);
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
