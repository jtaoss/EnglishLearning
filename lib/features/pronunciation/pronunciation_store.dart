enum PronunciationGrade {
  needsPractice('再练习'),
  familiar('基本会读'),
  confident('能独立认读');

  const PronunciationGrade(this.label);
  final String label;
}

final class PronunciationProgress {
  const PronunciationProgress({
    this.grade,
    this.assessedAt,
    this.legacyLabel,
    this.sourceId,
  });
  final PronunciationGrade? grade;
  final DateTime? assessedAt;
  final String? legacyLabel;
  final String? sourceId;
  String get sourceLabel => sourceId == null
      ? '未记录来源'
      : sourceId!.startsWith('windows-tts:')
      ? 'Windows 本地 TTS（合成语音）'
      : sourceId!.startsWith('self-reading:')
      ? '自主认读（未核对录音）'
      : sourceId!.startsWith('commons-')
      ? '已授权真人录音'
      : '既有认读来源';
  DateTime? get dueAt => grade == null || assessedAt == null
      ? null
      : assessedAt!.toUtc().add(switch (grade!) {
          PronunciationGrade.needsPractice => const Duration(minutes: 10),
          PronunciationGrade.familiar => const Duration(days: 1),
          PronunciationGrade.confident => const Duration(days: 7),
        });
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
