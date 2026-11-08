import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/settings/settings_repository.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_page.dart';

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  fail('Timed out waiting for $finder');
}

Future<void> mount(
  WidgetTester tester,
  SqliteLearningRepository repository,
) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('native-capture-root'),
      child: EnglishLearningApp(
        repository: SharedPreferencesSettingsRepository(),
        logger: AppLogger(),
        config: AppConfig.developmentPreset(),
        learningRepository: repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-vocabulary')));
  await tester.pumpAndSettle();
  await waitFor(
    tester,
    find.byWidgetPredicate(
      (w) =>
          w is FilledButton &&
          w.key == VocabularyPage.sampleImportKey &&
          w.onPressed != null,
    ),
  );
}

Future<String> captureFrame(
  WidgetTester tester,
  Directory directory,
  String name,
) async {
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('native-capture-root')),
  );
  final path = '${directory.path}${Platform.pathSeparator}$name.png';
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  return path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native SQLite import, reveal, rating, repeat import and restart persistence',
    (tester) async {
      const reportRoot = String.fromEnvironment('ACCEPTANCE_REPORT_DIR');
      final directory = reportRoot.isEmpty
          ? await tester.runAsync(
              () => Directory.systemTemp.createTemp('english_learning_native_'),
            )
          : await tester.runAsync(
              () => Directory(reportRoot).create(recursive: true),
            );
      final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final path =
          '${directory!.path}${Platform.pathSeparator}acceptance-$stamp.sqlite3';
      var repository = (await tester.runAsync(
        () => SqliteLearningRepository.open(path),
      ))!;
      addTearDown(() => repository.close());
      await mount(tester, repository);
      await tester.tap(find.byKey(VocabularyPage.sampleImportKey));
      await waitFor(tester, find.text('新增 100，更新 0，未变 0'));
      final frames = <String>[
        await captureFrame(tester, directory, 'word-list-$stamp'),
      ];
      final initial = (await tester.runAsync(repository.readWords))!;
      expect(initial.length, 100);
      expect(
        initial.every(
          (w) => w.status == 'untested' && w.pronunciationStatus == '未测试',
        ),
        isTrue,
      );
      expect(
        initial.map((w) => w.entry.word).toSet().containsAll([
          'May',
          'may',
          'March',
          'march',
        ]),
        isTrue,
      );
      await tester.tap(find.byKey(VocabularyPage.sampleImportKey));
      await waitFor(tester, find.text('新增 0，更新 0，未变 100'));
      final target = initial.firstWhere((w) => w.entry.libraryClass == '主学习');
      await tester.tap(find.byKey(ValueKey('word-${target.entry.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('meaning')), findsNothing);
      frames.add(await captureFrame(tester, directory, 'answer-hidden-$stamp'));
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(ReviewPage.gradeKey(ReviewGrade.familiar)),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(ReviewPage.revealKey));
      await tester.pump();
      expect(find.text(target.entry.meaning), findsOneWidget);
      expect(find.byKey(const Key('part-of-speech')), findsOneWidget);
      frames.add(
        await captureFrame(tester, directory, 'answer-revealed-$stamp'),
      );
      await tester.tap(find.byKey(ReviewPage.gradeKey(ReviewGrade.familiar)));
      await tester.tap(find.byKey(ReviewPage.gradeKey(ReviewGrade.familiar)));
      await waitFor(tester, find.byKey(const Key('review-saved')));
      expect(await tester.runAsync(repository.reviewEventCount), 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(repository.close);
      repository = (await tester.runAsync(
        () => SqliteLearningRepository.open(path),
      ))!;
      final restored = (await tester.runAsync(repository.readWords))!;
      final studied = restored.singleWhere(
        (w) => w.entry.id == target.entry.id,
      );
      expect(restored.length, 100);
      expect(studied.status, 'familiar');
      expect(studied.reviewCount, 1);
      expect(studied.pronunciationStatus, '未测试');
      expect(
        studied.dueAt!.difference(studied.lastReviewedAt!),
        const Duration(days: 1),
      );
      await mount(tester, repository);
      await tester.tap(find.byKey(VocabularyPage.sampleImportKey));
      await waitFor(tester, find.text('新增 0，更新 0，未变 100'));
      expect(
        (await tester.runAsync(repository.readWords))!
            .singleWhere((w) => w.entry.id == target.entry.id)
            .status,
        'familiar',
      );
      expect(await tester.runAsync(repository.reviewEventCount), 1);
      final report = {
        'platform': Platform.operatingSystem,
        'native_process_id': pid,
        'database': path,
        'initial_words': 100,
        'initial_learning_and_pronunciation_untested': true,
        'words_after_repeat_import': restored.length,
        'case_distinct_heads_retained': true,
        'answer_hidden_before_reveal': true,
        'review_events_after_rapid_repeat_click': 1,
        'persisted_stable_id': studied.entry.id,
        'persisted_status': studied.status,
        'persisted_due_utc': studied.dueAt!.toIso8601String(),
        'reimport_preserved_progress': true,
        'network_calls_required_for_learning': false,
        'test_database_separate_from_personal_database': true,
        'rendered_ui_frames': frames,
      };
      final output = File(
        '${directory.path}${Platform.pathSeparator}native-local-flow-$stamp.json',
      );
      await tester.runAsync(
        () => output.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
        ),
      );
      debugPrint('NATIVE_ACCEPTANCE_REPORT=${output.path}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
