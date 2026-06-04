import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Smart Campus ERP — Design Tokens
/// Spacing, border radius, elevation, and box shadow system.
/// Import this wherever layout decisions are needed.
abstract final class AppSpacing {
  AppSpacing._();

  // ─── Spacing Scale (4-base) ───────────────────────────────────────────────
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 12;
  static const double base = 16;
  static const double lg   = 20;
  static const double xl   = 24;
  static const double x2l  = 32;
  static const double x3l  = 40;
  static const double x4l  = 48;
  static const double x5l  = 64;

  // ─── Semantic Aliases ────────────────────────────────────────────────────────
  static const double cardPadding     = base;
  static const double cardPaddingH    = xl;
  static const double sectionGap      = x2l;
  static const double fieldGap        = base;
  static const double iconSize        = 20;
  static const double iconSizeLg      = 24;
  static const double drawerWidth     = 260;
  static const double sidebarWidth    = 240;
  static const double sidebarCollapse = 64;
  static const double topBarHeight    = 64;
  static const double bottomNavHeight = 64;

  // ─── Edge Insets ─────────────────────────────────────────────────────────────
  static const EdgeInsets pagePadding     = EdgeInsets.all(base);
  static const EdgeInsets pagePaddingLg   = EdgeInsets.all(xl);
  static const EdgeInsets cardInsets      = EdgeInsets.symmetric(horizontal: xl, vertical: base);
  static const EdgeInsets drawerItemInset = EdgeInsets.symmetric(horizontal: md, vertical: xs + 2);
  static const EdgeInsets chipInset       = EdgeInsets.symmetric(horizontal: md, vertical: xs);
}

abstract final class AppRadius {
  AppRadius._();

  static const double none = 0;
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 12;
  static const double lg   = 16;
  static const double xl   = 20;
  static const double x2l  = 24;
  static const double pill = 999;

  static const BorderRadius roundedXs  = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius roundedSm  = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius roundedMd  = BorderRadius.all(Radius.circular(md));
  static const BorderRadius roundedLg  = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius roundedXl  = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius roundedX2l = BorderRadius.all(Radius.circular(x2l));
  static const BorderRadius roundedPill = BorderRadius.all(Radius.circular(pill));

  // Left-accent strip (stat cards)
  static const BorderRadius leftStrip = BorderRadius.only(
    topLeft:    Radius.circular(lg),
    bottomLeft: Radius.circular(lg),
  );
}

abstract final class AppElevation {
  AppElevation._();

  static const double none    = 0;
  static const double low     = 1;
  static const double medium  = 2;
  static const double high    = 4;
  static const double overlay = 8;
  static const double modal   = 16;
}

abstract final class AppShadows {
  AppShadows._();

  /// Subtle card shadow — light mode
  static const List<BoxShadow> cardLight = [
    BoxShadow(
      color: Color(0x0A0F172A),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x060F172A),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// Card shadow — dark mode
  static const List<BoxShadow> cardDark = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// Drawer / sidebar shadow
  static const List<BoxShadow> drawer = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 24,
      offset: Offset(4, 0),
    ),
  ];

  /// Modal / dialog
  static const List<BoxShadow> modal = [
    BoxShadow(
      color: Color(0x29000000),
      blurRadius: 40,
      offset: Offset(0, 16),
    ),
  ];

  /// Glow accent — used on stat card icon backgrounds
  static List<BoxShadow> glow(Color color) => [
    BoxShadow(
      color: color.withOpacity(0.25),
      blurRadius: 16,
      offset: Offset.zero,
      spreadRadius: 2,
    ),
  ];
}