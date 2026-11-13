import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/features/japanese/domain/japanese_controller.dart';
import 'package:english_learning/features/japanese/presentation/japanese_home_page.dart';
import 'package:english_learning/features/japanese/presentation/gojuon_page.dart';
import 'package:english_learning/features/japanese/presentation/kana_practice_page.dart';
import 'package:english_learning/features/japanese/presentation/japanese_vocabulary_page.dart';
import 'package:english_learning/features/japanese/presentation/japanese_word_card_page.dart';

Future<void> _captureScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String filename,
) async {
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final buffer = byteData.buffer.asUint8List();
    final file = File('docs/japanese/screenshots/$filename');
    await file.writeAsBytes(buffer);
  });
}

void main() {
  late JapaneseController controller;

  setUp(() async {
    controller = JapaneseController();
    await controller.initialize();
  });

  tearDown(() {
    controller.dispose();
  });

  group('Windows Desktop Multi-Resolution Layout Tests (1366x768, 1920x1080)', () {
    final viewports = [
      (const Size(1366, 768), 1.0, '1366x768 @ 100%'),
      (const Size(1920 / 1.25, 1080 / 1.25), 1.25, '1920x1080 @ 125%'),
      (const Size(1920 / 1.5, 1080 / 1.5), 1.5, '1920x1080 @ 150%'),
    ];

    for (final (size, scale, label) in viewports) {
      testWidgets(
        'JapaneseHomePage fits $label in light and dark mode without overflow',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          for (final isDark in [false, true]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: isDark ? AppTheme.dark() : AppTheme.light(),
                home: JapaneseHomePage(controller: controller),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        },
      );

      testWidgets(
        'GojuonPage fits $label in light and dark mode without overflow',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          for (final isDark in [false, true]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: isDark ? AppTheme.dark() : AppTheme.light(),
                home: GojuonPage(controller: controller),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        },
      );

      testWidgets('KanaPracticePage fits $label without overflow', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: KanaPracticePage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('JapaneseVocabularyPage fits $label without overflow', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: JapaneseVocabularyPage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('JapaneseWordCardPage fits $label without overflow', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: JapaneseWordCardPage(
              sampleId: 'J0-001',
              controller: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Capture Official Screenshots for Documentation', () {
    testWidgets(
      'captures Japanese Home, Gojuon, Practice, Vocab, and Word Card screens',
      (tester) async {
        final boundaryKey = GlobalKey();
        tester.view.physicalSize = const Size(1366, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // 1. Japanese Home Light
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: JapaneseHomePage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _captureScreenshot(
          tester,
          boundaryKey,
          '01_japanese_home_light.png',
        );

        // 2. Japanese Home Dark
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: JapaneseHomePage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _captureScreenshot(
          tester,
          boundaryKey,
          '02_japanese_home_dark.png',
        );

        // 3. Gojuon Chart Light
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: GojuonPage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _captureScreenshot(
          tester,
          boundaryKey,
          '03_gojuon_chart_light.png',
        );

        // 4. Gojuon Detail Dialog
        await tester.tap(find.byKey(const Key('kana-card-a')));
        await tester.pumpAndSettle();
        await _captureScreenshot(
          tester,
          boundaryKey,
          '04_gojuon_detail_dialog.png',
        );
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();

        // 5. Kana Practice Light
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: KanaPracticePage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _captureScreenshot(
          tester,
          boundaryKey,
          '05_kana_practice_light.png',
        );

        // 6. Pilot Vocabulary Light
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: JapaneseVocabularyPage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _captureScreenshot(
          tester,
          boundaryKey,
          '06_pilot_vocabulary_light.png',
        );

        // 7. Word Card Hidden Light
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: JapaneseWordCardPage(
                sampleId: 'J0-001',
                controller: controller,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _captureScreenshot(
          tester,
          boundaryKey,
          '07_word_card_hidden_light.png',
        );

        // 8. Word Card Revealed Light
        await tester.tap(find.byKey(const Key('reveal-meaning-btn')));
        await tester.pumpAndSettle();
        await _captureScreenshot(
          tester,
          boundaryKey,
          '08_word_card_revealed_light.png',
        );

        // 9. Word Card Dark
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: JapaneseWordCardPage(
                sampleId: 'J0-001',
                controller: controller,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _captureScreenshot(tester, boundaryKey, '09_word_card_dark.png');
      },
    );
  });
}
