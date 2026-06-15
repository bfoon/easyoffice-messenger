import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// EasyOffice Messenger design system.
///
/// Palette: deep institutional teal for trust, a brighter signal teal for the
/// user's own messages and accents, warm sand for the canvas (West-African
/// daylight rather than a cold white), ink for text, coral for presence/alerts.
class EoColors {
  static const deepTeal = Color(0xFF0B5563);
  static const signalTeal = Color(0xFF13A0A0);
  static const sand = Color(0xFFF4EFE6);
  static const sandDeep = Color(0xFFEAE2D3);
  static const ink = Color(0xFF16242A);
  static const inkSoft = Color(0xFF55636A);
  static const coral = Color(0xFFE8615A);
  static const surface = Color(0xFFFFFFFF);
  static const onTeal = Color(0xFFF4FBFB);
  static const divider = Color(0x1416242A);
}

class EoTheme {
  static ThemeData build() {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: EoColors.ink,
      displayColor: EoColors.ink,
    );

    return base.copyWith(
      scaffoldBackgroundColor: EoColors.sand,
      colorScheme: base.colorScheme.copyWith(
        primary: EoColors.deepTeal,
        secondary: EoColors.signalTeal,
        surface: EoColors.surface,
        error: EoColors.coral,
        onPrimary: EoColors.onTeal,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: EoColors.sand,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: EoColors.ink),
        titleTextStyle: GoogleFonts.sora(
          color: EoColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerColor: EoColors.divider,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: EoColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: EoColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: EoColors.signalTeal, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: EoColors.deepTeal,
          foregroundColor: EoColors.onTeal,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
    );
  }

  static TextStyle display(double size, {FontWeight w = FontWeight.w700, Color? color}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color ?? EoColors.ink);
}
