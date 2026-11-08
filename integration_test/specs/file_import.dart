import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/vocabulary/vocabulary_page.dart';

import 'local_learning.dart' show mount, waitFor;

// Trace the real platform delegate, never substitute a synthetic file result.
class _TracingSelector extends FileSelectorPlatform {
  _TracingSelector(this.delegate);
  final FileSelectorPlatform delegate;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    debugPrint('NATIVE_PICKER_DELEGATE=${delegate.runtimeType}');
    try {
      final file = await delegate.openFile(
        acceptedTypeGroups: acceptedTypeGroups,
        initialDirectory: initialDirectory,
        confirmButtonText: confirmButtonText,
      );
      debugPrint('NATIVE_PICKER_RESULT=${file?.name ?? 'cancelled'}');
      return file;
    } catch (error) {
      debugPrint('NATIVE_PICKER_ERROR=$error');
      rethrow;
    }
  }
}

void main() {
  const enabled = bool.fromEnvironment('TEST_REAL_WINDOWS_PICKER');
  testWidgets(
    'real Windows file picker handles valid, repeated, empty, bad UTF-8 and cancel',
    (tester) async {
      final previous = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _TracingSelector(previous);
      addTearDown(() => FileSelectorPlatform.instance = previous);
      const reportRoot = String.fromEnvironment('ACCEPTANCE_REPORT_DIR');
      final directory = Directory(reportRoot);
      await tester.runAsync(() => directory.create(recursive: true));
      final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(
          '${directory.path}/picker-$stamp.sqlite3',
        ),
      ))!;
      addTearDown(repo.close);
      await mount(tester, repo);
      final ready = find.byWidgetPredicate(
        (w) =>
            w is OutlinedButton &&
            w.key == VocabularyPage.fileImportKey &&
            w.onPressed != null,
      );
      await waitFor(tester, ready);
      Future<void> choose() async {
        await tester.tap(find.byKey(VocabularyPage.fileImportKey));
        await tester.pump();
      }

      await choose();
      await waitFor(tester, find.text('新增 100，更新 0，未变 0'));
      await choose();
      await waitFor(tester, find.text('新增 0，更新 0，未变 100'));
      await choose();
      await waitFor(tester, find.text('CSV 必须包含表头和词条。'));
      await choose();
      await waitFor(tester, find.textContaining('CSV 不是有效的 UTF-8'));
      await choose();
      await waitFor(tester, ready);
      expect(find.textContaining('CSV 不是有效的 UTF-8'), findsNothing);
      expect((await tester.runAsync(repo.readWords))!.length, 100);
      expect(await tester.runAsync(repo.reviewEventCount), 0);
      await tester.runAsync(
        () => File('${directory.path}/native-file-picker-$stamp.json')
            .writeAsString(
              jsonEncode({
                'real_native_dialog': true,
                'platform': 'windows',
                'valid_import': 100,
                'reimport_total': 100,
                'empty_file_rejected': true,
                'invalid_utf8_rejected': true,
                'cancel_preserved_records': true,
                'review_events': 0,
                'personal_database_used': false,
              }),
            ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    skip: !Platform.isWindows || !enabled,
  );
}
