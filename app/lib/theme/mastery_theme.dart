// Mastery design tokens, sourced 1:1 from DESIGN.md.
// Composition reference: docs/design-mockups/.

import 'package:flutter/material.dart';

class MasteryColors {
  // Surfaces
  static const bgApp = Color(0xFFFCF8F6);
  static const bgSurface = Color(0xFFFFFDFC);
  static const bgSurfaceAlt = Color(0xFFF6EFEC);
  static const bgRaised = Color(0xFFFFFFFF);
  static const bgPrimarySoft = Color(0xFFF3E6E9);
  static const bgOnboardPanel = Color(0xFFE7D2D6);

  // Text
  static const textPrimary = Color(0xFF2B2326);
  static const textSecondary = Color(0xFF6A5A5E);
  static const textTertiary = Color(0xFF8E7E82);

  // Borders
  static const borderSoft = Color(0xFFE4D7D4);
  static const borderStrong = Color(0xFFD2C0BD);

  // Action — dusty rose
  static const actionPrimary = Color(0xFFB07A84);
  static const actionPrimaryHover = Color(0xFFA06B76);
  static const actionPrimaryPressed = Color(0xFF8F5C68);

  // Secondary — clay
  static const secondary = Color(0xFFC8A59A);

  // Accent gold (completion only)
  static const accentGold = Color(0xFFC89A52);
  static const accentGoldSoft = Color(0xFFF4E7CE);
  static const accentGoldDeep = Color(0xFF8B6A2A);

  // Semantic
  static const success = Color(0xFF4E7C68);
  static const successSoft = Color(0xFFE1ECDF);
  static const warning = Color(0xFFB68242);
  static const warningSoft = Color(0xFFF4E2CC);
  static const error = Color(0xFFB14C64);
  static const errorSoft = Color(0xFFF4D7DC);
  static const info = Color(0xFF5C7595);

  // Neutrals
  static const n50 = Color(0xFFFCF8F6);
  static const n100 = Color(0xFFF6EFEC);
  static const n200 = Color(0xFFE9DDDA);
  static const n300 = Color(0xFFD7C8C4);
  static const n500 = Color(0xFFAD9A97);
  static const n700 = Color(0xFF6A5A5E);
  static const n900 = Color(0xFF2B2326);
}

class MasterySpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 40.0;
  static const xxxl = 56.0;
  static const xxxxl = 72.0;
}

class MasteryRadii {
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 22.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

class MasteryDurations {
  static const micro = Duration(milliseconds: 90);
  static const short = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);
  static const long = Duration(milliseconds: 420);
}

class MasteryEasing {
  static const enter = Cubic(0.22, 1, 0.36, 1);
  static const exit = Cubic(0.55, 0, 1, 0.45);
  static const move = Cubic(0.4, 0, 0.2, 1);
}

class MasteryShadows {
  static const card = <BoxShadow>[
    BoxShadow(
        color: Color(0x05B07A84),
        offset: Offset(0, 6),
        blurRadius: 18),
    BoxShadow(
        color: Color(0x052B2326),
        offset: Offset(0, 1),
        blurRadius: 0),
  ];
  static const button = <BoxShadow>[
    BoxShadow(
        color: Color(0x29B07A84),
        offset: Offset(0, 6),
        blurRadius: 14),
    BoxShadow(
        color: Color(0x2D8F5C68),
        offset: Offset(0, 1),
        blurRadius: 0),
  ];
}

/// Custom tokens not covered by Material 3 ColorScheme.
@immutable
class MasteryTokens extends ThemeExtension<MasteryTokens> {
  final Color bgApp;
  final Color bgSurfaceAlt;
  final Color bgPrimarySoft;
  final Color bgOnboardPanel;
  final Color textTertiary;
  final Color borderSoft;
  final Color borderStrong;
  final Color actionPrimaryPressed;
  final Color accentGold;
  final Color accentGoldSoft;
  final Color accentGoldDeep;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color info;
  final List<BoxShadow> shadowCard;
  final List<BoxShadow> shadowButton;

  const MasteryTokens({
    required this.bgApp,
    required this.bgSurfaceAlt,
    required this.bgPrimarySoft,
    required this.bgOnboardPanel,
    required this.textTertiary,
    required this.borderSoft,
    required this.borderStrong,
    required this.actionPrimaryPressed,
    required this.accentGold,
    required this.accentGoldSoft,
    required this.accentGoldDeep,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.info,
    required this.shadowCard,
    required this.shadowButton,
  });

  static const light = MasteryTokens(
    bgApp: MasteryColors.bgApp,
    bgSurfaceAlt: MasteryColors.bgSurfaceAlt,
    bgPrimarySoft: MasteryColors.bgPrimarySoft,
    bgOnboardPanel: MasteryColors.bgOnboardPanel,
    textTertiary: MasteryColors.textTertiary,
    borderSoft: MasteryColors.borderSoft,
    borderStrong: MasteryColors.borderStrong,
    actionPrimaryPressed: MasteryColors.actionPrimaryPressed,
    accentGold: MasteryColors.accentGold,
    accentGoldSoft: MasteryColors.accentGoldSoft,
    accentGoldDeep: MasteryColors.accentGoldDeep,
    success: MasteryColors.success,
    successSoft: MasteryColors.successSoft,
    warning: MasteryColors.warning,
    warningSoft: MasteryColors.warningSoft,
    info: MasteryColors.info,
    shadowCard: MasteryShadows.card,
    shadowButton: MasteryShadows.button,
  );

  @override
  MasteryTokens copyWith({
    Color? bgApp,
    Color? bgSurfaceAlt,
    Color? bgPrimarySoft,
    Color? bgOnboardPanel,
    Color? textTertiary,
    Color? borderSoft,
    Color? borderStrong,
    Color? actionPrimaryPressed,
    Color? accentGold,
    Color? accentGoldSoft,
    Color? accentGoldDeep,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? info,
    List<BoxShadow>? shadowCard,
    List<BoxShadow>? shadowButton,
  }) {
    return MasteryTokens(
      bgApp: bgApp ?? this.bgApp,
      bgSurfaceAlt: bgSurfaceAlt ?? this.bgSurfaceAlt,
      bgPrimarySoft: bgPrimarySoft ?? this.bgPrimarySoft,
      bgOnboardPanel: bgOnboardPanel ?? this.bgOnboardPanel,
      textTertiary: textTertiary ?? this.textTertiary,
      borderSoft: borderSoft ?? this.borderSoft,
      borderStrong: borderStrong ?? this.borderStrong,
      actionPrimaryPressed: actionPrimaryPressed ?? this.actionPrimaryPressed,
      accentGold: accentGold ?? this.accentGold,
      accentGoldSoft: accentGoldSoft ?? this.accentGoldSoft,
      accentGoldDeep: accentGoldDeep ?? this.accentGoldDeep,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      info: info ?? this.info,
      shadowCard: shadowCard ?? this.shadowCard,
      shadowButton: shadowButton ?? this.shadowButton,
    );
  }

  @override
  MasteryTokens lerp(ThemeExtension<MasteryTokens>? other, double t) {
    if (other is! MasteryTokens) return this;
    return MasteryTokens(
      bgApp: Color.lerp(bgApp, other.bgApp, t)!,
      bgSurfaceAlt: Color.lerp(bgSurfaceAlt, other.bgSurfaceAlt, t)!,
      bgPrimarySoft: Color.lerp(bgPrimarySoft, other.bgPrimarySoft, t)!,
      bgOnboardPanel: Color.lerp(bgOnboardPanel, other.bgOnboardPanel, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      actionPrimaryPressed:
          Color.lerp(actionPrimaryPressed, other.actionPrimaryPressed, t)!,
      accentGold: Color.lerp(accentGold, other.accentGold, t)!,
      accentGoldSoft: Color.lerp(accentGoldSoft, other.accentGoldSoft, t)!,
      accentGoldDeep: Color.lerp(accentGoldDeep, other.accentGoldDeep, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      shadowCard: t < 0.5 ? shadowCard : other.shadowCard,
      shadowButton: t < 0.5 ? shadowButton : other.shadowButton,
    );
  }
}

extension MasteryThemeAccessor on ThemeData {
  MasteryTokens get masteryTokens =>
      extension<MasteryTokens>() ?? MasteryTokens.light;
}

extension MasteryBuildContextThemeAccessor on BuildContext {
  MasteryTokens get masteryTokens => Theme.of(this).masteryTokens;
}

/// Helper builder for a Fraunces display style with optical size axis tuned
/// for large display use.
TextStyle _fraunces({
  required double size,
  required double lineHeight,
  FontWeight weight = FontWeight.w600,
  FontStyle style = FontStyle.normal,
  Color color = MasteryColors.textPrimary,
  double letterSpacing = -0.018,
  double opticalSize = 144,
}) {
  return TextStyle(
    fontFamily: 'Fraunces',
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    fontStyle: style,
    color: color,
    letterSpacing: letterSpacing * size / 16, // approximate em
    fontVariations: [
      FontVariation('opsz', opticalSize),
      FontVariation('wght', weight.value.toDouble()),
    ],
  );
}

TextStyle _manrope({
  required double size,
  required double lineHeight,
  FontWeight weight = FontWeight.w500,
  Color color = MasteryColors.textPrimary,
  double letterSpacing = 0,
}) {
  return TextStyle(
    fontFamily: 'Manrope',
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
  );
}

class MasteryTextStyles {
  static TextStyle get displayXl =>
      _fraunces(size: 56, lineHeight: 60, weight: FontWeight.w600);
  static TextStyle get displayLg =>
      _fraunces(size: 48, lineHeight: 52, weight: FontWeight.w600);
  static TextStyle get displayMd =>
      _fraunces(size: 40, lineHeight: 46, weight: FontWeight.w600);
  static TextStyle get headlineLg =>
      _fraunces(size: 32, lineHeight: 38, weight: FontWeight.w600);
  static TextStyle get headlineMd => _manrope(
        size: 28,
        lineHeight: 34,
        weight: FontWeight.w700,
        letterSpacing: -0.2,
      );
  static TextStyle get titleLg => _manrope(
      size: 24, lineHeight: 30, weight: FontWeight.w700, letterSpacing: -0.1);
  static TextStyle get titleMd => _manrope(
      size: 20, lineHeight: 26, weight: FontWeight.w700, letterSpacing: -0.05);
  static TextStyle get titleSm => _manrope(
      size: 18,
      lineHeight: 24,
      weight: FontWeight.w700,
      letterSpacing: 0.05);
  // Body styles carry positive letter-spacing on mobile so the
  // Manrope glyphs do not visually fuse — the user-reported
  // "letters blend together" issue on phones (2026-05-01).
  static TextStyle get bodyLg => _manrope(
      size: 18,
      lineHeight: 30,
      weight: FontWeight.w500,
      letterSpacing: 0.1);
  static TextStyle get bodyMd => _manrope(
      size: 16,
      lineHeight: 26,
      weight: FontWeight.w500,
      letterSpacing: 0.15);
  static TextStyle get bodySm => _manrope(
      size: 15,
      lineHeight: 24,
      weight: FontWeight.w500,
      letterSpacing: 0.2);
  static TextStyle get labelLg =>
      _manrope(size: 16, lineHeight: 20, weight: FontWeight.w700);
  static TextStyle get labelMd => _manrope(
      size: 14, lineHeight: 18, weight: FontWeight.w700, letterSpacing: 0.4);
  static TextStyle get labelSm => _manrope(
      size: 13, lineHeight: 16, weight: FontWeight.w700, letterSpacing: 0.6);

  /// Editorial display with italic styling (used for Mastery wordmark).
  static TextStyle displayItalic({
    required double size,
    required double lineHeight,
    Color color = MasteryColors.actionPrimaryPressed,
  }) =>
      _fraunces(
        size: size,
        lineHeight: lineHeight,
        weight: FontWeight.w600,
        style: FontStyle.italic,
        color: color,
        letterSpacing: -0.025,
      );

  /// Tabular numerals for fractions / progress counters.
  static TextStyle mono({
    double size = 14,
    double lineHeight = 18,
    FontWeight weight = FontWeight.w400,
    Color color = MasteryColors.textSecondary,
    double letterSpacing = 0.5,
  }) =>
      TextStyle(
        fontFamily: 'IBMPlexMono',
        fontSize: size,
        height: lineHeight / size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// All-caps eyebrow label used above section titles.
  static TextStyle eyebrow({
    Color color = MasteryColors.actionPrimary,
  }) =>
      _manrope(
        size: 12,
        lineHeight: 16,
        weight: FontWeight.w700,
        color: color,
        letterSpacing: 1.6,
      );
}

/// Full Mastery [ThemeData] configured per DESIGN.md.
class MasteryTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: MasteryColors.actionPrimary,
      onPrimary: MasteryColors.bgSurface,
      primaryContainer: MasteryColors.bgPrimarySoft,
      onPrimaryContainer: MasteryColors.actionPrimaryPressed,
      secondary: MasteryColors.secondary,
      onSecondary: MasteryColors.textPrimary,
      secondaryContainer: MasteryColors.warningSoft,
      onSecondaryContainer: MasteryColors.accentGoldDeep,
      tertiary: MasteryColors.accentGold,
      onTertiary: MasteryColors.textPrimary,
      tertiaryContainer: MasteryColors.accentGoldSoft,
      onTertiaryContainer: MasteryColors.accentGoldDeep,
      error: MasteryColors.error,
      onError: MasteryColors.bgSurface,
      errorContainer: MasteryColors.errorSoft,
      onErrorContainer: Color(0xFF8E2A40),
      surface: MasteryColors.bgSurface,
      onSurface: MasteryColors.textPrimary,
      onSurfaceVariant: MasteryColors.textSecondary,
      surfaceContainerLowest: MasteryColors.bgApp,
      surfaceContainerLow: MasteryColors.bgSurface,
      surfaceContainer: MasteryColors.bgSurface,
      surfaceContainerHigh: MasteryColors.bgRaised,
      surfaceContainerHighest: MasteryColors.bgSurfaceAlt,
      outline: MasteryColors.borderStrong,
      outlineVariant: MasteryColors.borderSoft,
      shadow: Color(0x402B2326),
      scrim: Color(0x802B2326),
      inverseSurface: MasteryColors.textPrimary,
      onInverseSurface: MasteryColors.bgSurface,
      inversePrimary: MasteryColors.bgPrimarySoft,
    );

    final textTheme = TextTheme(
      displayLarge: MasteryTextStyles.displayXl,
      displayMedium: MasteryTextStyles.displayLg,
      displaySmall: MasteryTextStyles.displayMd,
      headlineLarge: MasteryTextStyles.headlineLg,
      headlineMedium: MasteryTextStyles.headlineMd,
      headlineSmall: MasteryTextStyles.titleLg,
      titleLarge: MasteryTextStyles.titleLg,
      titleMedium: MasteryTextStyles.titleMd,
      titleSmall: MasteryTextStyles.titleSm,
      bodyLarge: MasteryTextStyles.bodyLg,
      bodyMedium: MasteryTextStyles.bodyMd,
      bodySmall: MasteryTextStyles.bodySm,
      labelLarge: MasteryTextStyles.labelLg,
      labelMedium: MasteryTextStyles.labelMd,
      labelSmall: MasteryTextStyles.labelSm,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: MasteryColors.bgApp,
      canvasColor: MasteryColors.bgApp,
      fontFamily: 'Manrope',
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: MasteryColors.bgApp,
        foregroundColor: MasteryColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: MasteryTextStyles.titleSm.copyWith(
          color: MasteryColors.textPrimary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MasteryColors.actionPrimary,
          foregroundColor: MasteryColors.bgSurface,
          disabledBackgroundColor: MasteryColors.borderStrong,
          disabledForegroundColor: MasteryColors.textTertiary,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
          textStyle: MasteryTextStyles.labelLg,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.pressed)) {
              return MasteryColors.actionPrimaryPressed.withAlpha(40);
            }
            if (states.contains(WidgetState.hovered)) {
              return MasteryColors.actionPrimaryHover.withAlpha(20);
            }
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MasteryColors.textPrimary,
          minimumSize: const Size.fromHeight(56),
          side: const BorderSide(color: MasteryColors.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: MasteryTextStyles.labelLg,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MasteryColors.actionPrimary,
          textStyle: MasteryTextStyles.labelMd,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
      // We don't theme Material's Card widget directly — every screen uses
      // MasteryCard (custom Container). Skipping the cardTheme override keeps
      // the file portable across Flutter 3.22 (Render) and 3.41 (local), where
      // the field type was renamed CardTheme → CardThemeData.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MasteryColors.bgSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: MasteryTextStyles.bodyMd.copyWith(
          color: MasteryColors.textTertiary,
        ),
        labelStyle: MasteryTextStyles.labelMd.copyWith(
          color: MasteryColors.textSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MasteryRadii.md),
          borderSide: const BorderSide(color: MasteryColors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MasteryRadii.md),
          borderSide: const BorderSide(color: MasteryColors.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MasteryRadii.md),
          borderSide: const BorderSide(
              color: MasteryColors.actionPrimary, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MasteryRadii.md),
          borderSide: const BorderSide(color: MasteryColors.borderSoft),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MasteryColors.actionPrimary,
        linearTrackColor: MasteryColors.bgSurfaceAlt,
        circularTrackColor: MasteryColors.bgSurfaceAlt,
      ),
      dividerTheme: const DividerThemeData(
        color: MasteryColors.borderSoft,
        space: 1,
        thickness: 1,
      ),
      iconTheme: const IconThemeData(
        color: MasteryColors.textPrimary,
        size: 22,
      ),
      extensions: const [MasteryTokens.light],
    );
  }
}
