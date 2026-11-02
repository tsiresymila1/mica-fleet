import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/theme/app_theme.dart';
import 'package:mica_fleet/features/profile/presentation/screens/help_screen.dart';

void main() {
  testWidgets('présente un guide visuel des lots sur un écran étroit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.build(), home: const HelpScreen()),
    );

    expect(find.text('Guide rapide'), findsOneWidget);
    expect(find.text('Rechercher'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('TRANSPORT'), 250);
    expect(find.text('Dépôt AMB'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Bande à gauche · validation'),
      250,
    );
    expect(find.text('Vert'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Nuage coché'), 250);
    expect(find.text('Lot synchronisé et validé'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Exemple de score'), 250);
    expect(find.text('65'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Hors connexion'), 250);
    expect(find.text('Proposer une mine'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
