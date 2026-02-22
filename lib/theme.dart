import 'package:flutter/material.dart';

class KLPalette {
  // Brand
  static const primary = Color(0xFF027DFD);
  static const primary600 = Color(0xFF0273E9);
  static const primary700 = Color(0xFF0267CF);

  // Tints (for chips, highlights, selected states)
  static const tint50 = Color(0xFFEBF5FF);
  static const tint100 = Color(0xFFD9ECFF);
  static const tint200 = Color(0xFFB8DBFE);

  // Neutrals
  static const bg = Color(0xFFFFFFFF);
  static const mutedBg = Color(0xFFF8FAFC);
  static const border = Color(0xFFE2E8F0);

  static const text = Color(0xFF0F172A);
  static const text2 = Color(0xFF64748B);

  static const darkPill = Color(0xFF111827);
}

ThemeData buildKLTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: KLPalette.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: KLPalette.primary,
    onPrimary: Colors.white,
    surface: KLPalette.bg,
    onSurface: KLPalette.text,
    background: KLPalette.bg,
    onBackground: KLPalette.text,
    surfaceVariant: KLPalette.mutedBg,
    onSurfaceVariant: KLPalette.text2,
    outline: KLPalette.border,
    error: const Color(0xFFDC2626),
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: KLPalette.bg,

    appBarTheme: const AppBarTheme(
      backgroundColor: KLPalette.bg,
      foregroundColor: KLPalette.text,
      elevation: 0,
      centerTitle: false,
    ),

    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontWeight: FontWeight.w800,
        color: KLPalette.text,
      ),
      titleLarge: TextStyle(
        fontWeight: FontWeight.w800,
        color: KLPalette.text,
      ),
      titleMedium: TextStyle(
        fontWeight: FontWeight.w700,
        color: KLPalette.text,
      ),
      bodyMedium: TextStyle(color: KLPalette.text),
      bodySmall: TextStyle(color: KLPalette.text2),
    ),

    cardTheme: CardThemeData(
      color: KLPalette.bg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: KLPalette.border),
      ),
      margin: EdgeInsets.zero,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KLPalette.bg,
      hintStyle: const TextStyle(color: KLPalette.text2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: const BorderSide(color: KLPalette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: const BorderSide(color: KLPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: const BorderSide(color: KLPalette.primary, width: 1.6),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: KLPalette.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: KLPalette.tint200,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 50),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: KLPalette.text,
        side: const BorderSide(color: KLPalette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        minimumSize: const Size(0, 50),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: const BorderSide(color: KLPalette.border),
      backgroundColor: KLPalette.tint50,
      selectedColor: KLPalette.tint100,
      labelStyle: const TextStyle(
        color: KLPalette.primary700,
        fontWeight: FontWeight.w600,
      ),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: KLPalette.bg,
      selectedItemColor: KLPalette.primary,
      unselectedItemColor: KLPalette.text2,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
    ),

    dividerTheme: const DividerThemeData(
      color: KLPalette.border,
      thickness: 1,
      space: 1,
    ),
  );
}
