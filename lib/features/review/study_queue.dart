import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';

/// Learning order for the accepted book sections in `book_category`.
///
/// The stored labels come from the formal vocabulary. 基础词 is the book
/// section the study stages call 简单词. 主学习 and 扩展 are not used here.
abstract final class BookStudyOrder {
  static const high = '高频词';
  static const basic = '基础词';
  static const medium = '中频词';
  static const low = '低频词';
  static const occasional = '偶考词';
  static const supplement = '补充词';

  static int rank(String? category) => switch (category) {
    high => 0,
    basic => 1,
    medium => 2,
    low => 3,
    occasional => 4,
    supplement => 5,
    _ => 6,
  };

  static String stageLabel(String? category) => switch (category) {
    high => '考研高频词',
    basic => '简单词',
    medium => '考研中频词',
    low => '考研低频词',
    occasional => '偶考词',
    supplement => '补充词',
    null || '' => '未分类',
    _ => category,
  };

  /// First page number in `source_pdf_pages`. Missing pages sort last.
  static int sourcePage(StudyWord word) {
    final raw = word.entry.fields['source_pdf_pages'] ?? '';
    final match = RegExp(r'\d+').firstMatch(raw);
    if (match == null) return 1 << 30;
    return int.parse(match.group(0)!);
  }
}

/// A studied word, or a pronunciation item already given a due time.
bool isScheduledReview(StudyWord word, DateTime now) =>
    word.status != 'untested' ||
    word.reviewCount > 0 ||
    word.isPronunciationDue(now);

/// True only when a non-deferred studied word has reached its scheduled meaning
/// review timestamp. Untested new words are never counted as due reviews.
bool isMeaningReviewDue(StudyWord word, DateTime now) =>
    word.entry.libraryClass != '暂缓' &&
    (word.status != 'untested' || word.reviewCount > 0) &&
    word.isDue(now);

/// True when a non-deferred word has been graded as `'forgotten'` (`遗忘`) or
/// `'familiar'` (`眼熟`) in real learning records.
bool isWeakMeaningWord(StudyWord word) =>
    word.entry.libraryClass != '暂缓' &&
    (word.status == 'forgotten' || word.status == 'familiar');

/// True when `reviewedAt` falls within the same local calendar day as `now`.
bool isReviewedOnLocalDay(DateTime? reviewedAt, DateTime now) {
  if (reviewedAt == null) return false;
  final localReviewed = reviewedAt.toLocal();
  final localNow = now.toLocal();
  return localReviewed.year == localNow.year &&
      localReviewed.month == localNow.month &&
      localReviewed.day == localNow.day;
}

/// True when a non-deferred word has a real pronunciation assessment that needs
/// practice or is due for pronunciation review. Unassessed words return false.
bool isPronunciationWeakOrDue(StudyWord word, DateTime now) {
  if (word.entry.libraryClass == '暂缓') return false;
  if (word.isPronunciationDue(now)) return true;
  final grade = word.pronunciationProgress?.grade;
  if (grade == PronunciationGrade.needsPractice ||
      grade == PronunciationGrade.familiar) {
    return true;
  }
  return word.pronunciationStatus == '再练习' ||
      word.pronunciationStatus == '基本会读' ||
      word.pronunciationStatus == '基本掌握';
}

/// Due reviews stay ahead of every untested word. New words are ordered by
/// the book section before any caller takes the first item.
int compareStudyQueue(StudyWord a, StudyWord b, DateTime now) {
  final aReview = isScheduledReview(a, now);
  final bReview = isScheduledReview(b, now);
  if (aReview != bReview) return aReview ? -1 : 1;
  if (aReview) return _compareReviews(a, b);
  return _compareNewWords(a, b);
}

int _compareNewWords(StudyWord a, StudyWord b) {
  final rank = BookStudyOrder.rank(a.entry.fields['book_category'])
      .compareTo(BookStudyOrder.rank(b.entry.fields['book_category']));
  if (rank != 0) return rank;
  final page = BookStudyOrder.sourcePage(a)
      .compareTo(BookStudyOrder.sourcePage(b));
  if (page != 0) return page;
  final word = a.entry.word.compareTo(b.entry.word);
  if (word != 0) return word;
  return a.entry.id.compareTo(b.entry.id);
}

int _compareReviews(StudyWord a, StudyWord b) {
  DateTime? earliest(StudyWord word) {
    final meaning = word.dueAt;
    final reading = word.pronunciationProgress?.dueAt;
    if (meaning == null) return reading;
    return reading == null || meaning.isBefore(reading) ? meaning : reading;
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
  final priority = (a.entry.fields['learning_priority'] ?? 'P2').compareTo(
    b.entry.fields['learning_priority'] ?? 'P2',
  );
  if (priority != 0) return priority;
  final byWord = a.entry.word.compareTo(b.entry.word);
  if (byWord != 0) return byWord;
  return a.entry.id.compareTo(b.entry.id);
}

List<StudyWord> orderedDueWords(
  List<StudyWord> words,
  DateTime now, {
  String? libraryClass = '主学习',
}) {
  final selected =
      words
          .where(
            (word) =>
                (libraryClass == null
                    ? word.entry.libraryClass != '暂缓'
                    : word.entry.libraryClass == libraryClass) &&
                (word.isDue(now) || word.isPronunciationDue(now)),
          )
          .toList()
        ..sort((a, b) => compareStudyQueue(a, b, now));
  return selected;
}

/// Mode 1 queue: strictly studied words that have reached `dueAt <= now`,
/// ordered by `dueAt` ascending (oldest overdue first). Never includes untested
/// new words.
List<StudyWord> dueMeaningReviewQueue(
  List<StudyWord> words,
  DateTime now, {
  String? libraryClass,
}) {
  final selected =
      words
          .where(
            (word) =>
                isMeaningReviewDue(word, now) &&
                (libraryClass == null ||
                    word.entry.libraryClass == libraryClass),
          )
          .toList()
        ..sort((a, b) {
          final aDue = a.dueAt;
          final bDue = b.dueAt;
          if (aDue != null && bDue != null) {
            final order = aDue.compareTo(bDue);
            if (order != 0) return order;
          } else if (aDue != null) {
            return -1;
          } else if (bDue != null) {
            return 1;
          }
          return _compareReviews(a, b);
        });
  return selected;
}

/// Mode 2 queue: weak words (`forgotten` or `familiar`) from real SQLite
/// learning progress, ordered with `forgotten` before `familiar`, then `dueAt`
/// ascending, then most recently reviewed first.
List<StudyWord> weakMeaningWordQueue(
  List<StudyWord> words,
  DateTime now, {
  String? libraryClass,
}) {
  final selected =
      words
          .where(
            (word) =>
                isWeakMeaningWord(word) &&
                (libraryClass == null ||
                    word.entry.libraryClass == libraryClass),
          )
          .toList()
        ..sort((a, b) {
          final aRank = a.status == 'forgotten' ? 0 : 1;
          final bRank = b.status == 'forgotten' ? 0 : 1;
          if (aRank != bRank) return aRank.compareTo(bRank);
          final aDue = a.dueAt;
          final bDue = b.dueAt;
          if (aDue != null && bDue != null) {
            final byDue = aDue.compareTo(bDue);
            if (byDue != 0) return byDue;
          } else if (aDue != null || bDue != null) {
            return aDue != null ? -1 : 1;
          }
          final aLast = a.lastReviewedAt;
          final bLast = b.lastReviewedAt;
          if (aLast != null && bLast != null) {
            final byLast = bLast.compareTo(aLast);
            if (byLast != 0) return byLast;
          }
          return _compareNewWords(a, b);
        });
  return selected;
}

/// New-word study queue: untested words ordered by `BookStudyOrder`
/// (`高频词 -> 基础词 -> 中频词 -> 低频词 -> 偶考词 -> 补充词`).
List<StudyWord> newLearnableWordQueue(
  List<StudyWord> words, {
  String? libraryClass,
}) {
  final selected =
      words
          .where(
            (word) =>
                word.entry.libraryClass != '暂缓' &&
                (libraryClass == null ||
                    word.entry.libraryClass == libraryClass) &&
                word.status == 'untested' &&
                word.reviewCount == 0,
          )
          .toList()
        ..sort(_compareNewWords);
  return selected;
}

/// Pronunciation weak / due queue: words with real pronunciation self-assessments
/// that are due or graded as `再练习` / `基本会读`.
List<StudyWord> pronunciationReviewQueue(List<StudyWord> words, DateTime now) {
  final selected = words.where((w) => isPronunciationWeakOrDue(w, now)).toList()
    ..sort((a, b) {
      final aDue = a.isPronunciationDue(now);
      final bDue = b.isPronunciationDue(now);
      if (aDue != bDue) return aDue ? -1 : 1;
      final aNeeds =
          a.pronunciationProgress?.grade == PronunciationGrade.needsPractice ||
          a.pronunciationStatus == '再练习';
      final bNeeds =
          b.pronunciationProgress?.grade == PronunciationGrade.needsPractice ||
          b.pronunciationStatus == '再练习';
      if (aNeeds != bNeeds) return aNeeds ? -1 : 1;
      final aDueAt = a.pronunciationProgress?.dueAt;
      final bDueAt = b.pronunciationProgress?.dueAt;
      if (aDueAt != null && bDueAt != null) {
        final byDue = aDueAt.compareTo(bDueAt);
        if (byDue != 0) return byDue;
      }
      return _compareNewWords(a, b);
    });
  return selected;
}

/// Real SQLite-backed summary metrics for the Review Center.
final class ReviewDashboardStats {
  const ReviewDashboardStats({
    required this.totalCount,
    required this.coreCount,
    required this.extensionCount,
    required this.dueReviewCount,
    required this.completedTodayCount,
    required this.remainingReviewCount,
    required this.notYetDueCount,
    required this.weakWordsCount,
    required this.forgottenCount,
    required this.familiarCount,
    required this.masteredCount,
    required this.studiedCount,
    required this.untestedCount,
    required this.newLearnableCount,
    required this.pronunciationWeakCount,
  });

  factory ReviewDashboardStats.fromWords(List<StudyWord> words, DateTime now) {
    final nowUtc = now.toUtc();
    var coreCount = 0;
    var extensionCount = 0;
    var dueReviewCount = 0;
    var completedTodayCount = 0;
    var notYetDueCount = 0;
    var forgottenCount = 0;
    var familiarCount = 0;
    var masteredCount = 0;
    var studiedCount = 0;
    var untestedCount = 0;
    var newLearnableCount = 0;
    var pronunciationWeakCount = 0;

    for (final w in words) {
      if (w.entry.libraryClass == '主学习') coreCount++;
      if (w.entry.libraryClass == '扩展') extensionCount++;
      final isStudied = w.status != 'untested' || w.reviewCount > 0;
      if (isStudied) {
        studiedCount++;
      } else {
        untestedCount++;
      }
      if (w.entry.libraryClass == '暂缓') continue;

      if (isMeaningReviewDue(w, nowUtc)) {
        dueReviewCount++;
      } else if (isStudied && w.dueAt != null && w.dueAt!.isAfter(nowUtc)) {
        notYetDueCount++;
      } else if (!isStudied) {
        newLearnableCount++;
      }

      if (isStudied && isReviewedOnLocalDay(w.lastReviewedAt, now)) {
        completedTodayCount++;
      }

      if (w.status == 'forgotten') forgottenCount++;
      if (w.status == 'familiar') familiarCount++;
      if (w.status == 'mastered') masteredCount++;

      if (isPronunciationWeakOrDue(w, nowUtc)) {
        pronunciationWeakCount++;
      }
    }

    return ReviewDashboardStats(
      totalCount: words.length,
      coreCount: coreCount,
      extensionCount: extensionCount,
      dueReviewCount: dueReviewCount,
      completedTodayCount: completedTodayCount,
      remainingReviewCount: dueReviewCount,
      notYetDueCount: notYetDueCount,
      weakWordsCount: forgottenCount + familiarCount,
      forgottenCount: forgottenCount,
      familiarCount: familiarCount,
      masteredCount: masteredCount,
      studiedCount: studiedCount,
      untestedCount: untestedCount,
      newLearnableCount: newLearnableCount,
      pronunciationWeakCount: pronunciationWeakCount,
    );
  }

  final int totalCount;
  final int coreCount;
  final int extensionCount;
  final int dueReviewCount;
  final int completedTodayCount;
  final int remainingReviewCount;
  final int notYetDueCount;
  final int weakWordsCount;
  final int forgottenCount;
  final int familiarCount;
  final int masteredCount;
  final int studiedCount;
  final int untestedCount;
  final int newLearnableCount;
  final int pronunciationWeakCount;
}
