import 'package:flutter/material.dart';

/// Shared brand colors only. Layout/typography are intentionally separated
/// between the Persian and English UI systems.
abstract final class VelixeoBrand {
  static const sky = Color(0xFF38BDF8);
  static const skyHover = Color(0xFF7DD3FC);
  static const ink = Color(0xFF24343D);
  static const muted = Color(0xFF74818B);
  static const soft = Color(0xFFEDF8FD);
  static const background = Color(0xFFF6F9FC);
  static const line = Color(0xFFE7EEF2);
  static const green = Color(0xFF158365);
  static const orange = Color(0xFFAD670D);
  static const red = Color(0xFFC54152);
}

/// Persian/RTL design system ported from the Persian frames in velixeo-design.zip.
/// This is not an English theme with translated labels: typography, direction,
/// alignments and component metrics are defined independently.
abstract final class VelixeoFaDesign {
  static const direction = TextDirection.rtl;
  static const fontFamily = 'Vazirmatn';
  static const pagePadding = EdgeInsets.fromLTRB(20, 18, 20, 24);
  static const appHeaderPadding = EdgeInsets.fromLTRB(22, 24, 22, 17);
  static const cardRadius = 21.0;
  static const controlRadius = 12.0;
  static const buttonRadius = 13.0;
  static const titleSize = 23.0;
  static const sectionTitleSize = 15.0;
  static const bodySize = 14.0;
  static const captionSize = 11.0;

  static ThemeData get theme => _theme(
        fontFamily: fontFamily,
        appBarCenterTitle: false,
        textDirection: direction,
        pageTitleWeight: FontWeight.w700,
        sectionWeight: FontWeight.w700,
        bodyHeight: 1.75,
      );
}

/// English/LTR design system ported from the English frames in velixeo-design.zip.
/// It deliberately owns its own typography and layout metrics.
abstract final class VelixeoEnDesign {
  static const direction = TextDirection.ltr;
  static const fontFamily = 'Inter';
  static const pagePadding = EdgeInsets.fromLTRB(20, 18, 20, 24);
  static const appHeaderPadding = EdgeInsets.fromLTRB(22, 24, 22, 17);
  static const cardRadius = 21.0;
  static const controlRadius = 12.0;
  static const buttonRadius = 13.0;
  static const titleSize = 23.0;
  static const sectionTitleSize = 15.0;
  static const bodySize = 14.0;
  static const captionSize = 11.0;

  static ThemeData get theme => _theme(
        fontFamily: fontFamily,
        appBarCenterTitle: false,
        textDirection: direction,
        pageTitleWeight: FontWeight.w700,
        sectionWeight: FontWeight.w650,
        bodyHeight: 1.6,
      );
}

ThemeData _theme({
  required String fontFamily,
  required bool appBarCenterTitle,
  required TextDirection textDirection,
  required FontWeight pageTitleWeight,
  required FontWeight sectionWeight,
  required double bodyHeight,
}) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: VelixeoBrand.sky,
      secondary: VelixeoBrand.skyHover,
      surface: Colors.white,
      onSurface: VelixeoBrand.ink,
      outline: VelixeoBrand.line,
      error: VelixeoBrand.red,
    ),
    scaffoldBackgroundColor: VelixeoBrand.background,
    fontFamily: fontFamily,
  );

  final textTheme = base.textTheme.copyWith(
    headlineLarge: base.textTheme.headlineLarge?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.ink,
      fontSize: 28,
      height: 1.6,
      fontWeight: FontWeight.w700,
    ),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.ink,
      fontSize: 23,
      height: textDirection == TextDirection.rtl ? 1.55 : 1.35,
      fontWeight: pageTitleWeight,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.ink,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.ink,
      fontSize: 15,
      fontWeight: sectionWeight,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.ink,
      fontSize: 14,
      height: bodyHeight,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.ink,
      fontSize: 13,
      height: bodyHeight,
    ),
    bodySmall: base.textTheme.bodySmall?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.muted,
      fontSize: 11,
      height: bodyHeight,
    ),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontFamily: fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    labelSmall: base.textTheme.labelSmall?.copyWith(
      fontFamily: fontFamily,
      fontSize: 10,
      fontWeight: FontWeight.w500,
    ),
  );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: VelixeoBrand.background,
      foregroundColor: VelixeoBrand.ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: appBarCenterTitle,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleLarge,
      iconTheme: const IconThemeData(color: Color(0xFF637681), size: 21),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(21),
        side: const BorderSide(color: Color(0xFFEEF2F5)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: VelixeoBrand.line, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: textTheme.bodyMedium?.copyWith(color: const Color(0xFF99A4AB)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDFE8ED)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDFE8ED)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: VelixeoBrand.sky, width: 1.3),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: VelixeoBrand.red),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VelixeoBrand.sky,
        foregroundColor: const Color(0xFF183B4B),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VelixeoBrand.ink,
        side: const BorderSide(color: VelixeoBrand.line),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF347996),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 12),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: VelixeoBrand.ink,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: VelixeoBrand.sky,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return VelixeoBrand.sky;
        return Colors.white;
      }),
      side: const BorderSide(color: Color(0xFFCAD8E0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );
}

/// Compatibility alias for existing business screens while the page-specific
/// Persian/English view classes are being ported. New code should reference
/// [VelixeoFaDesign] or [VelixeoEnDesign] directly.
abstract final class VelixeoDesign {
  static const sky = VelixeoBrand.sky;
  static const skyHover = VelixeoBrand.skyHover;
  static const ink = VelixeoBrand.ink;
  static const muted = VelixeoBrand.muted;
  static const soft = VelixeoBrand.soft;
  static const background = VelixeoBrand.background;
  static const line = VelixeoBrand.line;
  static const green = VelixeoBrand.green;
  static const orange = VelixeoBrand.orange;
  static const red = VelixeoBrand.red;
  static const radius = 22.0;
  static const pagePadding = EdgeInsets.fromLTRB(20, 18, 20, 24);

  static ThemeData theme(bool persian) =>
      persian ? VelixeoFaDesign.theme : VelixeoEnDesign.theme;
}
