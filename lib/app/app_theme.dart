import 'package:flutter/material.dart';

/// Semantic color tokens for study status badges, rating buttons, and alerts.
@immutable
final class StatusColors {
  const StatusColors({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;
}

abstract final class AppTheme {
  static const Color seed = Color(0xFF1E4DB7);

  static const List<String> _fontFallback = <String>[
    'Segoe UI',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'sans-serif',
  ];

  static StatusColors masteredColors(Brightness brightness) =>
      brightness == Brightness.dark
      ? const StatusColors(
          foreground: Color(0xFF6EE7A0),
          background: Color(0xFF122D21),
          border: Color(0xFF23533B),
        )
      : const StatusColors(
          foreground: Color(0xFF136C3E),
          background: Color(0xFFEAF7EF),
          border: Color(0xFFB7E4C7),
        );

  static StatusColors familiarColors(Brightness brightness) =>
      brightness == Brightness.dark
      ? const StatusColors(
          foreground: Color(0xFFFCD34D),
          background: Color(0xFF31230F),
          border: Color(0xFF614419),
        )
      : const StatusColors(
          foreground: Color(0xFF9A5B00),
          background: Color(0xFFFEF6E7),
          border: Color(0xFFF6D5A3),
        );

  static StatusColors forgottenColors(Brightness brightness) =>
      brightness == Brightness.dark
      ? const StatusColors(
          foreground: Color(0xFFFCA5A5),
          background: Color(0xFF351919),
          border: Color(0xFF682B2B),
        )
      : const StatusColors(
          foreground: Color(0xFFB42318),
          background: Color(0xFFFEF0EF),
          border: Color(0xFFF7C7C3),
        );

  static StatusColors neutralColors(Brightness brightness) =>
      brightness == Brightness.dark
      ? const StatusColors(
          foreground: Color(0xFF98A2B3),
          background: Color(0xFF202938),
          border: Color(0xFF323F54),
        )
      : const StatusColors(
          foreground: Color(0xFF475467),
          background: Color(0xFFF2F4F7),
          border: Color(0xFFD0D5DD),
        );

  static StatusColors infoColors(Brightness brightness) =>
      brightness == Brightness.dark
      ? const StatusColors(
          foreground: Color(0xFF93C5FD),
          background: Color(0xFF16253E),
          border: Color(0xFF284675),
        )
      : const StatusColors(
          foreground: Color(0xFF1D4ED8),
          background: Color(0xFFEFF6FF),
          border: Color(0xFFBFDBFE),
        );

  static StatusColors statusColorsFor(String status, Brightness brightness) =>
      switch (status) {
        'mastered' ||
        '掌握' ||
        'confident' ||
        '能独立认读' => masteredColors(brightness),
        'familiar' || '眼熟' || '基本会读' || '基本掌握' => familiarColors(brightness),
        'forgotten' ||
        '遗忘' ||
        'needsPractice' ||
        '再练习' => forgottenColors(brightness),
        _ => neutralColors(brightness),
      };

  static ThemeData light() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    final scheme = baseScheme.copyWith(
      primary: const Color(0xFF1E4DB7),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDCE6FF),
      onPrimaryContainer: const Color(0xFF0E296B),
      secondary: const Color(0xFF344054),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFEAECF0),
      onSecondaryContainer: const Color(0xFF1D2939),
      surface: const Color(0xFFFFFFFF),
      onSurface: const Color(0xFF101828),
      onSurfaceVariant: const Color(0xFF475467),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF8FAFC),
      surfaceContainer: const Color(0xFFF1F5F9),
      surfaceContainerHigh: const Color(0xFFEAEFF6),
      outline: const Color(0xFF98A2B3),
      outlineVariant: const Color(0xFFE2E8F0),
      error: const Color(0xFFB42318),
      errorContainer: const Color(0xFFFEE4E2),
      onErrorContainer: const Color(0xFF7A271A),
    );
    return _buildTheme(
      scheme: scheme,
      scaffoldBackground: const Color(0xFFF5F7FB),
    );
  }

  static ThemeData dark() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    final scheme = baseScheme.copyWith(
      primary: const Color(0xFF7CA4FF),
      onPrimary: const Color(0xFF0A1D4D),
      primaryContainer: const Color(0xFF1C356E),
      onPrimaryContainer: const Color(0xFFDCE6FF),
      secondary: const Color(0xFF98A2B3),
      onSecondary: const Color(0xFF101828),
      secondaryContainer: const Color(0xFF242F42),
      onSecondaryContainer: const Color(0xFFE4E7EC),
      surface: const Color(0xFF161E2B),
      onSurface: const Color(0xFFF2F4F7),
      onSurfaceVariant: const Color(0xFF98A2B3),
      surfaceContainerLowest: const Color(0xFF111823),
      surfaceContainerLow: const Color(0xFF1B2434),
      surfaceContainer: const Color(0xFF202B3D),
      surfaceContainerHigh: const Color(0xFF28354A),
      outline: const Color(0xFF475467),
      outlineVariant: const Color(0xFF283347),
      error: const Color(0xFFF97066),
      errorContainer: const Color(0xFF3B1A19),
      onErrorContainer: const Color(0xFFFECDD3),
    );
    return _buildTheme(
      scheme: scheme,
      scaffoldBackground: const Color(0xFF0E141D),
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme scheme,
    required Color scaffoldBackground,
  }) {
    final isDark = scheme.brightness == Brightness.dark;
    final baseText =
        (isDark
                ? Typography.material2021().white
                : Typography.material2021().black)
            .apply(
              fontFamilyFallback: _fontFallback,
              bodyColor: scheme.onSurface,
              displayColor: scheme.onSurface,
            );

    final textTheme = baseText.copyWith(
      headlineLarge: baseText.headlineLarge?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.2,
        color: scheme.onSurface,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.25,
        color: scheme.onSurface,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.3,
        color: scheme.onSurface,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: scheme.onSurface,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: scheme.onSurface,
      ),
      titleSmall: baseText.titleSmall?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
      bodyLarge: baseText.bodyLarge?.copyWith(
        fontSize: 15,
        height: 1.55,
        color: scheme.onSurface,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
        color: scheme.onSurface,
      ),
      bodySmall: baseText.bodySmall?.copyWith(
        fontSize: 12.5,
        height: 1.45,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: baseText.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: baseText.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          minimumSize: const Size(88, 44),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          minimumSize: const Size(84, 42),
          shape: buttonShape,
          side: BorderSide(color: scheme.outlineVariant, width: 1.2),
          foregroundColor: scheme.onSurface,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          minimumSize: const Size(64, 38),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        helperStyle: textTheme.bodySmall,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        iconColor: scheme.onSurfaceVariant,
        collapsedIconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        collapsedTextColor: scheme.onSurfaceVariant,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
      ),
    );
  }
}
