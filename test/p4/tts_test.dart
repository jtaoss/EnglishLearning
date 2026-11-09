import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/core/storage/learning_repository.dart';
import 'package:english_learning/features/pronunciation/local_speech.dart';
import 'package:english_learning/features/pronunciation/pronunciation_content.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';

import '../p1a/learning_flow_test.dart' show MemoryLearningRepository;
import '../p1b/pronunciation_test.dart' show MemoryPronunciationStore;

class _Speech implements LocalSpeech {
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<LocalVoice?> voice() async =>
      const LocalVoice('Test Microsoft Desktop', 'en-US');
  @override
  Future<void> speak(String word, {required void Function() onStarted}) async {
    if (fail) throw StateError('output failed');
    pending = Completer<void>();
    onStarted();
    await pending!.future;
  }

  @override
  Future<void> stop() async {
    if (!(pending?.isCompleted ?? true)) {
      pending!.completeError(StateError('interrupted'));
    }
  }

  @override
  Future<void> dispose() => stop();
}

class _Repository implements LearningRepository {
  List<StudyWord> words = [];
  int events = 0;
  @override
  Future<List<StudyWord>> readWords() async => List.of(words);
  @override
  Future<ImportResult> importCsv(String csv) async =>
      const ImportResult(0, 0, 0);
  @override
  Future<int> reviewEventCount() async => events;
  @override
  Future<void> close() async {}
  @override
  Future<void> recordReview(String id, ReviewGrade grade, DateTime at) async {
    events++;
    words = words
        .map(
          (w) => w.entry.id != id
              ? w
              : StudyWord(
                  entry: w.entry,
                  status: grade.name,
                  pronunciationStatus: w.pronunciationStatus,
                  reviewCount: w.reviewCount + 1,
                  lastReviewedAt: at,
                  dueAt: ReviewSchedule.nextDue(grade, at),
                  pronunciationProgress: w.pronunciationProgress,
                ),
        )
        .toList();
  }
}

void main() {
  final csv = File('assets/vocabulary/reviewed500.csv').readAsStringSync();
  final entry = VocabularyCsv.parse(csv).singleWhere((e) => e.word == 'about');
  testWidgets(
    'failed and stopped TTS cannot rate pronunciation; meaning familiar remains independent',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repository();
      repo.words = [
        StudyWord(
          entry: entry,
          status: 'untested',
          pronunciationStatus: '未测试',
          reviewCount: 0,
        ),
      ];
      final controller = VocabularyController(repo, AppLogger());
      var disposed = false;
      addTearDown(() {
        if (!disposed) controller.dispose();
      });
      await controller.refresh();
      final store = MemoryPronunciationStore(), speech = _Speech();
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewPage(
            entryId: entry.id,
            controller: controller,
            pronunciationServices: PronunciationServices(
              store: store,
              logger: AppLogger(),
              catalogLoader: () async => PronunciationCatalog([]),
              speechFactory: () => speech,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-self-reading')));
      await tester.pumpAndSettle();
      final rating = find.byKey(const ValueKey('pronunciation-grade-familiar'));
      expect(tester.widget<OutlinedButton>(rating).onPressed, isNull);
      speech.fail = true;
      await tester.tap(find.byKey(const Key('play-local-tts')));
      await tester.pumpAndSettle();
      expect(store.writes, 0);
      expect(tester.widget<OutlinedButton>(rating).onPressed, isNull);
      await tester.tap(find.byKey(const Key('reveal-answer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-familiar')));
      await tester.pumpAndSettle();
      expect(controller.find(entry.id)!.status, 'familiar');
      expect(store.writes, 0);
      speech.fail = false;
      await tester.tap(find.byKey(const Key('play-local-tts')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('stop-local-tts')));
      await tester.pumpAndSettle();
      expect(store.writes, 0);
      expect(tester.widget<OutlinedButton>(rating).onPressed, isNull);
      await tester.tap(find.byKey(const Key('play-local-tts')));
      await tester.pump();
      speech.pending!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(rating).onPressed, isNotNull);
      await tester.tap(rating);
      await tester.pumpAndSettle();
      expect(store.writes, 1);
      expect(controller.find(entry.id)!.status, 'familiar');
      await tester.tap(rating);
      await tester.pumpAndSettle();
      expect(store.writes, 1);
      await tester.tap(find.text('再练习一次'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-self-reading')));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(rating).onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      disposed = true;
    },
  );
  test('TTS source persists with grade and due date, duplicate submission does not duplicate events', () async {
    final folder = await Directory.systemTemp.createTemp('tts_source_test_');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}/isolated.sqlite3';
    var repo = await SqliteLearningRepository.open(path);
    await repo.importCsv(csv);
    final at = DateTime.utc(2026, 11, 9);
    const source = 'windows-tts:sapi:en-US:Test Microsoft Desktop';
    for (var i = 0; i < 2; i++) {
      await repo.recordPronunciation(
        entryId: entry.id,
        grade: PronunciationGrade.familiar,
        audioAssetId: source,
        attemptId: 'one-attempt',
        at: at,
      );
    }
    await repo.close();
    repo = await SqliteLearningRepository.open(path);
    addTearDown(repo.close);
    final p = await repo.readPronunciation(entry.id);
    expect(p.sourceId, source);
    expect(p.sourceLabel, contains('合成语音'));
    expect(p.grade, PronunciationGrade.familiar);
    expect(p.dueAt, at.add(const Duration(days: 1)));
    expect(
      (await repo.readWords())
          .singleWhere((w) => w.entry.id == entry.id)
          .status,
      'untested',
    );
    expect(await repo.reviewEventCount(), 0);
  });
  test('due review precedes untested words even if new words have higher content priority', () async {
    final repo = MemoryLearningRepository();
    final controller = VocabularyController(repo, AppLogger());
    addTearDown(controller.dispose);
    final a = VocabularyCsv.parse(csv).first;
    final b = VocabularyCsv.parse(csv).last;
    final now = DateTime.utc(2026, 11, 9);
    repo.words = [
      StudyWord(
        entry: a,
        status: 'untested',
        pronunciationStatus: '未测试',
        reviewCount: 0,
      ),
      StudyWord(
        entry: b,
        status: 'forgotten',
        pronunciationStatus: '未测试',
        reviewCount: 1,
        dueAt: now.subtract(const Duration(minutes: 1)),
      ),
    ];
    await controller.refresh();
    expect(controller.dueWords(now, libraryClass: null).first.entry.id, b.id);
  });
}
