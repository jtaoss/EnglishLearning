import 'package:flutter/material.dart';
import 'package:english_learning/app/app_metadata.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_settings.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/features/home/home_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_settings_repository.dart';
import 'support/system_back.dart';

void main() {
  testWidgets('opens settings and returns to the empty learning home', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      AppMetadata.title,
    );
    expect(find.text('还没有学习词库'), findsOneWidget);
    await tester.tap(find.byKey(HomePage.openSettingsKey));
    await tester.pumpAndSettle();
    expect(find.text('Theme'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('还没有学习词库'), findsOneWidget);
  });
  testWidgets('theme selection updates the Material 3 app', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(HomePage.openSettingsKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme?.brightness, Brightness.dark);
  });
  testWidgets('restarting the app keeps the saved theme', (tester) async {
    final repository = MemorySettingsRepository();
    await pumpApp(tester, repository: repository);
    await tester.tap(find.byKey(HomePage.openSettingsKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpApp(tester, repository: repository);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });
  testWidgets('an invalid saved theme falls back to the system theme', (
    tester,
  ) async {
    await pumpApp(tester, repository: MemorySettingsRepository(stored: 'neon'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });
  testWidgets('system back leaves settings', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(HomePage.openSettingsKey));
    await tester.pumpAndSettle();
    await simulateSystemBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('还没有学习词库'), findsOneWidget);
  });
  for (final path in ['/missing-page', '/demo', '/library']) {
    testWidgets('$path is not registered and can return home', (tester) async {
      final settings = AppSettings(repository: MemorySettingsRepository());
      final router = AppRouter.create(appSettings: settings);
      addTearDown(router.dispose);
      addTearDown(settings.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.text('Page not found'), findsOneWidget);
      await tester.tap(find.text('Back to home'));
      await tester.pumpAndSettle();
      expect(find.text('还没有学习词库'), findsOneWidget);
    });
  }
  for (final size in [const Size(320, 568), const Size(1440, 900)]) {
    testWidgets('home and settings fit a $size window with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(HomePage.openSettingsKey));
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> pumpApp(
  WidgetTester tester, {
  MemorySettingsRepository? repository,
}) async {
  await tester.pumpWidget(
    EnglishLearningApp(
      repository: repository ?? MemorySettingsRepository(),
      logger: AppLogger(),
      config: AppConfig.developmentPreset(),
    ),
  );
  await tester.pumpAndSettle();
}
