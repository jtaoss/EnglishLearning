import 'dart:async';

import 'package:flutter/material.dart';
import 'package:english_learning/app/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_settings_repository.dart';

void main() {
  test('notifies listeners only when the theme mode changes', () async {
    final settings = AppSettings(repository: MemorySettingsRepository());
    addTearDown(settings.dispose);
    var notifications = 0;
    settings.addListener(() => notifications++);

    expect(settings.themeMode, ThemeMode.system);
    await settings.setThemeMode(ThemeMode.dark);
    await settings.setThemeMode(ThemeMode.dark);
    await settings.setThemeMode(ThemeMode.light);

    expect(settings.themeMode, ThemeMode.light);
    expect(notifications, 2);
  });

  test('restores a stored theme', () async {
    final repository = MemorySettingsRepository(stored: 'dark');
    final settings = AppSettings(repository: repository);
    addTearDown(settings.dispose);

    await settings.restore();

    expect(settings.themeMode, ThemeMode.dark);
  });

  test('writes the selected theme for the next launch', () async {
    final repository = MemorySettingsRepository();
    final settings = AppSettings(repository: repository);
    addTearDown(settings.dispose);

    await settings.setThemeMode(ThemeMode.dark);
    settings.dispose();

    final restored = AppSettings(repository: repository);
    addTearDown(restored.dispose);
    await restored.restore();

    expect(restored.themeMode, ThemeMode.dark);
  });

  test('an invalid stored value falls back to the system theme', () async {
    final settings = AppSettings(
      repository: MemorySettingsRepository(stored: 'neon'),
    );
    addTearDown(settings.dispose);

    await settings.restore();

    expect(settings.themeMode, ThemeMode.system);
  });

  test('a read failure falls back to the system theme', () async {
    final settings = AppSettings(
      repository: MemorySettingsRepository(stored: 'dark', throwOnRead: true),
    );
    addTearDown(settings.dispose);

    await settings.restore();

    expect(settings.themeMode, ThemeMode.system);
  });

  test('a write failure keeps the current choice', () async {
    final settings = AppSettings(
      repository: MemorySettingsRepository(throwOnWrite: true),
    );
    addTearDown(settings.dispose);

    await settings.setThemeMode(ThemeMode.dark);

    expect(settings.themeMode, ThemeMode.dark);
  });

  test('a late restore does not overwrite a user choice', () async {
    final gate = Completer<void>();
    final settings = AppSettings(
      repository: MemorySettingsRepository(
        stored: 'light',
        throwOnWrite: true,
        readGate: gate,
      ),
    );
    addTearDown(settings.dispose);

    final pending = settings.restore();
    await settings.setThemeMode(ThemeMode.dark);
    gate.complete();
    await pending;

    expect(settings.themeMode, ThemeMode.dark);
  });
}
