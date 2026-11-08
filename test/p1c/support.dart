import 'dart:convert';
import 'dart:io';

import 'package:english_learning/integrations/notion/notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:http/http.dart' as http;

const testToken = 'ntn_test_fixture_not_a_real_credential';
NotionAccount testAccount() =>
    NotionAccount(dataSourceId: notionPilotSource, token: testToken);

class MemoryCredentials implements NotionCredentials {
  MemoryCredentials([this.account]);
  NotionAccount? account;
  int writes = 0;
  @override
  Future<NotionAccount?> read() async => account;
  @override
  Future<void> save(NotionAccount value) async {
    account = value;
    writes++;
  }

  @override
  Future<void> delete() async {
    account = null;
  }
}

Map<String, dynamic> snapshot() => jsonDecode(
  File('test/fixtures/notion/verified100_snapshot.json').readAsStringSync(),
) as Map<String, dynamic>;
NotionScope testScope() =>
    NotionScope(File('assets/vocabulary/verified100.csv').readAsStringSync());
Map<String, dynamic> copyJson(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
http.Response jsonResponse(
  Object? value, {
  int status = 200,
  Map<String, String>? headers,
}) => http.Response(
  utf8.decode(utf8.encode(jsonEncode(value))),
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);
Map<String, Object?> listResponse(List<dynamic> rows, {String? next}) => {
  'object': 'list',
  'results': rows,
  'has_more': next != null,
  'next_cursor': next,
};
void setText(Map<String, dynamic> page, String name, String value) {
  page['properties'][name] = {
    'type': 'rich_text',
    'rich_text': [
      {
        'plain_text': value,
        'text': {'content': value},
      },
    ],
  };
}

Future<void> noDelay(Duration _) async {}
