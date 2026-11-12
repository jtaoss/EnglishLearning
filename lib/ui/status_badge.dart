import 'package:flutter/material.dart';
import 'package:english_learning/app/app_theme.dart';

String formatLocalDateTime(DateTime value) {
  final date = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}

/// Formats a real count with thousands separators, e.g. 5332 -> 5,332.
String formatCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

final class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.label,
    this.status,
    this.colors,
    this.icon,
    this.textKey,
    super.key,
  });

  final String label;
  final String? status;
  final StatusColors? colors;
  final IconData? icon;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final palette =
        colors ?? AppTheme.statusColorsFor(status ?? label, brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: palette.foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              key: textKey,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.backgroundColor,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: backgroundColor ?? scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor ?? scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

enum BannerTone { info, success, warning, danger }

final class StatusBanner extends StatelessWidget {
  const StatusBanner({
    required this.message,
    this.tone = BannerTone.info,
    this.icon,
    this.textKey,
    this.trailing,
    super.key,
  });

  final String message;
  final BannerTone tone;
  final IconData? icon;
  final Key? textKey;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final palette = switch (tone) {
      BannerTone.success => AppTheme.masteredColors(brightness),
      BannerTone.warning => AppTheme.familiarColors(brightness),
      BannerTone.danger => AppTheme.forgottenColors(brightness),
      BannerTone.info => AppTheme.infoColors(brightness),
    };
    final defaultIcon = switch (tone) {
      BannerTone.success => Icons.check_circle_outline,
      BannerTone.warning => Icons.info_outline,
      BannerTone.danger => Icons.error_outline,
      BannerTone.info => Icons.info_outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(icon ?? defaultIcon, size: 18, color: palette.foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              key: textKey,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}
