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

extension TemporaryColors on ColorScheme {
  /// The page background of a temporary chat, the same as the web's.
  Color get temporary => switch (brightness) {
    Brightness.light => const Color(0xFFE4E3F7),
    Brightness.dark => const Color(0xFF211A33),
  };

  /// [temporary] a shade apart, as [surfaceContainer] is from [surface], e.g. for the app bar scrolled under.
  Color get temporaryContainer => Color.alphaBlend(onSurface.withValues(alpha: 0.05), temporary);
}
