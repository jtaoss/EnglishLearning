import 'package:flutter/foundation.dart';

enum JapaneseRecallGrade {
  forgotten('遗忘', '无法独立回忆'),
  familiar('眼熟', '能回忆出大概或需提示'),
  mastered('掌握', '能迅速准确回忆');

  const JapaneseRecallGrade(this.label, this.description);
  final String label;
  final String description;
}

/// Demonstration in-memory review record for a Japanese vocabulary entry.
/// Tracks independent recall performance across:
/// 1. Dimension A: Meaning recall (看到日语想起中文意思)
/// 2. Dimension B: Reading recall (看到日语能正确读出假名)
final class JapaneseWordReviewRecord {
  JapaneseWordReviewRecord({
    required this.sampleId,
    this.meaningGrade,
    this.readingGrade,
    this.lastReviewedAt,
  });

  final String sampleId;
  JapaneseRecallGrade? meaningGrade;
  JapaneseRecallGrade? readingGrade;
  DateTime? lastReviewedAt;

  bool get isGraded => meaningGrade != null || readingGrade != null;
  bool get isFullyGraded => meaningGrade != null && readingGrade != null;
}

/// In-memory state manager for J1 Japanese demonstration review.
/// Explicitly isolated: never persists to SQLite or Notion.
final class JapaneseReviewSessionState extends ChangeNotifier {
  final Map<String, JapaneseWordReviewRecord> _records = {};

  static const bool isDemonstrationOnly = true;
  static const String demoDisclaimer =
      '演示评分模式：评分仅用于体验 J1 词义与读音双维度评级交互，不会写入正式 SQLite 离线数据库。';

  JapaneseWordReviewRecord getRecord(String sampleId) => _records.putIfAbsent(
    sampleId,
    () => JapaneseWordReviewRecord(sampleId: sampleId),
  );

  void setMeaningGrade(String sampleId, JapaneseRecallGrade grade) {
    final record = getRecord(sampleId);
    record.meaningGrade = grade;
    record.lastReviewedAt = DateTime.now();
    notifyListeners();
  }

  void setReadingGrade(String sampleId, JapaneseRecallGrade grade) {
    final record = getRecord(sampleId);
    record.readingGrade = grade;
    record.lastReviewedAt = DateTime.now();
    notifyListeners();
  }

  int get totalPracticed => _records.values.where((r) => r.isGraded).length;
  int get meaningMasteredCount => _records.values
      .where((r) => r.meaningGrade == JapaneseRecallGrade.mastered)
      .length;
  int get readingMasteredCount => _records.values
      .where((r) => r.readingGrade == JapaneseRecallGrade.mastered)
      .length;

  void resetAll() {
    _records.clear();
    notifyListeners();
  }
}
