import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/storage/learning_repository.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/review/review_schedule.dart';

final class VocabularyController extends ChangeNotifier {
  VocabularyController(
    this.repository,
    this.logger, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) => _notify());
  }
  final LearningRepository repository;
  final AppLogger logger;
  final DateTime Function() _clock;
  late final Timer _clockTimer;
  DateTime get nowUtc => _clock().toUtc();
  List<StudyWord> words = const [];
  bool busy = false;
  bool loaded = false;
  String? error;
  String? importMessage;
  bool _disposed = false;

  StudyWord? find(String id) {
    for (final word in words) {
      if (word.entry.id == id) return word;
    }
    return null;
  }

  List<StudyWord> dueWords(DateTime now, {String? libraryClass = '主学习'}) =>
      (words
          .where(
            (word) =>
                (libraryClass == null
                    ? word.entry.libraryClass != '暂缓'
                    : word.entry.libraryClass == libraryClass) &&
                (word.isDue(now) || word.isPronunciationDue(now)),
          )
          .toList()
        ..sort((a, b) {
          DateTime? earliest(StudyWord word) {
            final meaning = word.dueAt;
            final reading = word.pronunciationProgress?.dueAt;
            if (meaning == null) return reading;
            return reading == null || meaning.isBefore(reading)
                ? meaning
                : reading;
          }

          final aDue = earliest(a), bDue = earliest(b);
          if (aDue != null && bDue != null) {
            final order = aDue.compareTo(bDue);
            if (order != 0) return order;
          } else if (aDue != null) {
            return -1;
          } else if (bDue != null) {
            return 1;
          }
          final priority = (a.entry.fields['learning_priority'] ?? 'P2')
              .compareTo(b.entry.fields['learning_priority'] ?? 'P2');
          return priority != 0
              ? priority
              : a.entry.word.compareTo(b.entry.word);
        }));

  Future<bool> refresh() => _perform(() async {});
  Future<bool> importCsv(Future<String?> Function() load) => _perform(() async {
    importMessage = null;
    final text = await load();
    if (text != null) {
      importMessage = (await repository.importCsv(text)).message;
    }
  });
  Future<bool> review(String id, ReviewGrade grade, DateTime at) =>
      _perform(() async {
        final previous = find(id);
        if (previous == null) throw StateError('未找到词条。');
        await repository.recordReview(id, grade, at);
        // The write is acknowledged. Avoid turning a later read failure into a
        // retryable rating, which could otherwise record the same click twice.
        words = List.unmodifiable(
          words.map(
            (word) => word.entry.id != id
                ? word
                : StudyWord(
                    entry: previous.entry,
                    status: grade.name,
                    pronunciationStatus: previous.pronunciationStatus,
                    reviewCount: previous.reviewCount + 1,
                    lastReviewedAt: at.toUtc(),
                    dueAt: ReviewSchedule.nextDue(grade, at),
                    pronunciationProgress: previous.pronunciationProgress,
                  ),
          ),
        );
      }, reload: false);

  Future<bool> _perform(
    Future<void> Function() action, {
    bool reload = true,
  }) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
      if (reload) words = List.unmodifiable(await repository.readWords());
      loaded = true;
      return true;
    } on FormatException catch (e, stack) {
      error = e.message;
      logger.error('Vocabulary validation failed', error: e, stackTrace: stack);
      return false;
    } catch (e, stack) {
      error = '本地数据操作失败，请重试。原有记录已保留。';
      logger.error(
        'Local vocabulary operation failed',
        error: e,
        stackTrace: stack,
      );
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _clockTimer.cancel();
    super.dispose();
  }
}
