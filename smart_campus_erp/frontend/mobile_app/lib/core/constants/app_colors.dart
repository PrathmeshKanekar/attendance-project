import 'package:flutter/material.dart';

/// Smart Campus ERP — Unified Color Palette
/// Single source of truth. Never use Color() outside this file.
/// All values derived from the Phase 2 design system specification.
abstract final class AppColors {
  AppColors._();

  // ─── Slate Scale ────────────────────────────────────────────────────────────
  static const slate50  = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF374151);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);

  // ─── Dark Mode Surfaces ──────────────────────────────────────────────────────
  static const darkScaffold = Color(0xFF090D16); // premium midnight
  static const darkCard     = Color(0xFF1F2937); // rich dark grey
  static const darkCardAlt  = Color(0xFF111827); // deeper card surface
  static const darkBorder   = Color(0xFF374151); // slate 700

  // ─── Brand / Primary ─────────────────────────────────────────────────────────
  static const primary50  = Color(0xFFEFF6FF);
  static const primary100 = Color(0xFFDBEAFE);
  static const primary400 = Color(0xFF60A5FA);
  static const primary500 = Color(0xFF3B82F6);
  static const primary600 = Color(0xFF2563EB);
  static const primary700 = Color(0xFF1D4ED8);
  static const primary900 = Color(0xFF1E3A8A);

  // ─── Semantic ────────────────────────────────────────────────────────────────
  static const success50  = Color(0xFFF0FDF4);
  static const success400 = Color(0xFF4ADE80);
  static const success500 = Color(0xFF22C55E);
  static const success600 = Color(0xFF16A34A);
  static const success700 = Color(0xFF15803D);

  // ─── Warning ─────────────────────────────────────────────────────────────────
  static const warning50  = Color(0xFFFFFBEB);
  static const warning400 = Color(0xFFFBBF24);
  static const warning500 = Color(0xFFF59E0B);
  static const warning600 = Color(0xFFD97706);

  // ─── Error ───────────────────────────────────────────────────────────────────
  static const error50    = Color(0xFFFEF2F2);
  static const error400   = Color(0xFFF87171);
  static const error500   = Color(0xFFEF4444);
  static const error600   = Color(0xFFDC2626);

  // ─── Info ────────────────────────────────────────────────────────────────────
  static const info50     = Color(0xFFEFF6FF);
  static const info500    = Color(0xFF3B82F6);
  static const info600    = Color(0xFF2563EB);

  // ─── Transparent Overlays ────────────────────────────────────────────────────
  static const white        = Color(0xFFFFFFFF);
  static const black        = Color(0xFF000000);
  static const transparent  = Colors.transparent;

  static Color overlay04  = Colors.black.withOpacity(0.04);
  static Color overlay08  = Colors.black.withOpacity(0.08);
  static Color overlay12  = Colors.black.withOpacity(0.12);
  static Color overlay24  = Colors.black.withOpacity(0.24);

  // ─── Glow Accents (StatCard strips) ─────────────────────────────────────────
  static const glowBlue   = Color(0xFF3B82F6);
  static const glowGreen  = Color(0xFF22C55E);
  static const glowAmber  = Color(0xFFF59E0B);
  static const glowPurple = Color(0xFF8B5CF6);
  static const glowRose   = Color(0xFFF43F5E);
  static const glowTeal   = Color(0xFF14B8A6);

  // ─── Backward Legacy Mappings for Seamless Compilation ───────────────────────
  static const Color primary            = slate900;
  static const Color primaryLight       = primary600;
  static const Color accent             = primary500;
  static const Color success            = success500;
  static const Color warning            = warning500;
  static const Color danger             = error500;
  static const Color info               = info500;

  static const Color bgPrimary          = slate50;
  static const Color bgSecondary        = slate100;
  static const Color cardBg             = white;
  static const Color textPrimary        = slate900;
  static const Color textSecondary      = slate600;
  static const Color borderColor        = slate200;

  static const Color darkBgPrimary      = darkScaffold;
  static const Color darkBgSecondary    = darkCardAlt;
  static const Color darkCardBg         = darkCard;
  static const Color darkTextPrimary    = slate50;
  static const Color darkTextSecondary  = slate400;
  static const Color darkBorderColor    = darkBorder;

  static const Color sidebarBg          = slate900;
  static const Color sidebarActive      = primary600;
  static const Color dark               = slate900;
}