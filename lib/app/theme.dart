import 'package:flutter/material.dart';

/// Design tokens from the light wireframes (Thekedaar Wireframes canvas).
/// Bright fills are never used for text on white (PRD I-D1); amber always
/// carries dark text (I-D2).
abstract final class AppColors {
  // Ink and text
  static const ink = Color(0xFF15181D);
  static const inkSoft = Color(0xFF3A414B); // form labels, chip text
  static const muted = Color(0xFF5B6370); // secondary text
  static const faint = Color(0xFF8A919C); // placeholders, disabled text

  // Surfaces and lines
  static const page = Color(0xFFF4F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE3E6EA);
  static const divider = Color(0xFFEEF0F2);
  static const inputBorder = Color(0xFFC9CED6);
  static const track = Color(0xFFE9ECEF); // avatars, segmented track

  // Primary (blue) and accent (amber)
  static const primary = Color(0xFF0369A1);
  static const primaryPressed = Color(0xFF075985);
  static const primaryTint = Color(0xFFE0F2FE); // tab indicator
  static const primarySurface = Color(0xFFF0F9FF); // selected option
  static const amber500 = Color(0xFFF59E0B);
  static const amberLogo = Color(0xFFFBBF24);
  static const amber100 = Color(0xFFFEF3C7);

  // Status
  static const successFill = Color(0xFF059669);
  static const successText = Color(0xFF047857);
  static const successSurface = Color(0xFFECFDF5);
  static const warningFill = Color(0xFFD97706);
  static const warningText = Color(0xFFB45309);
  static const warningSurface = Color(0xFFFFFBEB);
  static const dangerFill = Color(0xFFE11D48);
  static const dangerText = Color(0xFFBE123C);
  static const dangerSurface = Color(0xFFFFF1F2);

  // Older names, kept so existing screens keep compiling while they move
  // to the names above.
  static const slate900 = ink;
  static const slate600 = muted;
  static const blue600 = Color(0xFF0284C7);
  static const blue700 = primary;
  static const surface2 = page;
}

abstract final class AppSizes {
  static const double tapMin = 48;
  static const double tapPrimary = 56; // main button
  static const double tapSecondary = 52; // outlined button, input
  static const double iconButton = 44;
  static const double chip = 34;
  static const double row = 56;
  static const double pinKey = 64;
  static const double gap = 8;
  static const double radius = 12;
  static const double gutter = 16;
  static const double gutterWide = 20; // onboarding and PIN screens
}

abstract final class AppRadius {
  static const double badge = 8;
  static const double small = 12; // small buttons, segmented track
  static const double input = 14; // inputs, icon tiles
  static const double card = 16; // cards, main buttons, keypad keys
  static const double tile = 18; // option tiles, FAB
  static const double sheet = 24;
}

abstract final class AppText {
  static const fontFamily = 'Manrope';

  /// Manrope has no Devanagari; Hindi falls back to Noto.
  static const fallback = ['NotoSansDevanagari'];

  /// Money and counts: digits line up in columns.
  static const amount = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.48,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const tabular = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primaryTint,
    onPrimaryContainer: AppColors.primaryPressed,
    secondary: AppColors.amber500,
    onSecondary: AppColors.ink,
    error: AppColors.dangerText,
    onError: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    surfaceContainerHighest: AppColors.page,
    outline: AppColors.inputBorder,
    outlineVariant: AppColors.border,
  );

  RoundedRectangleBorder rounded(double radius, [BorderSide? side]) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: side ?? BorderSide.none,
      );

  const textTheme = TextTheme(
    headlineMedium: TextStyle(
        fontSize: 30, height: 1.15, fontWeight: FontWeight.w800,
        letterSpacing: -0.6),
    headlineSmall: TextStyle(
        fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.52),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    titleSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    bodySmall: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
    labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
  );

  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppText.fontFamily,
    fontFamilyFallback: AppText.fallback,
    // Merged over the default typography, which already uses onSurface (ink).
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.page,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.page,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      leadingWidth: 68,
      titleSpacing: 4,
      titleTextStyle: TextStyle(
        fontFamily: AppText.fontFamily,
        fontFamilyFallback: AppText.fallback,
        color: AppColors.ink,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.22,
      ),
    ),
    // Back and menu buttons are 44px white circles with a hairline border.
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) =>
          const _RoundIcon(Icons.arrow_back),
      closeButtonIconBuilder: (context) => const _RoundIcon(Icons.close),
      drawerButtonIconBuilder: (context) => const _RoundIcon(Icons.menu),
    ),
    // White cards with a hairline border on the grey page; no shadow.
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: rounded(
          AppRadius.card, const BorderSide(color: AppColors.border)),
    ),
    // Lists sit on the grey page as white rows.
    listTileTheme: const ListTileThemeData(
      tileColor: AppColors.surface,
      iconColor: AppColors.muted,
      minTileHeight: AppSizes.row,
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(),
      titleTextStyle: TextStyle(
        fontFamily: AppText.fontFamily,
        fontFamilyFallback: AppText.fallback,
        color: AppColors.ink,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: AppText.fontFamily,
        fontFamilyFallback: AppText.fallback,
        color: AppColors.muted,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      selectedTileColor: AppColors.primarySurface,
      selectedColor: AppColors.primary,
    ),
    dividerTheme:
        const DividerThemeData(color: AppColors.divider, space: 1),
    // Filter chips: white with a border; selected is solid ink.
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.ink,
      checkmarkColor: Colors.white,
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected)
              ? AppColors.ink
              : AppColors.border,
        ),
      ),
      shape: const StadiumBorder(),
      labelStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          fontFamily: AppText.fontFamily,
          fontFamilyFallback: AppText.fallback,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.inkSoft,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    // Segmented: grey track, the selected segment is white.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.track,
        foregroundColor: AppColors.muted,
        selectedBackgroundColor: AppColors.surface,
        selectedForegroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.track, width: 2),
        shape: rounded(AppRadius.small),
        minimumSize: const Size(0, 40),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    // Underlined tabs: the selected one is ink with an ink line.
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.ink,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.ink,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.border,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      unselectedLabelStyle:
          TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: AppColors.surface),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: rounded(20),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: rounded(AppRadius.small),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.primary),
    // Main action: blue with white text.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.faint,
        minimumSize: const Size(64, AppSizes.tapPrimary),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        shape: rounded(AppRadius.card),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface,
        minimumSize: const Size(64, AppSizes.tapMin),
        side: const BorderSide(color: AppColors.border),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: rounded(AppRadius.card),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 4,
      highlightElevation: 6,
      shape: rounded(AppRadius.tile),
      extendedTextStyle: const TextStyle(
        fontFamily: AppText.fontFamily,
        fontFamilyFallback: AppText.fallback,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    ),
    checkboxTheme: CheckboxThemeData(shape: rounded(6)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      hintStyle: const TextStyle(color: AppColors.faint),
      labelStyle: const TextStyle(
          color: AppColors.inkSoft, fontWeight: FontWeight.w600),
      border: inputBorder(AppColors.inputBorder),
      enabledBorder: inputBorder(AppColors.inputBorder),
      focusedBorder: inputBorder(AppColors.primary, 2),
      errorBorder: inputBorder(AppColors.dangerText),
      focusedErrorBorder: inputBorder(AppColors.dangerText, 2),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primaryTint,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: AppText.fontFamily,
          fontFamilyFallback: AppText.fallback,
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.muted,
        ),
      ),
    ),
  );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSizes.iconButton,
      height: AppSizes.iconButton,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(icon, size: 22, color: AppColors.ink),
    );
  }
}
