import 'package:flutter/material.dart';
import 'package:english_learning/core/settings/settings_repository.dart';

/// Theme selection for this process.
///
/// The repository is the durable copy. A read or write failure leaves the
/// in-memory selection on the system theme or on the last choice the user made.
final class AppSettings extends ChangeNotifier {
  AppSettings({required this.repository});

  final SettingsRepository repository;
  ThemeMode _themeMode = ThemeMode.system;
  var _userChanged = false;
  var _disposed = false;

  ThemeMode get themeMode => _themeMode;

  Future<void> restore() async {
    ThemeMode mode = ThemeMode.system;
    try {
      mode = await repository.readThemeMode();
    } catch (_) {
      mode = ThemeMode.system;
    }
    if (_disposed || _userChanged) {
      return;
    }
    _themeMode = mode;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _userChanged = true;
    if (_themeMode != mode) {
      _themeMode = mode;
      if (!_disposed) {
        notifyListeners();
      }
    }
    try {
      await repository.writeThemeMode(mode);
    } catch (_) {
      // The screen keeps the selection even when storage is unavailable.
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    super.dispose();
  }
}
