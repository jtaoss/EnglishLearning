import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/storage/learning_repository.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/pronunciation/local_speech.dart';
import 'package:english_learning/features/pronunciation/pronunciation_content.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

import '../p1a/fixtures.dart' show encodeEntries, entryFields;
import '../p1b/pronunciation_test.dart'
    show MemoryPronunciationStore, ControlledPlayer, FakeAudioCache, content;
import '../p1c/support.dart' show MemoryCredentials, testAccount, noDelay;
import '../support/memory_settings_repository.dart';

class _TestDesktopRepo implements LearningRepository, NotionSyncStore {
  _TestDesktopRepo(this.words);
  final List<StudyWord> words;

  @override
  Future<List<StudyWord>> readWords() async => List.of(words);

  @override
  Future<ImportResult> importCsv(String csv) async =>
      ImportResult(0, 0, words.length);

  @override
  Future<void> recordReview(String id, ReviewGrade grade, DateTime at) async {
    final index = words.indexWhere((w) => w.entry.id == id);
    if (index < 0) return;
    final old = words[index];
    words[index] = StudyWord(
      entry: old.entry,
      status: grade.name,
      pronunciationStatus: old.pronunciationStatus,
      reviewCount: old.reviewCount + 1,
      lastReviewedAt: at,
      dueAt: ReviewSchedule.nextDue(grade, at),
      pronunciationProgress: old.pronunciationProgress,
    );
  }

  @override
  Future<int> reviewEventCount() async => 12;

  @override
  Future<void> close() async {}

  @override
  Future<NotionSyncState> readNotionState(String sourceId) async =>
      NotionSyncState(
        linkedWords: words.length,
        syncedAt: DateTime.utc(2026, 11, 11, 6, 30),
        watermark: DateTime.utc(2026, 11, 11, 6, 30),
      );

  @override
  Future<ImportResult> applyNotionBatch({
    required String sourceId,
    required List<NotionWord> words,
    required DateTime? expectedWatermark,
    required DateTime? watermark,
    required DateTime syncedAt,
  }) async => ImportResult(0, 0, this.words.length);
}

class _DesktopFakeSpeech implements LocalSpeech {
  @override
  Future<LocalVoice?> voice() async =>
      const LocalVoice('Microsoft Zira Desktop', 'en-US');

  @override
  Future<void> speak(String word, {required void Function() onStarted}) async {
    onStarted();
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

StudyWord _makeWord({
  required String id,
  required String word,
  required String meaning,
  required String libraryClass,
  required String status,
  required String exampleEn,
  required String exampleZh,
  DateTime? dueAt,
}) {
  final fields = {
    ...entryFields(id: id, word: word, library: libraryClass, meaning: meaning),
    'part_of_speech': 'n. / v.',
    'syllables': 'chal-lenge',
    'stress': "'chal-lenge（重音在第一音节）",
    'phonics_note': 'ch 读清辅音；a 在重读闭音节读短元音；末尾 ge 读软辅音。',
    'reading_review_status': '自然拼读提示已人工复核',
    'example_en': exampleEn,
    'example_zh': exampleZh,
    'usage_note': '常用于 face a challenge / challenge the assumption 等搭配。',
    'learning_priority': '高',
  };
  return StudyWord(
    entry: VocabularyEntry(fields),
    status: status,
    pronunciationStatus: '未测试',
    reviewCount: status == 'untested' ? 0 : 2,
    dueAt: dueAt,
  );
}

void main() {
  final now = DateTime.utc(2026, 11, 11, 8, 0);

  List<StudyWord> buildSampleWords() => [
    _makeWord(
      id: 'word-challenge',
      word: 'challenge',
      meaning: '挑战；质疑；向……提出挑战',
      libraryClass: '主学习',
      status: 'familiar',
      exampleEn: 'Learning long academic vocabulary is a rewarding challenge.',
      exampleZh: '学习较长的学术词汇是一项值得付出的挑战。',
      dueAt: now.subtract(const Duration(hours: 2)),
    ),
    _makeWord(
      id: 'word-long',
      word: 'counterrevolutionaries',
      meaning:
          '反革命分子；反对重大社会变革或学术范式更替的保守派人物（用于检验超长英文单词与多行中文释义在 Windows 缩放下的排版表现）',
      libraryClass: '主学习',
      status: 'untested',
      exampleEn: 'Historians documented how counterrevolutionaries attempted to restore the previous institutional order across multiple regions.',
      exampleZh: '历史学家记录了反对变革的势力如何试图在多个地区恢复原有的制度秩序。',
    ),
    _makeWord(
      id: 'word-extension',
      word: 'acknowledgement',
      meaning: '承认；致谢；确认收悉',
      libraryClass: '扩展',
      status: 'mastered',
      exampleEn: 'Please send a written acknowledgement upon receipt.',
      exampleZh: '收到后请发送书面确认函。',
      dueAt: now.add(const Duration(days: 5)),
    ),
  ];

  for (final size in const [
    Size(1366, 768),
    Size(1920, 1080),
    Size(960, 640),
  ]) {
    for (final scale in const [1.0, 1.25, 1.5]) {
      for (final theme in const ['light', 'dark']) {
        testWidgets(
          'Windows desktop layout ${size.width.toInt()}x${size.height.toInt()} '
          'at ${(scale * 100).toInt()}% scale in $theme mode has no overflow',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );

            final words = buildSampleWords();
            final repo = _TestDesktopRepo(words);
            final pronStore = MemoryPronunciationStore();
            final pronServices = PronunciationServices(
              store: pronStore,
              logger: AppLogger(),
              catalogLoader: () async =>
                  PronunciationCatalog([content('autumn')]),
              cache: FakeAudioCache(),
              playerFactory: ControlledPlayer.new,
              speechFactory: _DesktopFakeSpeech.new,
            );
            final notionService = NotionSyncService(
              store: repo,
              credentials: MemoryCredentials(testAccount()),
              api: NotionReadApi(
                MockClient((_) async => throw StateError('offline')),
                delay: noDelay,
              ),
              loadScope: () async => NotionScope(
                encodeEntries(words.map((w) => w.entry.fields).toList()),
              ),
              clock: () => now,
            );

            await tester.pumpWidget(
              EnglishLearningApp(
                repository: MemorySettingsRepository(stored: theme),
                logger: AppLogger(),
                config: AppConfig.developmentPreset(),
                learningRepository: repo,
                clock: () => now,
                pronunciationServices: pronServices,
                notionService: notionService,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            // 1. Home page checks
            expect(find.byKey(const Key('start-due-review')), findsOneWidget);
            expect(find.byKey(const Key('open-vocabulary')), findsOneWidget);

            // 2. Navigate to long word review page
            GoRouter.of(tester.element(find.byType(Scaffold).first))
                .push(AppRouter.wordPath('word-long'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('counterrevolutionaries'), findsOneWidget);
            expect(find.byKey(const Key('meaning')), findsNothing);

            // Confirm self-reading & reveal meaning
            await tester.ensureVisible(
              find.byKey(const Key('confirm-self-reading')),
            );
            await tester.tap(find.byKey(const Key('confirm-self-reading')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byKey(const Key('phonics-note')), findsOneWidget);

            await tester.ensureVisible(find.byKey(ReviewPage.revealKey));
            await tester.tap(find.byKey(ReviewPage.revealKey));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byKey(const Key('meaning')), findsOneWidget);

            // Grade meaning
            final gradeFamiliar = find.byKey(
              ReviewPage.gradeKey(ReviewGrade.familiar),
            );
            await tester.ensureVisible(gradeFamiliar);
            await tester.tap(gradeFamiliar);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byKey(const Key('review-saved')), findsOneWidget);

            // 3. Navigate to Vocabulary page
            GoRouter.of(tester.element(find.byType(Scaffold).first))
                .go(AppRouter.vocabulary);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byKey(const Key('vocabulary-search')), findsOneWidget);
            expect(find.text('共 3 词 · 当前 2 词'), findsOneWidget);

            // 4. Navigate to Settings page
            GoRouter.of(tester.element(find.byType(Scaffold).first))
                .push(AppRouter.settings);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('Theme'), findsOneWidget);

            // 5. Navigate to Notion Sync page
            GoRouter.of(tester.element(find.byType(Scaffold).first))
                .go(AppRouter.notion);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byKey(const Key('notion-sync')), findsOneWidget);
          },
        );
      }
    }
  }
}
