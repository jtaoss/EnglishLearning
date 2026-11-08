import 'package:flutter/material.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds Material 3 light and dark themes from the same seed', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
  });
}
