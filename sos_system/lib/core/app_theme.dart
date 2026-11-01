import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// TravelGuard "Calm Shield" palette: calm teal for everyday use,
/// red reserved for SOS and emergencies only.
class TG {
  TG._();

  static const teal = Color(0xFF0F766E);
  static const tealDark = Color(0xFF0B5A54);
  static const sos = Color(0xFFD7263D);
  static const sosDark = Color(0xFFA51B2E);
  static const warn = Color(0xFFB45309);

  // light
  static const bg = Color(0xFFF4F7F6);
  static const surface = Color(0xFFFFFFFF);
  static const field = Color(0xFFF0F3F2);
  static const tealSoft = Color(0xFFD7EFEA);
  static const ink = Color(0xFF10201D);
  static const muted = Color(0xFF4F5F5C);
  static const line = Color(0xFFCFDCD9);

  // dark
  static const bgDark = Color(0xFF0E1614);
  static const surfaceDark = Color(0xFF172220);
  static const fieldDark = Color(0xFF1F2C29);
  static const tealSoftDark = Color(0xFF12302C);
  static const inkDark = Color(0xFFE8EFED);
  static const mutedDark = Color(0xFF9DB0AB);
  static const lineDark = Color(0xFF2C3B38);

  static bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color bgOf(BuildContext c) => isDark(c) ? bgDark : bg;
  static Color surfaceOf(BuildContext c) => isDark(c) ? surfaceDark : surface;
  static Color fieldOf(BuildContext c) => isDark(c) ? fieldDark : field;
  static Color softOf(BuildContext c) => isDark(c) ? tealSoftDark : tealSoft;
  static Color inkOf(BuildContext c) => isDark(c) ? inkDark : ink;
  static Color mutedOf(BuildContext c) => isDark(c) ? mutedDark : muted;
  static Color lineOf(BuildContext c) => isDark(c) ? lineDark : line;
  static Color accentTextOf(BuildContext c) => isDark(c) ? const Color(0xFF5FD3C4) : tealDark;

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFF3FBFB0) : teal,
      onPrimary: Colors.white,
      error: sos,
      surface: dark ? surfaceDark : surface,
    );
    final base = ThemeData(brightness: brightness, colorScheme: scheme, useMaterial3: true);
    final text = GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor: dark ? inkDark : ink,
      displayColor: dark ? inkDark : ink,
    );
    final radius = BorderRadius.circular(14);
    return base.copyWith(
      scaffoldBackgroundColor: dark ? bgDark : bg,
      cardColor: dark ? surfaceDark : surface,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? bgDark : bg,
        foregroundColor: dark ? inkDark : ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: dark ? inkDark : ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: dark ? surfaceDark : surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: dark ? const Color(0xFF3FBFB0) : teal,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark ? inkDark : ink,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: dark ? lineDark : line, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? fieldDark : field,
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        hintStyle: TextStyle(color: dark ? mutedDark : muted),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: dark ? surfaceDark : surface,
        side: BorderSide(color: dark ? lineDark : line),
        shape: const StadiumBorder(),
        labelStyle: GoogleFonts.manrope(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: dark ? inkDark : ink,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: dark ? surfaceDark : surface,
        selectedItemColor: dark ? const Color(0xFF3FBFB0) : teal,
        unselectedItemColor: dark ? mutedDark : muted,
        selectedLabelStyle: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    );
  }
}
