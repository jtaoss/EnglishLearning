import 'package:csv/csv.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';

Map<String, String> entryFields({
  String id = 'test-alpha',
  String word = 'alpha',
  String library = '主学习',
  String meaning = '第一个',
}) => {
  'entry_id': id,
  'word': word,
  'meaning_zh': meaning,
  'book_category': '高频词',
  'source_file': 'test-source.pdf',
  'source_id': 'source-test',
  'source_pdf_pages': '12',
  'source_index_pages': '733',
  'book_verification': '已核验',
  'meaning_review_status': '独立编写待复核',
  'pets2015_status': '已收录',
  'pets2025_status': '待核实',
  'library_class': library,
};

String encodeEntries(List<Map<String, String>> entries) => Csv().encode([
  VocabularyCsv.columns,
  for (final e in entries)
    [for (final column in VocabularyCsv.columns) e[column] ?? ''],
]);
