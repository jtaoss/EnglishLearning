import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/features/home/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_settings_repository.dart';

void main() {
  testWidgets('changing app environment preserves the saved theme', (
    tester,
  ) async {
    final repository = MemorySettingsRepository(stored: 'dark');
    for (final config in [
      AppConfig.developmentPreset(),
      AppConfig.stagingPreset(),
      AppConfig.productionPreset(),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        EnglishLearningApp(
          repository: repository,
          logger: AppLogger(),
          config: config,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(
        find.text('Environment: ${config.environment.label}'),
        findsOneWidget,
      );
      expect(find.byKey(HomePage.openSettingsKey), findsOneWidget);
    }
  });
}
