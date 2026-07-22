import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Thème « minéral » mobile — simple, moderne, lisible. Tailles compactes,
/// Montserrat (titres) + ABeeZee (corps). Fort contraste pour le terrain.
class AppColors {
  static const paper = Color(0xFFF7F6F2); // fond clair
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1A1F1C); // texte
  static const inkSoft = Color(0xFF6B736E);
  static const primary = Color(0xFF15604A); // vert émeraude minéral
  static const primaryDark = Color(0xFF0E4334);
  static const gold = Color(0xFFD99A2B); // or mica (accent)
  static const ok = Color(0xFF1F8A5B);
  static const warn = Color(0xFFE08A1E);
  static const danger = Color(0xFFC0492F);
  static const line = Color(0xFFE6E2D9);
}

/// Barres système sur fond clair (écrans sans AppBar) : icônes sombres, sinon
/// elles restent blanches et deviennent invisibles.
const kOverlaySurClair = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark, // Android
  statusBarBrightness: Brightness.light, // iOS
  systemNavigationBarColor: AppColors.paper,
  systemNavigationBarIconBrightness: Brightness.dark,
);

/// Barres système sous l'AppBar verte : icônes claires.
const kOverlaySurPrimaire = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: AppColors.paper,
  systemNavigationBarIconBrightness: Brightness.dark,
);

class AppTheme {
  static ThemeData build() {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);

    TextStyle display(
            {double? fontSize, FontWeight? fontWeight, Color? color}) =>
        TextStyle(
            fontFamily: 'Montserrat',
            fontSize: fontSize,
            fontWeight: fontWeight,
            height: 1.2,
            color: color);
    TextStyle body({double? fontSize, FontWeight? fontWeight, Color? color}) =>
        TextStyle(
            fontFamily: 'ABeeZee',
            fontSize: fontSize,
            fontWeight: fontWeight,
            height: 1.35,
            color: color);

    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.gold,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.paper,
      colorScheme: scheme,
      textTheme: base.textTheme
          .copyWith(
            displaySmall: display(fontSize: 26, fontWeight: FontWeight.w700),
            headlineMedium:
                display(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink),
            headlineSmall:
                display(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
            titleLarge:
                display(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
            titleMedium:
                display(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
            bodyLarge: body(fontSize: 14, color: AppColors.ink),
            bodyMedium: body(fontSize: 12.5, color: AppColors.inkSoft),
            labelLarge: display(fontSize: 14, fontWeight: FontWeight.w600),
          )
          .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        systemOverlayStyle: kOverlaySurPrimaire,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: display(
            fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: display(fontSize: 15, fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(50),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          textStyle: display(fontSize: 14, fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: body(fontSize: 14, color: AppColors.inkSoft),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
    );
  }
}
