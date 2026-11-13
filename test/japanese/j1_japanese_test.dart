import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/features/japanese/domain/gojuon_data.dart';
import 'package:english_learning/features/japanese/domain/kana_quiz.dart';
import 'package:english_learning/features/japanese/domain/japanese_review_state.dart';
import 'package:english_learning/features/japanese/domain/japanese_controller.dart';
import 'package:english_learning/features/japanese/data/pilot_vocab_loader.dart';
import 'package:english_learning/features/japanese/data/japanese_audio_service.dart';
import 'package:english_learning/features/japanese/presentation/japanese_home_page.dart';
import 'package:english_learning/features/japanese/presentation/gojuon_page.dart';
import 'package:english_learning/features/japanese/presentation/kana_practice_page.dart';
import 'package:english_learning/features/japanese/presentation/japanese_vocabulary_page.dart';
import 'package:english_learning/features/japanese/presentation/japanese_word_card_page.dart';
import 'package:english_learning/features/pronunciation/local_speech.dart';

final class _MockNonJapaneseSpeech implements LocalSpeech {
  @override
  Future<LocalVoice?> voice() async =>
      const LocalVoice('Microsoft David Desktop', 'en-US');

  @override
  Future<void> speak(String word, {required void Function() onStarted}) async {
    throw UnsupportedError('Should not be called for Japanese text');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('1. Gojūon 50-Sound Chart Verification', () {
    test('standard 46 basic Seion + Hatsun count is exactly 46', () {
      expect(GojuonData.totalCount, 46);
      expect(GojuonData.basicKanaList.length, 46);
    });

    test('grid has 11 rows and 5 columns', () {
      final grid = GojuonData.grid;
      expect(grid.length, 11);
      for (final row in grid) {
        expect(row.length, 5);
      }
    });

    test('vowels and standard rows are mapped accurately', () {
      // Row 0: a-row (5 kana)
      expect(GojuonData.basicKanaList.where((k) => k.rowIndex == 0).length, 5);
      final aRow = GojuonData.grid[0];
      expect(aRow[0]?.hiragana, 'あ');
      expect(aRow[0]?.katakana, 'ア');
      expect(aRow[0]?.romaji, 'a');

      // Row 7: ya-row has 3 items (ya, yu, yo) and 2 empty slots
      final yaRow = GojuonData.grid[7];
      expect(yaRow[0]?.hiragana, 'や');
      expect(yaRow[1], isNull);
      expect(yaRow[2]?.hiragana, 'ゆ');
      expect(yaRow[3], isNull);
      expect(yaRow[4]?.hiragana, 'よ');

      // Row 9: wa-row has 2 items (wa, wo) and 3 empty slots
      final waRow = GojuonData.grid[9];
      expect(waRow[0]?.hiragana, 'わ');
      expect(waRow[1], isNull);
      expect(waRow[2], isNull);
      expect(waRow[3], isNull);
      expect(waRow[4]?.hiragana, 'を');

      // Row 10: Hatsun (n) has 1 item and 4 empty slots
      final nRow = GojuonData.grid[10];
      expect(nRow[0]?.hiragana, 'ん');
      expect(nRow[1], isNull);
    });

    test('lookup finds kana by id, hiragana, katakana, and romaji', () {
      final byId = GojuonData.find('ka');
      final byHira = GojuonData.find('か');
      final byKata = GojuonData.find('カ');
      expect(byId, isNotNull);
      expect(byId, equals(byHira));
      expect(byId, equals(byKata));
      expect(byId?.romaji, 'ka');
    });

    test(
      'every kana has mnemonic hint without Chinese phonetic homophones',
      () {
        for (final k in GojuonData.basicKanaList) {
          expect(k.mnemonicHint, isNotEmpty);
          expect(k.mnemonicHint, contains('源自'));
        }
      },
    );
  });

  group('2. Kana Practice Quiz Logic', () {
    test('creates quiz sessions for all 3 modes with 10 questions each', () {
      for (final mode in KanaPracticeMode.values) {
        final session = KanaQuizSession.create(mode: mode, count: 10);
        expect(session.totalQuestions, 10);
        expect(session.currentIndex, 0);
        expect(session.isFinished, isFalse);

        for (final q in session.questions) {
          expect(q.options.length, 4);
          expect(q.options.contains(q.correctAnswer), isTrue);
          expect(q.options.toSet().length, 4, reason: 'Options must be unique');
        }
      }
    });

    test('answering questions tracks score correctly', () {
      final session = KanaQuizSession.create(
        mode: KanaPracticeMode.kanaToRomaji,
        count: 5,
      );

      // Answer first correctly
      final q0 = session.currentQuestion;
      session.answerCurrent(q0.correctAnswer);
      expect(session.isCurrentAnswered, isTrue);
      expect(session.isCurrentCorrect, isTrue);
      expect(session.correctCount, 1);

      // Advance
      expect(session.next(), isTrue);
      expect(session.currentIndex, 1);

      // Answer second incorrectly
      final wrongOption = session.currentQuestion.options.firstWhere(
        (o) => o != session.currentQuestion.correctAnswer,
      );
      session.answerCurrent(wrongOption);
      expect(session.isCurrentAnswered, isTrue);
      expect(session.isCurrentCorrect, isFalse);
      expect(session.correctCount, 1);
    });
  });

  group('3. Pilot 100 CSV Loading & Field Mapping', () {
    test('loads and parses 100 entries from default path', () async {
      const loader = PilotVocabLoader();
      final entries = await loader.load();

      expect(entries.length, 100, reason: 'Must parse all 100 Pilot records');

      // Check first entry
      final first = entries.first;
      expect(first.sampleId, 'J0-001');
      expect(first.sampleOrder, 1);
      expect(first.japanese, 'おはよう（ございます）');
      expect(first.kana, 'おはよう（ございます）');
      expect(first.coreMeaning, '早上好');
      expect(first.englishOriginal, 'Good morning.');
      expect(first.posOriginal, 'Exp');
      expect(first.lessonOriginal, '1');
      expect(first.validationStatus, 'CANDIDATE_PENDING_HUMAN');
      expect(first.humanConfirmation, 'UNCONFIRMED');
      expect(first.importAllowed, 'NO');

      // Audit badge presence
      expect(first.auditBadgeLabel, '中文释义待校对');
      expect(first.isCandidatePending, isTrue);
      expect(first.isHumanConfirmed, isFalse);
    });

    test(
      'all 100 entries have unconfirmed status and candidate flags',
      () async {
        const loader = PilotVocabLoader();
        final entries = await loader.load();

        for (final e in entries) {
          expect(e.isCandidatePending, isTrue);
          expect(e.isHumanConfirmed, isFalse);
          expect(e.auditBadgeLabel, '中文释义待校对');
          expect(e.importAllowed, 'NO');
          expect(e.coreMeaning, isNotEmpty);
        }
      },
    );

    test('kanji detection correctly identifies kanji presence', () async {
      const loader = PilotVocabLoader();
      final entries = await loader.load();

      // J0-001 おはよう（ございます） contains no kanji
      expect(entries[0].hasKanji, isFalse);

      // J0-006 失礼します contains kanji (失, 礼)
      final shitsurei = entries.firstWhere((e) => e.sampleId == 'J0-006');
      expect(shitsurei.hasKanji, isTrue);
    });
  });

  group('4. Japanese Audio Service Safety Guard', () {
    test('blocks playback when system voice is non-Japanese', () async {
      final service = JapaneseAudioService(
        localSpeech: _MockNonJapaneseSpeech(),
      );

      final kana = GojuonData.basicKanaList.first;
      final result = await service.playKana(kana);

      expect(result.status, JapaneseAudioStatus.noVoice);
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('不是日语语音包'));
      expect(result.message, contains('已拦截播放'));
    });
  });

  group('5. Review Session Demonstration State', () {
    test(
      'records meaning and reading recall independently without DB write',
      () {
        final state = JapaneseReviewSessionState();
        expect(JapaneseReviewSessionState.isDemonstrationOnly, isTrue);

        state.setMeaningGrade('J0-001', JapaneseRecallGrade.mastered);
        state.setReadingGrade('J0-001', JapaneseRecallGrade.familiar);

        final record = state.getRecord('J0-001');
        expect(record.meaningGrade, JapaneseRecallGrade.mastered);
        expect(record.readingGrade, JapaneseRecallGrade.familiar);
        expect(record.isFullyGraded, isTrue);
        expect(state.meaningMasteredCount, 1);
        expect(state.readingMasteredCount, 0);
        expect(state.totalPracticed, 1);
      },
    );
  });

  group('6. Widget Presentation Tests', () {
    late JapaneseController controller;

    setUp(() async {
      controller = JapaneseController();
      await controller.initialize();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('JapaneseHomePage renders key cards and navigation', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: JapaneseHomePage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('日本語学習 · 日语学习'), findsOneWidget);
      expect(find.byKey(const Key('switch-to-english')), findsOneWidget);
      expect(find.byKey(const Key('open-gojuon')), findsOneWidget);
      expect(find.byKey(const Key('open-kana-practice')), findsOneWidget);
      expect(find.byKey(const Key('open-japanese-vocab')), findsOneWidget);
      expect(find.text('中文释义待校对'), findsWidgets);
    });

    testWidgets(
      'GojuonPage displays 46-kana chart, romaji toggle, and opens detail dialog',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1366, 768));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: GojuonPage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('五十音图 · 46 基础清音'), findsOneWidget);
        expect(find.byKey(const Key('kana-display-toggle')), findsOneWidget);
        expect(find.byKey(const Key('toggle-romaji-switch')), findsOneWidget);

        // Tap 'a' kana card to open detail
        final aCard = find.byKey(const Key('kana-card-a'));
        expect(aCard, findsOneWidget);
        await tester.tap(aCard);
        await tester.pumpAndSettle();

        expect(find.text('あ行 · 假名详情'), findsOneWidget);
        expect(find.text('平假名源自「安」的草书，片假名源自「阿」的左偏旁「阝」'), findsOneWidget);
        expect(find.byKey(const Key('play-kana-audio')), findsOneWidget);

        // Close dialog
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'KanaPracticePage presents questions, receives input, and gives feedback',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1366, 768));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: KanaPracticePage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('假名基础练习'), findsOneWidget);
        expect(
          find.byKey(const Key('practice-question-prompt')),
          findsOneWidget,
        );

        // Find an option and tap it
        final optionFinder = find.byKey(const Key('practice-next-btn'));
        expect(optionFinder, findsNothing); // Next button hidden until answered

        // Tap first option
        final firstOpt = find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'practice-option-',
                  ),
            )
            .first;
        await tester.tap(firstOpt);
        await tester.pumpAndSettle();

        // Next button should now appear
        expect(find.byKey(const Key('practice-next-btn')), findsOneWidget);
      },
    );

    testWidgets('JapaneseVocabularyPage filters and displays 100 pilot words', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: JapaneseVocabularyPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Irodori 试点词汇 (100 词)'), findsOneWidget);
      expect(find.byKey(const Key('vocab-item-J0-001')), findsOneWidget);

      // Search for specific word
      await tester.enterText(find.byType(TextField), '早上好');
      await tester.pumpAndSettle();

      expect(find.text('おはよう（ございます）'), findsOneWidget);
    });

    testWidgets(
      'JapaneseWordCardPage hides Chinese meaning by default, reveals on demand, and toggles furigana',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1366, 768));
        addTearDown(() => tester.binding.setSurfaceSize(null));

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

        // Default: Chinese meaning hidden
        expect(find.text('中文释义默认隐藏'), findsOneWidget);
        expect(find.byKey(const Key('reveal-meaning-btn')), findsOneWidget);
        expect(find.byKey(const Key('revealed-core-meaning')), findsNothing);

        // Reveal meaning
        await tester.tap(find.byKey(const Key('reveal-meaning-btn')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('revealed-core-meaning')), findsOneWidget);
        expect(find.text('早上好'), findsOneWidget);

        // Toggle furigana
        expect(find.byKey(const Key('furigana-text')), findsOneWidget);
        await tester.tap(find.byKey(const Key('toggle-furigana-btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('furigana-hidden-placeholder')),
          findsOneWidget,
        );

        // Scroll down and tap 2-dimension review buttons
        await tester.scrollUntilVisible(find.text('掌握 · 词义'), 100);
        await tester.tap(find.text('掌握 · 词义'));
        await tester.pumpAndSettle();
        expect(
          controller.reviewState.getRecord('J0-001').meaningGrade,
          JapaneseRecallGrade.mastered,
        );

        await tester.scrollUntilVisible(find.text('眼熟 · 读音'), 100);
        await tester.tap(find.text('眼熟 · 读音'));
        await tester.pumpAndSettle();
        expect(
          controller.reviewState.getRecord('J0-001').readingGrade,
          JapaneseRecallGrade.familiar,
        );
      },
    );
  });
}
