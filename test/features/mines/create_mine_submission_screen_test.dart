import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/mines/presentation/screens/create_mine_submission_screen.dart';

void main() {
  testWidgets('affiche le minimum de 5 photos et bloque la sauvegarde', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: CreateMineSubmissionScreen()),
      ),
    );

    expect(find.text('Proposer une mine'), findsWidgets);
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
}
