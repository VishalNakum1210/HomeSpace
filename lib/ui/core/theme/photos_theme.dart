import 'package:flutter/material.dart';

class PhotosColors {
  static const Color googleBlue = Color(0xFF1A73E8);
  static const Color googleRed = Color(0xFFEA4335);
  static const Color googleYellow = Color(0xFFFBBC04);
  static const Color googleGreen = Color(0xFF34A853);

  // Dark theme surfaces
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkSurfaceVariant = Color(0xFF2C2C2C);
  static const Color darkBorder = Color(0xFF383838);

  // Light theme surfaces
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFF8F9FA);
  static const Color lightSurfaceVariant = Color(0xFFEEF0F2);
  static const Color lightBorder = Color(0xFFE0E0E0);
}

class PhotosTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: PhotosColors.googleBlue,
        brightness: Brightness.light,
        surface: PhotosColors.lightSurface,
      ),
      scaffoldBackgroundColor: PhotosColors.lightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: PhotosColors.lightBackground,
        selectedItemColor: PhotosColors.googleBlue,
        unselectedItemColor: Color(0xFF5F6368),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: PhotosColors.googleBlue,
        brightness: Brightness.dark,
        surface: PhotosColors.darkSurface,
      ),
      scaffoldBackgroundColor: PhotosColors.darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: PhotosColors.darkBackground,
        selectedItemColor: Color(0xFF8AB4F8), // Google Blue light
        unselectedItemColor: Color(0xFF9AA0A6),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      ),
    );
  }
}
