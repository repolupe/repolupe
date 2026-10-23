import 'package:flutter/material.dart';

const _primary = Color(0xFF00002B);

ThemeData getTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _primary,
    brightness: brightness,
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    // In the color of the text instead of the primary color, disabled ones keep the default.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        iconColor: colorScheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
  );
}
