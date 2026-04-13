import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  /// Onboarding / auth wordmark (Playfair + forest green).
  static const Color publicCommonsForest = Color(0xFF1B3022);

  /// Warm cream used for onboarding and auth screens.
  static const Color publicCommonsCream = Color(0xFFFDF9F3);

  /// Playfair wordmark (sign-in, etc.) after [preloadKindredGoogleFonts].
  static TextStyle publicCommonsWordmark() {
    return GoogleFonts.playfairDisplay(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      color: publicCommonsForest,
      height: 1.12,
    );
  }

  static ThemeData light() {
    const seed = Color(0xFF2E7D5A);
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
        primary: seed,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(centerTitle: true, scrolledUnderElevation: 0),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 2,
      ),
    );
  }

  /// Activity bubble hues (Material green / blue / deep orange).
  static const double hueOffer = 120;
  static const double hueRequest = 210;
  static const double hueEvent = 30;
}
