import 'package:flutter/material.dart';

abstract final class AppColors {
  static const page = Color(0xFFF3F5F2);
  static const ink = Color(0xFF111816);
  static const muted = Color(0xFF5D6863);
  static const border = Color(0xFFDCE2DE);
  static const primary = Color(0xFF0E6B50);
  static const primaryDark = Color(0xFF084D3B);
  static const graphite = Color(0xFF111714);
  static const success = Color(0xFF0B7A55);
  static const warning = Color(0xFFB66B16);
  static const danger = Color(0xFFC33B32);
  static const softGreen = Color(0xFFE8F3EE);
  static const softAmber = Color(0xFFFFF3E3);
  static const softRed = Color(0xFFFCEBE9);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
    surface: Colors.white,
    error: AppColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.page,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.page,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
  );
}
