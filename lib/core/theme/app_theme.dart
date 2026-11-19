import 'package:flutter/material.dart';
import '../constants/app_spacing.dart';

class AppTheme {
  AppTheme._();

  // Premium palette directly derived from Kee Logo on Dark Canvas:
  // Pure Obsidian (#050505) + Warm Champagne Ivory Linen (#FBF2E6)

  // Light Mode Colors (Warm Alabaster Linen + Deep Obsidian Ink)
  static const Color _primaryLight = Color(0xFF141312);
  static const Color _onPrimaryLight = Color(0xFFFAF8F5);
  static const Color _secondaryLight = Color(0xFFA6855B);
  static const Color _backgroundLight = Color(0xFFFAF8F5);
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _surfaceVariantLight = Color(0xFFF3EFE9);
  static const Color _textPrimaryLight = Color(0xFF141312);
  static const Color _textSecondaryLight = Color(0xFF6B665E);
  static const Color _outlineLight = Color(0xFFE5DFD5);

  // Dark Mode Colors (Deep Obsidian Canvas + Warm Ivory Silk & Champagne Gold)
  static const Color _primaryDark = Color(0xFFFBF2E6);
  static const Color _onPrimaryDark = Color(0xFF050505);
  static const Color _secondaryDark = Color(0xFFE8D0B2);
  static const Color _backgroundDark = Color(0xFF050505);
  static const Color _surfaceDark = Color(0xFF111112);
  static const Color _surfaceVariantDark = Color(0xFF1C1C1E);
  static const Color _textPrimaryDark = Color(0xFFFBF2E6);
  static const Color _textSecondaryDark = Color(0xFFA39E95);
  static const Color _outlineDark = Color(0xFF272625);

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: _primaryLight,
      onPrimary: _onPrimaryLight,
      secondary: _secondaryLight,
      onSecondary: Colors.white,
      error: const Color(0xFFBA1A1A),
      onError: Colors.white,
      surface: _surfaceLight,
      onSurface: _textPrimaryLight,
      surfaceContainerHighest: _surfaceVariantLight,
      onSurfaceVariant: _textSecondaryLight,
      outline: _outlineLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _backgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _textPrimaryLight,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: _textPrimaryLight),
      ),
      cardTheme: CardThemeData(
        color: _surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: const BorderSide(color: _outlineLight, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: _outlineLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: _outlineLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: _primaryLight, width: 1.5),
        ),
        hintStyle: const TextStyle(color: _textSecondaryLight, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryLight,
          foregroundColor: _onPrimaryLight,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surfaceLight,
        elevation: 2,
        indicatorColor: _secondaryLight.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _primaryLight,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: _textSecondaryLight,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _primaryLight);
          }
          return const IconThemeData(color: _textSecondaryLight);
        }),
      ),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _primaryDark,
      onPrimary: _onPrimaryDark,
      secondary: _secondaryDark,
      onSecondary: _onPrimaryDark,
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      surface: _surfaceDark,
      onSurface: _textPrimaryDark,
      surfaceContainerHighest: _surfaceVariantDark,
      onSurfaceVariant: _textSecondaryDark,
      outline: _outlineDark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _textPrimaryDark,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: _textPrimaryDark),
      ),
      cardTheme: CardThemeData(
        color: _surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: const BorderSide(color: _outlineDark, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: _outlineDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: _outlineDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: _primaryDark, width: 1.5),
        ),
        hintStyle: const TextStyle(color: _textSecondaryDark, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryDark,
          foregroundColor: _onPrimaryDark,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surfaceDark,
        elevation: 2,
        indicatorColor: _secondaryDark.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _primaryDark,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: _textSecondaryDark,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _primaryDark);
          }
          return const IconThemeData(color: _textSecondaryDark);
        }),
      ),
    );
  }
}
