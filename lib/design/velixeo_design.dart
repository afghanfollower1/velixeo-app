import 'package:flutter/material.dart';

/// Locked VELIXEO brand palette from velixeo-design(1).zip.
///
/// Business logic can be shared across locales, but the Persian and English
/// presentation systems below intentionally own independent typography,
/// spacing and component metrics.
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

  static const successSoft = Color(0xFFEAF8F1);
  static const warningSoft = Color(0xFFFFF5E7);
  static const errorSoft = Color(0xFFFCEEF0);
  static const infoSoft = Color(0xFFEAF7FE);
  static const neutralSoft = Color(0xFFF0F3F6);
}

/// Persian/RTL presentation contract.
///
/// Do not use these values as a translated English theme. Persian screens own
/// their own widget trees and use these metrics directly.
abstract final class VelixeoFaDesign {
  static const direction = TextDirection.rtl;
  static const fontFamily = 'Vazirmatn';

  static const pagePadding = EdgeInsets.fromLTRB(20, 18, 20, 24);
  static const compactPagePadding = EdgeInsets.fromLTRB(18, 14, 18, 22);
  static const appHeaderPadding = EdgeInsets.fromLTRB(22, 24, 22, 17);
  static const cardPadding = EdgeInsets.all(24);
  static const compactCardPadding = EdgeInsets.all(18);

  static const cardRadius = 22.0;
  static const compactCardRadius = 18.0;
  static const controlRadius = 12.0;
  static const searchRadius = 14.0;
  static const buttonRadius = 13.0;
  static const iconButtonRadius = 14.0;

  static const pageTitleSize = 21.0;
  static const sectionTitleSize = 17.0;
  static const cardTitleSize = 15.0;
  static const bodySize = 14.0;
  static const compactBodySize = 13.0;
  static const captionSize = 12.0;
  static const tinySize = 10.0;
  static const amountSize = 30.0;

  static const titleWeight = FontWeight.w700;
  static const sectionWeight = FontWeight.w700;
  static const bodyHeight = 1.75;
  static const compactBodyHeight = 1.65;

  static ThemeData get theme => _buildTheme(
        fontFamily: fontFamily,
        pageTitleSize: pageTitleSize,
        titleWeight: titleWeight,
        sectionWeight: sectionWeight,
        bodyHeight: bodyHeight,
        textDirection: direction,
      );
}

/// English/LTR presentation contract.
///
/// English screens are implemented independently from Persian screens. Shared
/// data/actions are allowed; shared page composition is not the target.
abstract final class VelixeoEnDesign {
  static const direction = TextDirection.ltr;
  static const fontFamily = 'Inter';

  static const pagePadding = EdgeInsets.fromLTRB(20, 18, 20, 24);
  static const compactPagePadding = EdgeInsets.fromLTRB(18, 14, 18, 22);
  static const appHeaderPadding = EdgeInsets.fromLTRB(22, 24, 22, 17);
  static const cardPadding = EdgeInsets.all(24);
  static const compactCardPadding = EdgeInsets.all(18);

  static const cardRadius = 22.0;
  static const compactCardRadius = 18.0;
  static const controlRadius = 12.0;
  static const searchRadius = 14.0;
  static const buttonRadius = 13.0;
  static const iconButtonRadius = 14.0;

  static const pageTitleSize = 21.0;
  static const sectionTitleSize = 17.0;
  static const cardTitleSize = 15.0;
  static const bodySize = 14.0;
  static const compactBodySize = 13.0;
  static const captionSize = 12.0;
  static const tinySize = 10.0;
  static const amountSize = 30.0;

  static const titleWeight = FontWeight.w700;
  static const sectionWeight = FontWeight.w600;
  static const bodyHeight = 1.60;
  static const compactBodyHeight = 1.50;

  static ThemeData get theme => _buildTheme(
        fontFamily: fontFamily,
        pageTitleSize: pageTitleSize,
        titleWeight: titleWeight,
        sectionWeight: sectionWeight,
        bodyHeight: bodyHeight,
        textDirection: direction,
      );
}

ThemeData _buildTheme({
  required String fontFamily,
  required double pageTitleSize,
  required FontWeight titleWeight,
  required FontWeight sectionWeight,
  required double bodyHeight,
  required TextDirection textDirection,
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
      height: textDirection == TextDirection.rtl ? 1.60 : 1.35,
      fontWeight: FontWeight.w700,
    ),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.ink,
      fontSize: pageTitleSize,
      height: textDirection == TextDirection.rtl ? 1.70 : 1.35,
      fontWeight: titleWeight,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.ink,
      fontSize: 17,
      height: textDirection == TextDirection.rtl ? 1.70 : 1.45,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.ink,
      fontSize: 15,
      height: textDirection == TextDirection.rtl ? 1.70 : 1.45,
      fontWeight: sectionWeight,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.ink,
      fontSize: 14,
      height: bodyHeight,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.ink,
      fontSize: 13,
      height: bodyHeight,
      fontWeight: FontWeight.w400,
    ),
    bodySmall: base.textTheme.bodySmall?.copyWith(
      fontFamily: fontFamily,
      color: VelixeoBrand.muted,
      fontSize: 12,
      height: bodyHeight,
      fontWeight: FontWeight.w400,
    ),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontFamily: fontFamily,
      fontSize: 14,
      height: textDirection == TextDirection.rtl ? 1.65 : 1.45,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: base.textTheme.labelMedium?.copyWith(
      fontFamily: fontFamily,
      fontSize: 12,
      height: textDirection == TextDirection.rtl ? 1.65 : 1.45,
      fontWeight: FontWeight.w500,
    ),
    labelSmall: base.textTheme.labelSmall?.copyWith(
      fontFamily: fontFamily,
      fontSize: 10,
      height: textDirection == TextDirection.rtl ? 1.65 : 1.45,
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
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleLarge,
      iconTheme: const IconThemeData(
        color: Color(0xFF637681),
        size: 21,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFEEF2F5)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: VelixeoBrand.line,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: const Color(0xFF99A4AB),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
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
        borderSide: const BorderSide(
          color: VelixeoBrand.sky,
          width: 1.3,
        ),
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
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        elevation: 0,
        shadowColor: const Color(0x2138BDF8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VelixeoBrand.ink,
        side: const BorderSide(color: VelixeoBrand.line),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF347996),
        textStyle: textTheme.labelMedium,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: const Color(0xFF637681),
        backgroundColor: Colors.white,
        side: const BorderSide(color: VelixeoBrand.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: VelixeoBrand.ink,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: Colors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: VelixeoBrand.sky,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return VelixeoBrand.sky;
        }
        return Colors.white;
      }),
      side: const BorderSide(color: Color(0xFFCAD8E0)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: const Color(0xFF2288B1),
      unselectedLabelColor: const Color(0xFF80919D),
      indicatorColor: VelixeoBrand.sky,
      dividerColor: VelixeoBrand.line,
      labelStyle: textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: textTheme.labelMedium,
    ),
  );
}

/// Compatibility alias for business widgets that do not own page layout.
///
/// New page composition must use [VelixeoFaDesign] or [VelixeoEnDesign]
/// directly. Keeping the alias avoids mixing presentation refactors with
/// unrelated API/business changes.
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


class VelixeoFaPageHeader extends StatelessWidget {
  const VelixeoFaPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.leading,
    this.trailing,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? leading;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(bottom: compact ? 12 : 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onBack != null) ...[
                _VelixeoHeaderButton(
                  icon: Icons.arrow_forward_rounded,
                  onTap: onBack!,
                ),
                const SizedBox(width: 12),
              ] else if (leading != null) ...[
                leading!,
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: VelixeoBrand.ink,
                          fontFamily: VelixeoFaDesign.fontFamily,
                          fontSize: compact ? 18 : 21,
                          height: 1.55,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VelixeoBrand.muted,
                            fontFamily: VelixeoFaDesign.fontFamily,
                            fontSize: 10.5,
                            height: 1.75,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
        ),
      );
}

class VelixeoEnPageHeader extends StatelessWidget {
  const VelixeoEnPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.leading,
    this.trailing,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? leading;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: EdgeInsets.only(bottom: compact ? 12 : 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onBack != null) ...[
                _VelixeoHeaderButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: onBack!,
                ),
                const SizedBox(width: 12),
              ] else if (leading != null) ...[
                leading!,
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: VelixeoBrand.ink,
                          fontFamily: VelixeoEnDesign.fontFamily,
                          fontSize: compact ? 18 : 21,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VelixeoBrand.muted,
                            fontFamily: VelixeoEnDesign.fontFamily,
                            fontSize: 10.5,
                            height: 1.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
        ),
      );
}

class _VelixeoHeaderButton extends StatelessWidget {
  const _VelixeoHeaderButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: const BorderSide(color: VelixeoBrand.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox.square(
            dimension: 42,
            child: Icon(
              icon,
              size: 20,
              color: const Color(0xFF5E7582),
            ),
          ),
        ),
      );
}
