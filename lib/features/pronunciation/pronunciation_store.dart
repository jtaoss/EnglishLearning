enum PronunciationGrade {
  needsPractice('再练习'),
  familiar('基本会读'),
  confident('能独立认读');

  const PronunciationGrade(this.label);
  final String label;
}

final class PronunciationProgress {
  const PronunciationProgress({this.grade, this.assessedAt, this.legacyLabel});
  final PronunciationGrade? grade;
  final DateTime? assessedAt;
  final String? legacyLabel;
  String get label => grade?.label ?? legacyLabel ?? '未测试';
}

abstract interface class PronunciationStore {
  Future<PronunciationProgress> readPronunciation(String entryId);
  Future<void> recordPronunciation({
    required String entryId,
    required PronunciationGrade grade,
    required String audioAssetId,
    required String attemptId,
    required DateTime at,
  });
}
