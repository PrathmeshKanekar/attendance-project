import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_tokens.dart';
import '../constants/app_typography.dart';

export '../constants/app_colors.dart';
export '../constants/app_tokens.dart';
export '../constants/app_typography.dart';


/// Smart Campus ERP — Unified Theme
/// Usage:
///   MaterialApp(
///     theme:      AppTheme.light,
///     darkTheme:  AppTheme.dark,
///     themeMode:  ThemeMode.system,
///   )
abstract final class AppTheme {
  AppTheme._();

  // ─── Light Theme ─────────────────────────────────────────────────────────────
  static ThemeData get light => _build(Brightness.light);

  // ─── Dark Theme ──────────────────────────────────────────────────────────────
  static ThemeData get dark => _build(Brightness.dark);

  // ─── Builder ─────────────────────────────────────────────────────────────────
  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = isDark ? _darkScheme : _lightScheme;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: 'Outfit',
      scaffoldBackgroundColor: colorScheme.surface,
      splashFactory: InkRipple.splashFactory,

      // ── AppBar ───────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        elevation: AppElevation.none,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: AppTypography.titleLarge.copyWith(
          color: colorScheme.onSurface,
        ),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        shadowColor: isDark
            ? AppColors.darkBorder.withOpacity(0.4)
            : AppColors.slate200.withOpacity(0.6),
      ),

      // ── Card ─────────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: AppElevation.none,
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.roundedLg,
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.slate200,
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      // ── Divider ──────────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkBorder : AppColors.slate200,
        thickness: 1,
        space: 1,
      ),

      // ── Input Decoration ─────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AppColors.darkCard.withOpacity(0.6)
            : AppColors.slate50,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.roundedMd,
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.slate200,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.roundedMd,
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.slate200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.roundedMd,
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.roundedMd,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.roundedMd,
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.roundedMd,
          borderSide: BorderSide(
            color: isDark
                ? AppColors.darkBorder.withOpacity(0.5)
                : AppColors.slate200.withOpacity(0.5),
          ),
        ),
        labelStyle: AppTypography.bodyMedium.copyWith(
          color: isDark ? AppColors.slate400 : AppColors.slate600,
        ),
        hintStyle: AppTypography.bodyMedium.copyWith(
          color: isDark ? AppColors.slate600 : AppColors.slate400,
        ),
        errorStyle: AppTypography.labelSmall.copyWith(
          color: colorScheme.error,
        ),
        floatingLabelStyle: AppTypography.labelMedium.copyWith(
          color: colorScheme.primary,
        ),
      ),

      // ── Elevated Button ───────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: AppElevation.none,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: isDark
              ? AppColors.darkBorder
              : AppColors.slate200,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.roundedMd,
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      // ── Outlined Button ───────────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.roundedMd,
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      // ── Text Button ───────────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.sm,
          ),
          minimumSize: const Size(48, 40),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.roundedSm,
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      // ── Icon Button ───────────────────────────────────────────────────────────
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(AppSpacing.sm),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.roundedSm,
          ),
        ),
      ),

      // ── Chip ─────────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.darkCard : AppColors.slate100,
        selectedColor: colorScheme.primaryContainer,
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.slate200,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.roundedPill,
        ),
        labelStyle: AppTypography.labelMedium,
        padding: AppSpacing.chipInset,
      ),

      // ── Drawer ───────────────────────────────────────────────────────────────
      drawerTheme: DrawerThemeData(
        backgroundColor: isDark ? AppColors.darkCard : AppColors.white,
        elevation: AppElevation.none,
        shadowColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(AppRadius.xl),
            bottomRight: Radius.circular(AppRadius.xl),
          ),
        ),
        width: AppSpacing.drawerWidth,
      ),

      // ── List Tile ─────────────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: AppSpacing.drawerItemInset,
        minLeadingWidth: 24,
        iconColor: isDark ? AppColors.slate400 : AppColors.slate600,
        textColor: isDark ? AppColors.slate200 : AppColors.slate700,
        titleTextStyle: AppTypography.drawerItem,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.roundedMd,
        ),
      ),

      // ── NavigationBar (bottom) ────────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        elevation: AppElevation.none,
        height: AppSpacing.bottomNavHeight,
        backgroundColor: isDark ? AppColors.darkCard : AppColors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: AppRadius.roundedMd,
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return AppTypography.labelSmall.copyWith(
            color: isSelected
                ? colorScheme.primary
                : (isDark ? AppColors.slate400 : AppColors.slate500),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: isSelected
                ? colorScheme.primary
                : (isDark ? AppColors.slate400 : AppColors.slate500),
          );
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      // ── NavigationRail (tablet sidebar) ──────────────────────────────────────
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? AppColors.darkCard : AppColors.white,
        elevation: AppElevation.none,
        indicatorColor: colorScheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: AppRadius.roundedMd,
        ),
        selectedIconTheme: IconThemeData(
          color: colorScheme.primary,
          size: 22,
        ),
        unselectedIconTheme: IconThemeData(
          color: isDark ? AppColors.slate400 : AppColors.slate500,
          size: 22,
        ),
        selectedLabelTextStyle: AppTypography.labelSmall.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: AppTypography.labelSmall.copyWith(
          color: isDark ? AppColors.slate400 : AppColors.slate500,
        ),
        groupAlignment: -1,
        useIndicator: true,
        minWidth: AppSpacing.sidebarCollapse,
        minExtendedWidth: AppSpacing.sidebarWidth,
      ),

      // ── Snack Bar ─────────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.slate700 : AppColors.slate900,
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.slate50,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.roundedMd,
        ),
        elevation: AppElevation.high,
      ),

      // ── Dialog ───────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        elevation: AppElevation.modal,
        backgroundColor: isDark ? AppColors.darkCard : AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.roundedXl,
        ),
        titleTextStyle: AppTypography.titleLarge.copyWith(
          color: isDark ? AppColors.slate50 : AppColors.slate900,
        ),
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: isDark ? AppColors.slate300 : AppColors.slate600,
        ),
      ),

      // ── Bottom Sheet ─────────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.darkCard : AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.modal,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft:  Radius.circular(AppRadius.x2l),
            topRight: Radius.circular(AppRadius.x2l),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: isDark ? AppColors.slate600 : AppColors.slate300,
      ),

      // ── Tab Bar ───────────────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: isDark ? AppColors.slate400 : AppColors.slate500,
        labelStyle: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppTypography.labelLarge,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
          borderRadius: AppRadius.roundedPill,
        ),
        dividerColor: isDark ? AppColors.darkBorder : AppColors.slate200,
        overlayColor: WidgetStateProperty.all(
          colorScheme.primary.withOpacity(0.08),
        ),
      ),

      // ── Progress Indicator ────────────────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: colorScheme.primaryContainer,
        linearTrackColor: colorScheme.primaryContainer,
        borderRadius: AppRadius.roundedPill,
      ),

      // ── Text Theme ────────────────────────────────────────────────────────────
      textTheme: TextTheme(
        displayLarge:  AppTypography.displayLarge,
        displayMedium: AppTypography.displayMedium,
        displaySmall:  AppTypography.displaySmall,
        headlineLarge:  AppTypography.headlineLarge,
        headlineMedium: AppTypography.headlineMedium,
        headlineSmall:  AppTypography.headlineSmall,
        titleLarge:  AppTypography.titleLarge,
        titleMedium: AppTypography.titleMedium,
        titleSmall:  AppTypography.titleSmall,
        bodyLarge:  AppTypography.bodyLarge,
        bodyMedium: AppTypography.bodyMedium,
        bodySmall:  AppTypography.bodySmall,
        labelLarge:  AppTypography.labelLarge,
        labelMedium: AppTypography.labelMedium,
        labelSmall:  AppTypography.labelSmall,
      ).apply(
        bodyColor:    isDark ? AppColors.slate100 : AppColors.slate800,
        displayColor: isDark ? AppColors.slate50  : AppColors.slate900,
      ),
    );
  }

  // ─── Color Schemes ───────────────────────────────────────────────────────────

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary:          AppColors.primary600,
    onPrimary:        AppColors.white,
    primaryContainer: AppColors.primary100,
    onPrimaryContainer: AppColors.primary900,
    secondary:          AppColors.slate600,
    onSecondary:        AppColors.white,
    secondaryContainer: AppColors.slate100,
    onSecondaryContainer: AppColors.slate900,
    tertiary:           AppColors.glowPurple,
    onTertiary:         AppColors.white,
    tertiaryContainer:  Color(0xFFEDE9FE),
    onTertiaryContainer: Color(0xFF3B0764),
    error:              AppColors.error500,
    onError:            AppColors.white,
    errorContainer:     AppColors.error50,
    onErrorContainer:   AppColors.error600,
    surface:            AppColors.slate50,
    onSurface:          AppColors.slate900,
    surfaceContainerLow:     AppColors.white,
    surfaceContainerHighest: AppColors.slate100,
    outline:            AppColors.slate300,
    outlineVariant:     AppColors.slate200,
    inverseSurface:     AppColors.slate900,
    onInverseSurface:   AppColors.slate50,
    inversePrimary:     AppColors.primary400,
    scrim:              Color(0x66000000),
    shadow:             Color(0x1A0F172A),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary:          AppColors.primary400,
    onPrimary:        AppColors.primary900,
    primaryContainer: AppColors.primary700,
    onPrimaryContainer: AppColors.primary100,
    secondary:          AppColors.slate400,
    onSecondary:        AppColors.slate900,
    secondaryContainer: AppColors.slate700,
    onSecondaryContainer: AppColors.slate100,
    tertiary:           Color(0xFFA78BFA),
    onTertiary:         Color(0xFF2E1065),
    tertiaryContainer:  Color(0xFF4C1D95),
    onTertiaryContainer: Color(0xFFEDE9FE),
    error:              AppColors.error400,
    onError:            AppColors.error600,
    errorContainer:     Color(0xFF7F1D1D),
    onErrorContainer:   AppColors.error50,
    surface:            AppColors.darkScaffold,
    onSurface:          AppColors.slate50,
    surfaceContainerLow:     AppColors.darkCard,
    surfaceContainerHighest: AppColors.darkCardAlt,
    outline:            AppColors.slate600,
    outlineVariant:     AppColors.darkBorder,
    inverseSurface:     AppColors.slate100,
    onInverseSurface:   AppColors.slate900,
    inversePrimary:     AppColors.primary600,
    scrim:              Color(0x99000000),
    shadow:             Color(0x66000000),
  );
}