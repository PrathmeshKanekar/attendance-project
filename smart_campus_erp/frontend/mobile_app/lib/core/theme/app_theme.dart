import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF1E3A5F);
  static const primaryLight = Color(0xFF2563EB);
  static const accent = Color(0xFF0EA5E9);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFEA580C);
  static const danger = Color(0xFFDC2626);
  static const bgPrimary = Color(0xFFF8FAFC);
  static const bgSecondary = Color(0xFFF1F5F9);
  static const cardBg = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const borderColor = Color(0xFFE2E8F0);
}

ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  fontFamily: GoogleFonts.poppins().fontFamily,
  scaffoldBackgroundColor: AppColors.bgPrimary,
  cardTheme: CardThemeData(
    elevation: 0,
    color: AppColors.cardBg,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.borderColor),
    ),
    margin: EdgeInsets.zero,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primaryLight,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.bgSecondary,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryLight, width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: AppColors.cardBg,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    titleTextStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 18, color: AppColors.textPrimary),
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    systemOverlayStyle: SystemUiOverlayStyle.dark,
  ),
  chipTheme: ChipThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  ),
  dividerTheme: const DividerThemeData(color: AppColors.borderColor, thickness: 1),
);
