import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';

final class StudyWord {
  const StudyWord({
    required this.entry,
    required this.status,
    required this.pronunciationStatus,
    required this.reviewCount,
    this.lastReviewedAt,
    this.dueAt,
  });
  final VocabularyEntry entry;
  final String status;
  final String pronunciationStatus;
  final int reviewCount;
  final DateTime? lastReviewedAt;
  final DateTime? dueAt;

  String get statusLabel => switch (status) {
    'mastered' => '掌握',
    'familiar' => '眼熟',
    'forgotten' => '遗忘',
    _ => '未测试',
  };
  bool isDue(DateTime now) => dueAt == null || !dueAt!.isAfter(now.toUtc());
}
