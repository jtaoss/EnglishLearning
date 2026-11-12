import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/review/study_queue.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12, 4);

  test(
    'new words follow the book sections and stay stable inside a section',
    () {
      final words = [
        _word(
          'low-late',
          'zeta',
          BookStudyOrder.low,
          page: '500',
          library: '扩展',
        ),
        _word('basic-b', 'beta', BookStudyOrder.basic, page: '651'),
        _word('mid', 'middle', BookStudyOrder.medium, page: '300'),
        _word(
          'occasional',
          'odd',
          BookStudyOrder.occasional,
          page: '600',
          library: '扩展',
        ),
        _word('high-b', 'second', BookStudyOrder.high, page: '14'),
        _word('high-a', 'first', BookStudyOrder.high, page: '13'),
        _word('same-page-z', 'zeta', BookStudyOrder.high, page: '13'),
        _word('same-page-a', 'alpha', BookStudyOrder.high, page: '13'),
        _word('supplement', 'extra', BookStudyOrder.supplement, page: '701'),
        _word('low-early', 'early', BookStudyOrder.low, page: '452'),
      ].reversed.toList();

      final order = orderedDueWords(
        words,
        now,
        libraryClass: null,
      ).map((word) => word.entry.id).toList();

      expect(order, [
        'same-page-a',
        'high-a',
        'same-page-z',
        'high-b',
        'basic-b',
        'mid',
        'low-early',
        'low-late',
        'occasional',
        'supplement',
      ]);
      expect(
        orderedDueWords(
          words.reversed.toList(),
          now,
          libraryClass: null,
        ).map((word) => word.entry.id),
        order,
      );
    },
  );

  test('a due studied word stays ahead of high-frequency new words', () {
    final due = _word(
      'old',
      'old',
      BookStudyOrder.occasional,
      status: 'forgotten',
      reviewCount: 2,
      dueAt: now.subtract(const Duration(minutes: 5)),
    );
    final fresh = _word('new', 'new', BookStudyOrder.high, page: '1');
    final waiting = _word(
      'waiting',
      'waiting',
      BookStudyOrder.high,
      status: 'mastered',
      reviewCount: 1,
      dueAt: now.add(const Duration(days: 3)),
    );
    final reading = _word(
      'reading',
      'reading',
      BookStudyOrder.low,
      pronunciation: PronunciationProgress(
        grade: PronunciationGrade.needsPractice,
        assessedAt: now.subtract(const Duration(minutes: 30)),
      ),
    );
    final before = {
      for (final word in [due, fresh, waiting, reading])
        word.entry.id: (word.status, word.dueAt, word.reviewCount),
    };

    final queue = orderedDueWords(
      [fresh, waiting, reading, due],
      now,
      libraryClass: null,
    );

    expect(queue.map((word) => word.entry.id), ['reading', 'old', 'new']);
    expect(queue.map((word) => word.entry.id), isNot(contains('waiting')));
    for (final word in [due, fresh, waiting, reading]) {
      expect((
        word.status,
        word.dueAt,
        word.reviewCount,
      ), before[word.entry.id]);
    }
  });

  test('formal library queue covers every accepted word once, before any batch cut', () {
    final entries = VocabularyCsv.parse(
      File('docs/p5a/public/formal_learning_vocabulary.csv').readAsStringSync(),
    );
    expect(entries.length, VocabularyCsv.maxEntries);
    expect(entries.map((entry) => entry.id).toSet(), hasLength(entries.length));
    final counts = <String, int>{};
    for (final entry in entries) {
      final category = entry.fields['book_category']!;
      counts[category] = (counts[category] ?? 0) + 1;
    }
    expect(counts.keys, {
      BookStudyOrder.high,
      BookStudyOrder.basic,
      BookStudyOrder.medium,
      BookStudyOrder.low,
      BookStudyOrder.occasional,
    });
    expect(counts[BookStudyOrder.supplement] ?? 0, 0);

    final words = [
      for (final entry in entries.reversed)
        StudyWord(
          entry: entry,
          status: 'untested',
          pronunciationStatus: '未测试',
          reviewCount: 0,
        ),
    ];
    final queue = orderedDueWords(words, now, libraryClass: null);
    expect(queue, hasLength(entries.length));
    expect(
      queue.map((word) => word.entry.id).toSet(),
      hasLength(entries.length),
    );

    var previousRank = -1;
    var previousPage = -1;
    String? previousWord;
    for (final word in queue) {
      final rank = BookStudyOrder.rank(word.entry.fields['book_category']);
      final page = BookStudyOrder.sourcePage(word);
      expect(rank, greaterThanOrEqualTo(previousRank));
      if (rank == previousRank) {
        expect(page, greaterThanOrEqualTo(previousPage));
        if (page == previousPage) {
          expect(
            word.entry.word.compareTo(previousWord!),
            greaterThanOrEqualTo(0),
          );
        }
      }
      previousRank = rank;
      previousPage = page;
      previousWord = word.entry.word;
    }
    expect(
      BookStudyOrder.rank(queue.first.entry.fields['book_category']),
      lessThan(BookStudyOrder.rank(queue.last.entry.fields['book_category'])),
    );

    final seen = <String>{};
    var cursor = queue;
    while (cursor.isNotEmpty) {
      final batch = cursor.take(100).toList();
      expect(batch, isNotEmpty);
      expect(
        seen.intersection(batch.map((word) => word.entry.id).toSet()),
        isEmpty,
      );
      seen.addAll(batch.map((word) => word.entry.id));
      cursor = cursor.skip(batch.length).toList();
      expect(
        orderedDueWords(
          words.where((word) => !seen.contains(word.entry.id)).toList(),
          now,
          libraryClass: null,
        ).map((word) => word.entry.id),
        cursor.map((word) => word.entry.id),
      );
    }
    expect(seen, hasLength(entries.length));
    expect(
      entries
          .map((entry) => entry.word.toLowerCase())
          .where((word) => word.contains('advance')),
      isNotEmpty,
    );
  });

  test(
    '100, 200 and 500 sample prefixes stay on the accepted historical order',
    () {
      final formal = File('docs/p5a/public/formal_learning_vocabulary.csv')
          .readAsStringSync();
      final historical = File('assets/vocabulary/reviewed500.csv')
          .readAsStringSync();
      final scope = NotionScope.withHistoricalPrefix(formal, historical);
      final reviewed = VocabularyCsv.parse(historical);
      for (final size in [100, 200, 500]) {
        expect(
          scope.take(size).entries.map((entry) => entry.id),
          reviewed.take(size).map((entry) => entry.id),
        );
      }
      expect(
        scope.take(VocabularyCsv.maxEntries).entries,
        hasLength(VocabularyCsv.maxEntries),
      );
    },
  );

  test(
    'an isolated database keeps queue order and saved ratings after restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'english_p6_order_',
      );
      final path = '${directory.path}/learning.sqlite3';
      final csv = [
        VocabularyCsv.columns.join(','),
        _csv('SG25-low', 'lowword', BookStudyOrder.low, '452'),
        _csv('SG25-high', 'highword', BookStudyOrder.high, '13'),
        _csv('SG25-basic', 'basicword', BookStudyOrder.basic, '651'),
      ].join('\n');

      var repository = await SqliteLearningRepository.open(path);
      await repository.importCsv(csv);
      var loaded = await repository.readWords();
      expect(
        orderedDueWords(
          loaded,
          now,
          libraryClass: null,
        ).map((word) => word.entry.word),
        ['highword', 'basicword', 'lowword'],
      );
      await repository.recordReview('SG25-high', ReviewGrade.mastered, now);
      final highBeforeClose = (await repository.readWords()).singleWhere(
        (word) => word.entry.id == 'SG25-high',
      );
      await repository.close();

      repository = await SqliteLearningRepository.open(path);
      loaded = await repository.readWords();
      final high = loaded.singleWhere((word) => word.entry.id == 'SG25-high');
      final basic = loaded.singleWhere((word) => word.entry.id == 'SG25-basic');
      expect(high.status, 'mastered');
      expect(high.reviewCount, 1);
      expect(high.dueAt, highBeforeClose.dueAt);
      expect(basic.status, 'untested');
      expect(basic.reviewCount, 0);
      expect(basic.dueAt, isNull);
      expect(
        orderedDueWords(
          loaded,
          now,
          libraryClass: null,
        ).map((word) => word.entry.id),
        ['SG25-basic', 'SG25-low'],
      );
      await repository.close();
      await directory.delete(recursive: true);
    },
  );
}

StudyWord _word(
  String id,
  String word,
  String category, {
  String page = '1',
  String library = '主学习',
  String status = 'untested',
  int reviewCount = 0,
  DateTime? dueAt,
  PronunciationProgress? pronunciation,
}) {
  return StudyWord(
    entry: VocabularyEntry({
      'entry_id': id,
      'word': word,
      'meaning_zh': '义',
      'book_category': category,
      'source_file': '2025考研英语词汇闪过.pdf',
      'source_id': 'src',
      'source_pdf_pages': page,
      'source_index_pages': '1',
      'book_verification': '已核验',
      'meaning_review_status': '待确认',
      'pets2015_status': '待核实',
      'pets2025_status': '待核实',
      'library_class': library,
      'learning_priority': library == '扩展' ? 'P2' : 'P1',
    }),
    status: status,
    pronunciationStatus: '未测试',
    reviewCount: reviewCount,
    dueAt: dueAt,
    pronunciationProgress: pronunciation,
  );
}

String _csv(String id, String word, String category, String page) =>
    '$id,$word,义,$category,2025考研英语词汇闪过.pdf,src,$page,1,已核验,待确认,待核实,待核实,主学习';
