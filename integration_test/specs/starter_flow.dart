import 'package:flutter/material.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/settings/settings_repository.dart';
import 'package:english_learning/features/home/home_page.dart';
import 'package:english_learning/features/settings/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../system_back.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native theme storage survives a new app instance', (
    tester,
  ) async {
    final preferences = SharedPreferencesAsync();
    final previous = await preferences.getString(
      SharedPreferencesSettingsRepository.themeKey,
    );
    addTearDown(() async {
      if (previous == null) {
        await preferences.remove(SharedPreferencesSettingsRepository.themeKey);
      } else {
        await preferences.setString(
          SharedPreferencesSettingsRepository.themeKey,
          previous,
        );
      }
    });
    await preferences.remove(SharedPreferencesSettingsRepository.themeKey);
    await pumpNative(tester, preferences, AppConfig.developmentPreset());
    await tester.tap(find.byKey(HomePage.openSettingsKey));
    await tester.pumpAndSettle();
    if (find.text('Dark').evaluate().isEmpty) {
      await tester.tap(find.byKey(SettingsPage.themeModeKey));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 20; attempt++) {
        if (await preferences.getString(
              SharedPreferencesSettingsRepository.themeKey,
            ) ==
            'dark') {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      fail('Theme preference was not persisted.');
    });
    await simulateSystemBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('还没有学习词库'), findsOneWidget);
    await pumpNative(tester, preferences, AppConfig.productionPreset());
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });
}

Future<void> pumpNative(
  WidgetTester tester,
  SharedPreferencesAsync preferences,
  AppConfig config,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.pumpWidget(
    EnglishLearningApp(
      repository: SharedPreferencesSettingsRepository(preferences: preferences),
      logger: AppLogger(),
      config: config,
    ),
  );
  await tester.pumpAndSettle();
}
