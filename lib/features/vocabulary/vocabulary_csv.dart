import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';

abstract final class VocabularyCsv {
  static const columns = [
    'entry_id',
    'word',
    'meaning_zh',
    'book_category',
    'source_file',
    'source_id',
    'source_pdf_pages',
    'source_index_pages',
    'book_verification',
    'meaning_review_status',
    'pets2015_status',
    'pets2025_status',
    'library_class',
  ];
  static const maxEntries = 100;
  static const optionalColumns = [
    'part_of_speech',
    'usage_note',
    'lexical_sources',
  ];

  static List<VocabularyEntry> parse(String input) {
    if (utf8.encode(input).length > 1024 * 1024) {
      throw const FormatException('CSV 超过 1 MB，未导入。');
    }
    final text = input.startsWith('\uFEFF') ? input.substring(1) : input;
    _checkQuotes(text);
    final rows = Csv(fieldDelimiter: ',', dynamicTyping: false)
        .decode(text)
        .map((row) => row.map((value) => value as String).toList())
        .where((row) => !(row.length == 1 && row.single.trim().isEmpty))
        .toList();
    if (rows.length < 2) {
      throw const FormatException('CSV 必须包含表头和词条。');
    }
    final header = rows.first.map((s) => s.trim()).toList();
    if (header.toSet().length != header.length ||
        !header.toSet().containsAll(columns) ||
        header.any(
          (key) => !columns.contains(key) && !optionalColumns.contains(key),
        )) {
      throw const FormatException('CSV 表头与 100 词样本格式不一致。');
    }
    if (rows.length - 1 > maxEntries) {
      throw const FormatException('本阶段单次最多导入 100 词。');
    }
    final ids = <String>{};
    final words = <String>{};
    final entries = <VocabularyEntry>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length != header.length) {
        throw FormatException('CSV 第 ${i + 1} 条记录列数不正确。');
      }
      // Canonical field order makes a reordered CSV an unchanged reimport.
      final fields = <String, String>{
        for (final key in [...columns, ...optionalColumns])
          if (header.contains(key)) key: row[header.indexOf(key)].trim(),
      };
      for (final key in columns) {
        if (fields[key]!.isEmpty) {
          throw FormatException('CSV 第 ${i + 1} 条记录缺少 $key。');
        }
      }
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:\-]{0,99}$')
          .hasMatch(fields['entry_id']!)) {
        throw FormatException('CSV 第 ${i + 1} 条记录的稳定 ID 无效。');
      }
      if (fields['book_verification'] != '已核验') {
        throw FormatException('CSV 第 ${i + 1} 条记录尚未通过原书核验。');
      }
      if (fields['pets2025_status'] != '待核实') {
        throw FormatException('CSV 第 ${i + 1} 条记录：本阶段 2025 官方归属须保持待核实。');
      }
      if (!const {'主学习', '扩展', '暂缓'}.contains(fields['library_class'])) {
        throw FormatException('CSV 第 ${i + 1} 条记录的词库分类无效。');
      }
      final entry = VocabularyEntry(fields);
      if (!ids.add(entry.id) || !words.add(entry.wordKey)) {
        throw FormatException('CSV 第 ${i + 1} 条记录存在重复 ID 或词头。');
      }
      entries.add(entry);
    }
    return List.unmodifiable(entries);
  }

  // The CSV library is intentionally forgiving. Reject damaged quoting first.
  static void _checkQuotes(String text) {
    var state = 0; // field start, unquoted, quoted, after closing quote
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '\u0000') throw const FormatException('CSV 含有空字符。');
      if (state == 2) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            i++;
          } else {
            state = 3;
          }
        }
      } else if (c == ',' || c == '\r' || c == '\n') {
        state = 0;
      } else if (state == 3 || (state == 1 && c == '"')) {
        throw const FormatException('CSV 引号格式损坏，未导入。');
      } else if (state == 0) {
        state = c == '"' ? 2 : 1;
      }
    }
    if (state == 2) throw const FormatException('CSV 引号未闭合，未导入。');
  }
}
