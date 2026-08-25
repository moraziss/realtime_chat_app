import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Единая точка сборки [ThemeData] для всего приложения.
///
/// Держит акцентный цвет пользователя (seed) и масштаб шрифта в одном месте,
/// чтобы каждому экрану не приходилось вручную стилизовать поля ввода,
/// кнопки, диалоги и т.д. — они наследуют вид отсюда.
class AppTheme {
  AppTheme._();

  static ThemeData build({
    required Color seedColor,
    required Brightness brightness,
    required double fontScale,
  }) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    final baseTextTheme = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    final textTheme = _scaleText(
      GoogleFonts.manropeTextTheme(baseTextTheme).apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      fontScale,
    );

    final radiusL = BorderRadius.circular(20);
    final radiusM = BorderRadius.circular(16);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: GoogleFonts.manrope().fontFamily,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 20 * fontScale,
          fontWeight: FontWeight.w800,
          color: colorScheme.onSurface,
          letterSpacing: -0.3,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        isDense: false,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(isDark ? 0.35 : 0.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
        border: OutlineInputBorder(borderRadius: radiusM, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: radiusM, borderSide: BorderSide.none),
        disabledBorder: OutlineInputBorder(borderRadius: radiusM, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusM,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusM,
          borderSide: BorderSide(color: colorScheme.error, width: 1.3),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radiusM,
          borderSide: BorderSide(color: colorScheme.error, width: 1.6),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.onSurface.withOpacity(0.08),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: radiusM),
          textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15.5 * fontScale),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: radiusM),
          textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15.5 * fontScale),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14.5 * fontScale),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outlineVariant),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: radiusM),
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHigh,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: radiusL),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 19 * fontScale,
          fontWeight: FontWeight.w800,
          color: colorScheme.onSurface,
        ),
        contentTextStyle: GoogleFonts.manrope(
          fontSize: 14.5 * fontScale,
          color: colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface, fontFamily: GoogleFonts.manrope().fontFamily),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withOpacity(0.4),
        space: 1,
        thickness: 1,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.primary,
        textColor: colorScheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colorScheme.primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary.withOpacity(0.35)
              : null,
        ),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withOpacity(0.15),
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 2,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: TextStyle(color: colorScheme.onSurface, fontFamily: GoogleFonts.manrope().fontFamily),
      ),

      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorColor: colorScheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14 * fontScale),
        unselectedLabelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 14 * fontScale),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: colorScheme.primary.withOpacity(0.12),
        linearTrackColor: colorScheme.primary.withOpacity(0.12),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colorScheme.primary : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),
      ),
    );
  }

  static TextTheme _scaleText(TextTheme base, double factor) {
    TextStyle? scale(TextStyle? style, double fallback) =>
        style?.copyWith(fontSize: (style.fontSize ?? fallback) * factor);

    return base.copyWith(
      displayLarge: scale(base.displayLarge, 57),
      displayMedium: scale(base.displayMedium, 45),
      displaySmall: scale(base.displaySmall, 36),
      headlineLarge: scale(base.headlineLarge, 32),
      headlineMedium: scale(base.headlineMedium, 28),
      headlineSmall: scale(base.headlineSmall, 24),
      titleLarge: scale(base.titleLarge, 22),
      titleMedium: scale(base.titleMedium, 16),
      titleSmall: scale(base.titleSmall, 14),
      bodyLarge: scale(base.bodyLarge, 16),
      bodyMedium: scale(base.bodyMedium, 14),
      bodySmall: scale(base.bodySmall, 12),
      labelLarge: scale(base.labelLarge, 14),
      labelMedium: scale(base.labelMedium, 12),
      labelSmall: scale(base.labelSmall, 11),
    );
  }
}
