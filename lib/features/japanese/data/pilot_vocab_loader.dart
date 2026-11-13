import 'dart:io';

import 'package:csv/csv.dart';
import 'package:english_learning/features/japanese/domain/japanese_vocab_entry.dart';

final class PilotVocabLoader {
  const PilotVocabLoader({this.filePath = defaultFilePath});

  static const String defaultFilePath =
      r'E:\desktop\JapaneseLearningSources\Pilot100\japanese_vocab_100.csv';

  final String filePath;

  /// Loads and parses the Pilot 100 CSV file into strongly typed entries.
  /// If the file does not exist, an empty list or fallback fixture can be returned.
  Future<List<JapaneseVocabEntry>> load({String? csvContent}) async {
    String rawCsv;
    if (csvContent != null) {
      rawCsv = csvContent;
    } else {
      final file = File(filePath);
      if (!await file.exists()) {
        return const [];
      }
      rawCsv = await file.readAsString();
    }

    return parseCsv(rawCsv);
  }

  /// Synchronous parse helper.
  static List<JapaneseVocabEntry> parseCsv(String rawCsv) {
    if (rawCsv.trim().isEmpty) return const [];

    // Strip leading UTF-8 BOM if present
    var sanitized = rawCsv;
    if (sanitized.startsWith('\uFEFF')) {
      sanitized = sanitized.substring(1);
    }

    final rows = Csv(fieldDelimiter: ',', dynamicTyping: false)
        .decode(sanitized)
        .where(
          (row) => !(row.length == 1 && row.single.toString().trim().isEmpty),
        )
        .toList();
    if (rows.isEmpty) return const [];

    // Process header row: strip quotes and whitespace
    final rawHeader = rows.first;
    final headerIndex = <String, int>{};
    for (var i = 0; i < rawHeader.length; i++) {
      final name = rawHeader[i].toString().replaceAll('"', '').trim();
      headerIndex[name] = i;
    }

    String getField(List<dynamic> row, String key) {
      final idx = headerIndex[key];
      if (idx == null || idx >= row.length) return '';
      return row[idx].toString().trim();
    }

    final entries = <JapaneseVocabEntry>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty ||
          (row.length == 1 && row[0].toString().trim().isEmpty)) {
        continue;
      }

      final sampleId = getField(row, 'sample_id');
      if (sampleId.isEmpty) continue;

      final sampleOrder =
          int.tryParse(getField(row, 'sample_order')) ?? entries.length + 1;
      final japanese = getField(row, 'japanese');
      final kana = getField(row, 'kana');
      final zhCnCandidate = getField(row, 'zh_cn_candidate');
      final englishOriginal = getField(row, 'english_original');
      final posOriginal = getField(row, 'pos_original');
      final accentOriginal = getField(row, 'accent_original');
      final romajiOriginal = getField(row, 'romaji_original');
      final levelOriginal = getField(row, 'level_original');
      final lessonOriginal = getField(row, 'lesson_original');
      final activityOriginal = getField(row, 'activity_original');
      final sourceSheet = getField(row, 'source_sheet');
      final sourceExcelRow = getField(row, 'source_excel_row');
      final validationStatus = getField(row, 'validation_status');
      final humanConfirmation = getField(row, 'human_confirmation');
      final reviewPriority = getField(row, 'review_priority');
      final reviewFlags = getField(row, 'review_flags');
      final ambiguityNotes = getField(row, 'ambiguity_notes');
      final officialZhReferenceType = getField(
        row,
        'official_zh_reference_type',
      );
      final officialZhReference = getField(row, 'official_zh_reference');
      final contextPdf = getField(row, 'context_pdf');
      final contextPdfPages = getField(row, 'context_pdf_pages');
      final importAllowed = getField(row, 'import_allowed');

      entries.add(
        JapaneseVocabEntry(
          sampleId: sampleId,
          sampleOrder: sampleOrder,
          japanese: japanese,
          kana: kana,
          zhCnCandidate: zhCnCandidate,
          englishOriginal: englishOriginal,
          posOriginal: posOriginal,
          accentOriginal: accentOriginal,
          romajiOriginal: romajiOriginal,
          levelOriginal: levelOriginal,
          lessonOriginal: lessonOriginal,
          activityOriginal: activityOriginal,
          sourceSheet: sourceSheet,
          sourceExcelRow: sourceExcelRow,
          validationStatus: validationStatus,
          humanConfirmation: humanConfirmation,
          reviewPriority: reviewPriority,
          reviewFlags: reviewFlags,
          ambiguityNotes: ambiguityNotes,
          officialZhReferenceType: officialZhReferenceType,
          officialZhReference: officialZhReference,
          contextPdf: contextPdf,
          contextPdfPages: contextPdfPages,
          importAllowed: importAllowed,
        ),
      );
    }

    return entries;
  }
}
