import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Thème « minéral guidé » — pensé pour le terrain : fort contraste plein soleil,
/// grandes cibles tactiles, icône + texte court, états couleur lisibles.
class AppColors {
  static const paper = Color(0xFFF6F4EE); // fond papier chaud
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1A1F1C); // texte
  static const inkSoft = Color(0xFF5B635E);
  static const primary = Color(0xFF15604A); // vert émeraude minéral
  static const primaryDark = Color(0xFF0E4334);
  static const gold = Color(0xFFE0A93B); // or mica (accent)
  static const ok = Color(0xFF1F8A5B);
  static const warn = Color(0xFFE08A1E);
  static const danger = Color(0xFFC0492F);
  static const line = Color(0xFFE3DFD5);
}

class AppTheme {
  static ThemeData build() {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
    final display = GoogleFonts.bricolageGrotesque;
    final body = GoogleFonts.plusJakartaSans;

    final scheme = const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.gold,
      onSecondary: AppColors.ink,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.paper,
      colorScheme: scheme,
      textTheme: base.textTheme
          .copyWith(
            displaySmall: display(fontWeight: FontWeight.w700),
            headlineMedium:
                display(fontWeight: FontWeight.w700, color: AppColors.ink),
            headlineSmall:
                display(fontWeight: FontWeight.w700, color: AppColors.ink),
            titleLarge:
                display(fontWeight: FontWeight.w600, color: AppColors.ink),
            titleMedium:
                body(fontWeight: FontWeight.w600, color: AppColors.ink),
            bodyLarge: body(fontSize: 17, color: AppColors.ink),
            bodyMedium: body(fontSize: 15, color: AppColors.inkSoft),
            labelLarge: body(fontWeight: FontWeight.w700),
          )
          .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: display(
            fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(64),
          textStyle: body(fontSize: 18, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(60),
          side: const BorderSide(color: AppColors.primary, width: 2),
          textStyle: body(fontSize: 17, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        labelStyle: body(fontSize: 16, color: AppColors.inkSoft),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
