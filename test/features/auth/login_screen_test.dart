import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/theme/app_theme.dart';
import 'package:mica_fleet/features/auth/presentation/screens/login_screen.dart';

void main() {
  testWidgets('affiche le logo officiel Radoran sur le fond clair', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.build(), home: const LoginScreen()),
      ),
    );
    await tester.pump();

    final logo = tester.widget<Image>(find.byType(Image).first);
    expect(
      (logo.image as AssetImage).assetName,
      'assets/logos/radoran_logo.png',
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      isNull,
    );
    expect(AppTheme.build().scaffoldBackgroundColor, AppColors.paper);
  });
}
