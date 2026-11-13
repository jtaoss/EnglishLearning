import 'package:flutter/foundation.dart';

/// Represents a single Japanese vocabulary record from the Pilot 100 dataset.
/// All records in Pilot 100 are CANDIDATE translations pending human confirmation.
@immutable
final class JapaneseVocabEntry {
  const JapaneseVocabEntry({
    required this.sampleId,
    required this.sampleOrder,
    required this.japanese,
    required this.kana,
    required this.zhCnCandidate,
    required this.englishOriginal,
    required this.posOriginal,
    required this.accentOriginal,
    required this.romajiOriginal,
    required this.levelOriginal,
    required this.lessonOriginal,
    required this.activityOriginal,
    required this.sourceSheet,
    required this.sourceExcelRow,
    required this.validationStatus,
    required this.humanConfirmation,
    required this.reviewPriority,
    required this.reviewFlags,
    required this.ambiguityNotes,
    required this.officialZhReferenceType,
    required this.officialZhReference,
    required this.contextPdf,
    required this.contextPdfPages,
    required this.importAllowed,
  });

  final String sampleId;
  final int sampleOrder;
  final String japanese;
  final String kana;
  final String zhCnCandidate;
  final String englishOriginal;
  final String posOriginal;
  final String accentOriginal;
  final String romajiOriginal;
  final String levelOriginal;
  final String lessonOriginal;
  final String activityOriginal;
  final String sourceSheet;
  final String sourceExcelRow;
  final String validationStatus;
  final String humanConfirmation;
  final String reviewPriority;
  final String reviewFlags;
  final String ambiguityNotes;
  final String officialZhReferenceType;
  final String officialZhReference;
  final String contextPdf;
  final String contextPdfPages;
  final String importAllowed;

  /// Audit status indicator: all 100 Pilot entries are candidate unconfirmed.
  bool get isCandidatePending => true;
  bool get isHumanConfirmed => false;

  /// Prominent label required on UI: "中文释义待校对".
  String get auditBadgeLabel => '中文释义待校对';

  /// Primary core Chinese meaning extracted from the candidate string.
  String get coreMeaning {
    if (zhCnCandidate.isEmpty) return '（暂无中文释义）';
    final parts = zhCnCandidate.split(RegExp(r'[；;]'));
    return parts.first.trim();
  }

  /// Secondary/extended meanings or pragmatic notes if present.
  String? get extendedMeaning {
    final parts = zhCnCandidate.split(RegExp(r'[；;]'));
    if (parts.length > 1) {
      return parts.sublist(1).map((s) => s.trim()).join('；');
    }
    return null;
  }

  /// Whether this entry contains Kanji (so hiding furigana makes pedagogical sense).
  bool get hasKanji {
    for (final rune in japanese.runes) {
      // CJK Unified Ideographs range
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF)) {
        return true;
      }
    }
    return false;
  }

  /// Clean display label for lesson source, e.g. "Irodori 入门 · 第 1 课 活动 1".
  String get lessonLabel {
    final lesson = lessonOriginal.isNotEmpty ? '第 $lessonOriginal 课' : '';
    final activity = activityOriginal.isNotEmpty ? '活动 $activityOriginal' : '';
    final parts = [levelOriginal, lesson, activity].where((p) => p.isNotEmpty);
    return parts.isEmpty ? 'Irodori 试点' : 'Irodori ${parts.join(' · ')}';
  }

  /// Part of speech localized description.
  String get posLabel => switch (posOriginal) {
    'N' => '名词 (N)',
    'V' => '动词 (V)',
    'A' => '形容词 (A)',
    'Na-A' => 'な形容词 (Na-A)',
    'Adv' => '副词 (Adv)',
    'Exp' => '惯用语/固定表达 (Exp)',
    'Part' => '助词 (Part)',
    'Conj' => '连词 (Conj)',
    'Pron' => '代词 (Pron)',
    _ => posOriginal.isEmpty ? '未标注词性' : posOriginal,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JapaneseVocabEntry &&
          runtimeType == other.runtimeType &&
          sampleId == other.sampleId;

  @override
  int get hashCode => sampleId.hashCode;
}
