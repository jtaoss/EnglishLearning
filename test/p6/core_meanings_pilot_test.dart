import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/features/core_meanings_pilot/core_meaning_sample.dart';
import 'package:english_learning/features/core_meanings_pilot/core_meanings_pilot_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final file = File('docs/p6/p6c/core_meanings_pilot.json');
  final text = file.readAsStringSync();
  final bundle = CoreMeaningPilotBundle.decode(text);

  test('only the selected 100 draft records can be previewed', () {
    expect(bundle.samples, hasLength(100));
    expect(bundle.samples.map((s) => s.id).toSet(), hasLength(100));
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (j) => j['record_count'] = 5332,
      (j) => j['publication_status'] = 'approved',
      (j) => (j['records'] as List<dynamic>).removeLast(),
      (j) =>
          ((j['records'] as List<dynamic>)[0]
                  as Map<String, dynamic>)['original_meaning_zh'] =
              '不匹配的原文',
      (j) =>
          ((j['records'] as List<dynamic>)[0]
                  as Map<String, dynamic>)['selection_reason'] =
              '改动后未重新复核',
    ]) {
      final copy = jsonDecode(text) as Map<String, dynamic>;
      mutate(copy);
      expect(
        () => CoreMeaningPilotBundle.decode(jsonEncode(copy)),
        throwsFormatException,
      );
    }
  });

  testWidgets(
    'all answer hints are absent before reveal, including semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(CoreMeaningsPilotApp(bundle: bundle));
      final sample = bundle.samples.first;
      for (final hint in [
        sample.originalMeaning,
        sample.explanation,
        sample.reason,
        ...sample.core.expand((g) => g.glosses),
        ...sample.extended.expand((g) => g.glosses),
        ...sample.other.expand((g) => g.glosses),
      ]) {
        expect(find.textContaining(hint, findRichText: true), findsNothing);
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(hint))),
          findsNothing,
        );
      }
      expect(find.byKey(const Key('pilot-expand-other')), findsNothing);
      expect(find.byKey(const Key('pilot-expand-source')), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'reveal shows core and extension; other and original require expansion',
    (tester) async {
      await tester.pumpWidget(CoreMeaningsPilotApp(bundle: bundle));
      await tester.tap(find.byKey(const Key('pilot-reveal')));
      await tester.pump();
      expect(find.textContaining('双倍的', findRichText: true), findsOneWidget);
      expect(find.textContaining('成双的', findRichText: true), findsOneWidget);
      expect(find.textContaining('替身', findRichText: true), findsNothing);
      expect(find.byKey(const Key('pilot-original')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('pilot-expand-other')));
      await tester.tap(find.byKey(const Key('pilot-expand-other')));
      await tester.pump();
      expect(find.textContaining('替身', findRichText: true), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('pilot-expand-source')));
      await tester.tap(find.byKey(const Key('pilot-expand-source')));
      await tester.pump();
      expect(find.byKey(const Key('pilot-original')), findsOneWidget);
      expect(find.byKey(const Key('pilot-reason')), findsOneWidget);
    },
  );

  testWidgets('navigation hides the previous answer and resets expansions', (
    tester,
  ) async {
    await tester.pumpWidget(CoreMeaningsPilotApp(bundle: bundle));
    await tester.tap(find.byKey(const Key('pilot-reveal')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pilot-next')));
    await tester.pump();
    expect(find.byKey(const Key('pilot-answer')), findsNothing);
    expect(find.byKey(const Key('pilot-reveal')), findsOneWidget);
    expect(find.textContaining('双倍的', findRichText: true), findsNothing);
    await tester.tap(find.byKey(const Key('pilot-previous')));
    await tester.pump();
    expect(find.byKey(const Key('pilot-answer')), findsNothing);
  });

  testWidgets('space reveals and numeric keys do not create a learning grade', (
    tester,
  ) async {
    await tester.pumpWidget(CoreMeaningsPilotApp(bundle: bundle));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.byKey(const Key('pilot-answer')), findsOneWidget);
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pump();
    expect(find.text('1 / 100'), findsOneWidget);
    expect(find.byKey(const Key('pilot-answer')), findsOneWidget);
  });

  testWidgets('narrow layout with large text has no overflow', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: CoreMeaningsPilotPage(bundle: bundle),
      ),
    );
    await tester.tap(find.byKey(const Key('pilot-reveal')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture an isolated preview without starting the personal app', (
    tester,
  ) async {
    // Optional local evidence, never a golden assertion or semantic approval.
    if (!Platform.isWindows) return;
    for (final entry in {
      'Roboto': r'C:\Windows\Fonts\segoeui.ttf',
      'Segoe UI': r'C:\Windows\Fonts\segoeui.ttf',
      'Microsoft YaHei UI': r'C:\Windows\Fonts\msyh.ttc',
      'Microsoft YaHei': r'C:\Windows\Fonts\msyh.ttc',
    }.entries) {
      final font = File(entry.value);
      if (font.existsSync()) {
        final loader = FontLoader(entry.key)
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
        await tester.runAsync(loader.load);
      }
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await tester.runAsync(icons.load);
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: CoreMeaningsPilotApp(bundle: bundle),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final shot = (await tester.runAsync(boundary.toImage))!;
      final bytes = await tester.runAsync(
        () => shot.toByteData(format: ui.ImageByteFormat.png),
      );
      await tester.runAsync(() async {
        final out = File('build/p6c/$name.png');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(bytes!.buffer.asUint8List());
      });
      shot.dispose();
    }

    await capture('hidden');
    await tester.tap(find.byKey(const Key('pilot-reveal')));
    await tester.pumpAndSettle();
    await capture('revealed');
  }, skip: !const bool.fromEnvironment('P6C_CAPTURE_PREVIEW'));
}
