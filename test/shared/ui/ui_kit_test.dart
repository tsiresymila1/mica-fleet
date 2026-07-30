import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/shared/ui/ui_kit.dart';

void main() {
  testWidgets('showAppToast affiche une confirmation non bloquante', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    showAppToast(context, 'Synchronisation lancée');
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Synchronisation lancée'), findsOneWidget);
  });
}
