import 'package:flutter/material.dart';

/// VELIXEO design system — ported from velixeo-design.zip (2026-09-23).
abstract final class VelixeoDesign {
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
  static const radius = 22.0;
  static const pagePadding = EdgeInsets.fromLTRB(20, 18, 20, 24);

  static ThemeData theme(bool persian) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: sky,
        secondary: skyHover,
        surface: Colors.white,
        onSurface: ink,
        outline: line,
        error: red,
      ),
      scaffoldBackgroundColor: background,
    );
    final localized = base.textTheme.apply(
      fontFamily: persian ? 'Vazirmatn' : 'Inter',
    );

    return base.copyWith(
      textTheme: localized.apply(bodyColor: ink, displayColor: ink),
      primaryTextTheme: localized.apply(bodyColor: ink, displayColor: ink),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: localized.titleLarge?.copyWith(
          color: ink, fontSize: 18, fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: Color(0xFFEEF2F5)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) =>
          localized.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? const Color(0xFF329ECA)
                : const Color(0xFF97A5AD),
            fontSize: 10,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? const Color(0xFF329ECA)
              : const Color(0xFF97A5AD),
          size: 21,
        )),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: localized.bodyMedium?.copyWith(
          color: const Color(0xFF99A4AB), fontSize: 14,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
          borderSide: const BorderSide(color: sky, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: sky,
          foregroundColor: const Color(0xFF183B4B),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: localized.labelLarge?.copyWith(
            fontSize: 14, fontWeight: FontWeight.w700,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: line),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: sky),
    );
  }
}
