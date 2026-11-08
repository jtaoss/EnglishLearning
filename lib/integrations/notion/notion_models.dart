import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:english_learning/core/storage/learning_repository.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';

const notionPilotSource = '157d89e5-71fb-4e68-9640-1b04dbb1e627';
const notionApiVersion = '2026-03-11';
final notionIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Safe, fixed messages only. Never include response bodies or credentials.
final class NotionFailure implements Exception {
  const NotionFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

final class NotionAccount {
  NotionAccount({required this.dataSourceId, required this.token}) {
    if (!notionIdPattern.hasMatch(dataSourceId) ||
        token.length < 20 ||
        token.length > 2000 ||
        !RegExp(r'^[\x21-\x7E]+$').hasMatch(token)) {
      throw const NotionFailure('请检查数据源 ID 和密钥格式。密钥只在程序内输入。');
    }
  }
  final String dataSourceId;
  final String token;
  String encode() =>
      jsonEncode({'data_source_id': dataSourceId, 'token': token});
  static NotionAccount decode(String value) {
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      return NotionAccount(
        dataSourceId: data['data_source_id'] as String,
        token: data['token'] as String,
      );
    } catch (_) {
      throw const NotionFailure('安全连接配置无法读取，请重新保存密钥。');
    }
  }

  @override
  String toString() => 'NotionAccount(credentials redacted)';
}

final class NotionSyncState {
  const NotionSyncState({this.watermark, this.syncedAt, this.linkedWords = 0});
  final DateTime? watermark;
  final DateTime? syncedAt;
  final int linkedWords;
}

final class NotionWord {
  NotionWord({
    required this.entry,
    required this.pageId,
    required this.editedAt,
  });
  final VocabularyEntry entry;
  final String pageId;
  final DateTime editedAt;
  String get contentHash =>
      sha256.convert(utf8.encode(jsonEncode(entry.fields))).toString();
}

abstract interface class NotionSyncStore {
  Future<NotionSyncState> readNotionState(String sourceId);
  Future<ImportResult> applyNotionBatch({
    required String sourceId,
    required List<NotionWord> words,
    required DateTime? expectedWatermark,
    required DateTime? watermark,
    required DateTime syncedAt,
  });
}

/// Same 100 stable identities as CSV. This is an explicit scope, not a full dump.
final class NotionScope {
  NotionScope(String csv) : entries = VocabularyCsv.parse(csv) {
    if (entries.length != 100) {
      throw const NotionFailure('本轮样本范围须为 100 个既有稳定 ID。');
    }
  }
  final List<VocabularyEntry> entries;
  Map<String, String> get heads => {for (final e in entries) e.id: e.word};
}

abstract final class NotionFields {
  static const mapping = <String, String>{
    'entry_id': '词条ID',
    'word': '单词',
    'meaning_zh': '中文词义',
    'book_category': '原书分类',
    'source_file': '来源文件',
    'source_id': '来源ID',
    'source_pdf_pages': '原书PDF页码',
    'source_index_pages': '索引PDF页码',
    'book_verification': '原书核验状态',
    'meaning_review_status': '释义复核说明',
    'pets2015_status': 'PETS3 2015收录状态',
    'pets2025_status': 'PETS3 2025收录状态',
    'library_class': '学习词库分类',
    'part_of_speech': '词性',
    'usage_note': '用法说明',
    'lexical_sources': '释义来源',
  };
  static const selects = {
    'book_category',
    'book_verification',
    'pets2015_status',
    'pets2025_status',
    'library_class',
  };

  static String type(String field) => field == 'word'
      ? 'title'
      : selects.contains(field)
      ? 'select'
      : 'rich_text';

  static void validateSchema(Map<String, dynamic> source, String sourceId) {
    if (source['id'] != sourceId ||
        source['object'] != 'data_source' ||
        source['in_trash'] == true) {
      throw const NotionFailure('目标不是可用的数据源，请检查数据源 ID 和连接权限。');
    }
    final properties = source['properties'];
    if (properties is! Map) throw const NotionFailure('Notion 数据源缺少字段结构。');
    for (final field in mapping.keys) {
      final p = properties[mapping[field]];
      if (p is! Map || p['type'] != type(field)) {
        throw NotionFailure('Notion 字段“${mapping[field]}”缺失或类型不符，原数据已保留。');
      }
    }
  }

  static NotionWord read(
    Map<String, dynamic> page,
    NotionScope scope,
    String sourceId,
  ) {
    try {
      final pageId = page['id'] as String;
      if (!notionIdPattern.hasMatch(pageId) ||
          page['object'] != 'page' ||
          page['in_trash'] == true ||
          page['is_archived'] == true ||
          page['archived'] == true ||
          (page['parent'] as Map)['data_source_id'] != sourceId) {
        throw const NotionFailure('同步结果包含无效或已归档词条，原数据已保留。');
      }
      final properties = page['properties'] as Map;
      final fields = <String, String>{};
      for (final field in mapping.keys) {
        final property = properties[mapping[field]] as Map;
        final expected = type(field);
        if (property['type'] != expected || property['has_more'] == true) {
          throw const NotionFailure('词条字段类型不符或内容未完整返回，整批未同步。');
        }
        if (expected == 'select') {
          fields[field] =
              ((property['select'] as Map?)?['name'] as String?) ?? '';
        } else {
          fields[field] = (property[expected] as List)
              .map((part) {
                final p = part as Map;
                return (p['plain_text'] ?? (p['text'] as Map?)?['content'])
                    as String;
              })
              .join()
              .trim();
        }
      }
      final expectedHead = scope.heads[fields['entry_id']];
      if (expectedHead == null || expectedHead != fields['word']) {
        throw const NotionFailure('Notion 稳定 ID 或词头与本轮已核验样本不一致，整批未同步。');
      }
      if (!const {'已收录', '未直接列出', '待核实'}.contains(fields['pets2015_status'])) {
        throw const NotionFailure('2015 收录状态无效，整批未同步。');
      }
      final columns = [
        ...VocabularyCsv.columns,
        ...VocabularyCsv.optionalColumns,
      ];
      final entry = VocabularyCsv.parse(
        Csv().encode([
          columns,
          [for (final key in columns) fields[key] ?? ''],
        ]),
      ).single;
      final edited = DateTime.parse(page['last_edited_time'] as String);
      if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$')
          .hasMatch(page['last_edited_time'] as String)) {
        throw const NotionFailure('远端修改时间缺少时区，整批未同步。');
      }
      return NotionWord(entry: entry, pageId: pageId, editedAt: edited.toUtc());
    } on NotionFailure {
      rethrow;
    } on FormatException catch (error) {
      throw NotionFailure(error.message);
    } catch (_) {
      throw const NotionFailure('Notion 词条内容缺失或格式异常，整批未同步。');
    }
  }
}
