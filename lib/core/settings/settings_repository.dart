import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret preferences.
///
/// Implementations must not store credentials, tokens, or session secrets.
abstract interface class SettingsRepository {
  Future<ThemeMode> readThemeMode();

  Future<void> writeThemeMode(ThemeMode mode);
}

/// Parses a stored theme name. Unknown or missing values use the system theme.
ThemeMode themeModeFromStorage(String? raw) {
  return switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.system,
  };
}

String themeModeToStorage(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}

/// Theme preference stored with [SharedPreferencesAsync].
final class SharedPreferencesSettingsRepository implements SettingsRepository {
  SharedPreferencesSettingsRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const themeKey = 'theme_mode';

  final SharedPreferencesAsync _preferences;

  @override
  Future<ThemeMode> readThemeMode() async {
    try {
      final raw = await _preferences.getString(themeKey);
      return themeModeFromStorage(raw);
    } catch (_) {
      return ThemeMode.system;
    }
  }

  @override
  Future<void> writeThemeMode(ThemeMode mode) {
    return _preferences.setString(themeKey, themeModeToStorage(mode));
  }
}
