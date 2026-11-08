import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

const p1dDirectory = String.fromEnvironment('P1D_DIR');
String get p1dDatabase => '$p1dDirectory/learning-copy.sqlite3';

Future<void> waitP1d(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  fail('P1-D timed out waiting for $finder');
}

Map<String, String> snapshotTables(String path, {bool all = false}) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final tables = all
        ? [
            'vocabulary',
            'learning_progress',
            'review_events',
            'pronunciation_progress',
            'pronunciation_events',
            'notion_word_links',
            'notion_sync_state',
          ]
        : [
            'learning_progress',
            'review_events',
            'pronunciation_progress',
            'pronunciation_events',
          ];
    return {
      for (final table in tables)
        table: jsonEncode(
          db
              .select('SELECT * FROM $table ORDER BY 1,2')
              .map((row) => row.values.toList())
              .toList(),
        ),
    };
  } finally {
    db.close();
  }
}

Future<void> saveP1d(WidgetTester tester, String name, Object data) async {
  await tester.runAsync(
    () =>
        File('$p1dDirectory/$name')
            .writeAsString(jsonEncode(data), flush: true),
  );
}

Future<void> openListWord(WidgetTester tester, String id) async {
  final list = find.byKey(const Key('word-list'));
  await waitP1d(tester, list);
  await tester.drag(list, const Offset(0, 10000));
  await tester.pump(const Duration(milliseconds: 500));
  final word = find.byKey(ValueKey('word-$id'));
  for (
    var step = 0;
    step < 45 && word.hitTestable().evaluate().isEmpty;
    step++
  ) {
    await tester.drag(list, const Offset(0, -250));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(word.hitTestable(), findsOneWidget);
  await tester.tap(word.hitTestable());
  await tester.pump(const Duration(milliseconds: 500));
}
