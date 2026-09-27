import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/theme/app_theme.dart';

void main() {
  test('utilise la palette claire officielle Radoran', () {
    final theme = AppTheme.build();

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF5F2ED));
    expect(theme.colorScheme.primary, const Color(0xFFBD345A));
    expect(theme.colorScheme.primaryContainer, const Color(0xFFED6976));
    expect(theme.colorScheme.secondary, const Color(0xFF653472));
    expect(theme.colorScheme.tertiary, const Color(0xFF2B367D));
    expect(theme.colorScheme.onPrimary, Colors.white);
  });

  test('conserve des couleurs métier distinctes de la marque', () {
    expect(AppColors.ok, isNot(AppColors.primary));
    expect(AppColors.warn, isNot(AppColors.primary));
    expect(AppColors.danger, isNot(AppColors.primary));
  });
}
