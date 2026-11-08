import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/settings/settings_repository.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_content.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/review/review_schedule.dart';

import 'local_learning.dart' show captureFrame;
import 'p1d_common.dart';

void main() {
  testWidgets(
    'P1-D cloned learning: 15 rated words, six native recordings and exact due boundaries',
    (tester) async {
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(p1dDatabase),
      ))!;
      addTearDown(repo.close);
      final all = (await tester.runAsync(repo.readWords))!;
      expect(all.length, 100);
      final initialEvents = (await tester.runAsync(repo.reviewEventCount))!;
      final catalog = await PronunciationCatalog.load();
      final audioIds = catalog.entries.keys.toSet();
      final selected = [
        ...all.where((word) => audioIds.contains(word.entry.id)),
        ...all
            .where(
              (word) =>
                  word.entry.libraryClass == '主学习' &&
                  !audioIds.contains(word.entry.id),
            )
            .take(9),
      ];
      expect(selected.length, 15);
      expect(selected.every((word) => word.entry.libraryClass == '主学习'), true);
      final base = DateTime.utc(2026, 11, 8, 15, 59, 30);
      var now = base;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('native-capture-root'),
          child: EnglishLearningApp(
            repository: SharedPreferencesSettingsRepository(),
            logger: AppLogger(),
            config: AppConfig.developmentPreset(),
            learningRepository: repo,
            clock: () => now,
            pronunciationServices: PronunciationServices(
              store: repo,
              logger: AppLogger(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('open-vocabulary')));
      await tester.pump(const Duration(milliseconds: 500));
      final ratings = <Map<String, Object?>>[];
      final audio = <Map<String, Object?>>[];
      final missing = <String>[];
      var audioComplete = false;
      try {
        for (var index = 0; index < selected.length; index++) {
          final word = selected[index];
          await saveP1d(tester, 'learning-stage.json', {
            'word': word.entry.word,
            'index': index,
            'phase': 'open',
          });
          await openListWord(tester, word.entry.id);
          expect(find.byKey(const Key('meaning')), findsNothing);
          expect(
            tester
                .widget<OutlinedButton>(
                  find.byKey(ReviewPage.gradeKey(ReviewGrade.mastered)),
                )
                .onPressed,
            isNull,
          );
          await tester.ensureVisible(find.byKey(ReviewPage.revealKey));
          await tester.tap(find.byKey(ReviewPage.revealKey));
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text(word.entry.meaning), findsOneWidget);
          final grade = ReviewGrade.values[index % 3];
          await tester.ensureVisible(find.byKey(ReviewPage.gradeKey(grade)));
          await tester.tap(find.byKey(ReviewPage.gradeKey(grade)));
          await waitP1d(tester, find.byKey(const Key('review-saved')));
          expect(
            tester
                .widget<OutlinedButton>(find.byKey(ReviewPage.gradeKey(grade)))
                .onPressed,
            isNull,
          );
          final saved = (await tester.runAsync(repo.readWords))!
              .singleWhere((w) => w.entry.id == word.entry.id);
          expect(saved.status, grade.name);
          expect(saved.reviewCount, word.reviewCount + 1);
          expect(saved.lastReviewedAt, base);
          expect(saved.dueAt, ReviewSchedule.nextDue(grade, base));
          ratings.add({
            'id': word.entry.id,
            'word': word.entry.word,
            'grade': grade.name,
            'reviewed_at': base.toIso8601String(),
            'due_at': saved.dueAt!.toIso8601String(),
          });
          final beforeAudio = (await tester.runAsync(
            () async => snapshotTables(p1dDatabase),
          ))!;
          await tester.ensureVisible(
            find.byKey(const Key('word-pronunciation')),
          );
          await tester.tap(find.byKey(const Key('word-pronunciation')));
          await tester.pump(const Duration(milliseconds: 500));
          if (audioIds.contains(word.entry.id)) {
            await waitP1d(
              tester,
              find.byKey(const Key('confirm-self-reading')),
            );
            expect(find.byKey(const Key('phonics-note')), findsNothing);
            await tester.ensureVisible(
              find.byKey(const Key('confirm-self-reading')),
            );
            await tester.tap(find.byKey(const Key('confirm-self-reading')));
            await tester.pump(const Duration(milliseconds: 500));
            for (
              var replay = 0;
              replay < (word.entry.word == 'tree' ? 2 : 1);
              replay++
            ) {
              await saveP1d(tester, 'audio-stage.json', {
                'stamp': stamp,
                'pid': pid,
                'word': word.entry.word,
                'attempt': '${word.entry.word}-$replay',
                'phase': 'play',
              });
              await tester.ensureVisible(
                find.byKey(const Key('play-pronunciation')),
              );
              await tester.tap(find.byKey(const Key('play-pronunciation')));
              for (var wait = 0; wait < 200; wait++) {
                await tester.pump(const Duration(milliseconds: 50));
                if (find
                        .byKey(const Key('pronunciation-error'))
                        .evaluate()
                        .isNotEmpty ||
                    find.text('播放完成，请对照后自评').evaluate().isNotEmpty) {
                  break;
                }
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 100)),
                );
              }
              if (find.text('播放完成，请对照后自评').evaluate().isEmpty) {
                await captureFrame(
                  tester,
                  Directory(p1dDirectory),
                  'playback-failure',
                );
                await saveP1d(tester, 'playback-failure.json', {
                  'word': word.entry.word,
                  'replay': replay,
                  'messages': tester
                      .widgetList<Text>(find.byType(Text))
                      .map((text) => text.data)
                      .toList(),
                });
              }
              expect(find.text('播放完成，请对照后自评'), findsOneWidget);
              expect(
                find.byKey(const Key('pronunciation-error')),
                findsNothing,
              );
              audio.add({
                'word': word.entry.word,
                'attempt': replay,
                'native_completed': true,
              });
            }
            final pronunciation = PronunciationGrade.values[index % 3];
            final gradeKey = Key('pronunciation-grade-${pronunciation.name}');
            await tester.ensureVisible(find.byKey(gradeKey));
            await tester.tap(find.byKey(gradeKey));
            await waitP1d(tester, find.byKey(const Key('pronunciation-saved')));
            expect(
              (await tester.runAsync(
                () => repo.readPronunciation(word.entry.id),
              ))!.grade,
              pronunciation,
            );
          } else {
            await waitP1d(tester, find.byKey(const Key('audio-missing')));
            expect(find.byKey(const Key('play-pronunciation')), findsNothing);
            missing.add(word.entry.word);
          }
          await saveP1d(tester, 'learning-stage.json', {
            'word': word.entry.word,
            'index': index,
            'phase': 'audio_done',
          });
          final afterAudio = (await tester.runAsync(
            () async => snapshotTables(p1dDatabase),
          ))!;
          expect(
            afterAudio['learning_progress'],
            beforeAudio['learning_progress'],
          );
          expect(afterAudio['review_events'], beforeAudio['review_events']);
          await tester.pageBack();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.ensureVisible(find.text('返回词库'));
          await saveP1d(tester, 'learning-stage.json', {
            'word': word.entry.word,
            'index': index,
            'phase': 'return',
          });
          await tester.tap(find.text('返回词库'));
          await tester.pump(const Duration(milliseconds: 500));
        }
        audioComplete = true;
      } finally {
        await saveP1d(tester, 'audio-stage.json', {
          'stamp': stamp,
          'pid': pid,
          'phase': 'finished',
          'passed': audioComplete,
        });
      }
      expect(
        (await tester.runAsync(repo.reviewEventCount))!,
        initialEvents + 15,
      );
      final persisted = (await tester.runAsync(repo.readWords))!;
      final selectedIds = selected.map((w) => w.entry.id).toSet();
      final untouchedDue = persisted
          .where(
            (w) =>
                w.entry.libraryClass == '主学习' &&
                !selectedIds.contains(w.entry.id) &&
                w.isDue(base),
          )
          .length;
      await tester.ensureVisible(find.text('仅看未测试 / 到期'));
      await tester.tap(find.text('仅看未测试 / 到期'));
      await tester.pump(const Duration(milliseconds: 500));
      final dueChecks = <Map<String, Object?>>[];
      for (final offset in [
        Duration.zero,
        const Duration(minutes: 10) - const Duration(microseconds: 1),
        const Duration(minutes: 10),
        const Duration(days: 1),
        const Duration(days: 7),
      ]) {
        now = base.add(offset);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final expectedSelected = offset >= const Duration(days: 7)
            ? 15
            : offset >= const Duration(days: 1)
            ? 10
            : offset >= const Duration(minutes: 10)
            ? 5
            : 0;
        final expected =
            persisted
                .where(
                  (w) =>
                      w.entry.libraryClass == '主学习' &&
                      !selectedIds.contains(w.entry.id) &&
                      w.isDue(now),
                )
                .length +
            expectedSelected;
        await waitP1d(tester, find.text('共 100 词 · 当前 $expected 词'));
        dueChecks.add({
          'offset_us': offset.inMicroseconds,
          'due_words': expected,
          'selected_due': expectedSelected,
        });
      }
      now = base;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await waitP1d(tester, find.text('共 100 词 · 当前 $untouchedDue 词'));
      final frame = await captureFrame(
        tester,
        Directory(p1dDirectory),
        'learning-fifteen',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      await saveP1d(tester, 'learning-result.json', {
        'pid': pid,
        'db_path': p1dDatabase,
        'evidence_kind': 'real Windows UI, cloned actual 100-word SQLite; test ratings are not personal history',
        'controlled_clock': base.toIso8601String(),
        'ratings': ratings,
        'words_rated': 15,
        'initial_events': initialEvents,
        'final_events': initialEvents + 15,
        'audio': audio,
        'audio_missing_words': missing,
        'due_checks': dueChecks,
        'untouched_due_at_start': untouchedDue,
        'stable_ids_preserved': true,
        'frame': frame,
        'progress_snapshot': (await tester.runAsync(
          () async => snapshotTables(p1dDatabase),
        ))!,
      });
    },
    skip: p1dDirectory.isEmpty,
  );
}
