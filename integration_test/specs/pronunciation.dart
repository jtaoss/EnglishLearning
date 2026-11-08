import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/settings/settings_repository.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_content.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/pronunciation/local_audio_cache.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';

import 'local_learning.dart' show waitFor, captureFrame;

final class AcceptanceLogSink implements LogSink {
  final records = <Map<String, String>>[];
  @override
  void write(LogRecord record) => records.add({
    'message': record.message,
    'error': '${record.error}',
    'stack': '${record.stackTrace}',
  });
}

final class OfflineTestBundle extends CachingAssetBundle {
  bool unavailable = false;
  @override
  Future<ByteData> load(String key) {
    if (unavailable) {
      throw StateError(
        'Asset source intentionally unavailable for offline cached replay',
      );
    }
    return rootBundle.load(key);
  }
}

void main() {
  testWidgets(
    'native six-word audio, replay, independent self-assessment and persistent restart',
    (tester) async {
      const reportRoot = String.fromEnvironment('P1B_REPORT_DIR');
      final directory = (await tester.runAsync(
        () => reportRoot.isEmpty
            ? Directory.systemTemp.createTemp('english_pron_native_')
            : Directory(reportRoot).create(recursive: true),
      ))!;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final dbPath = '${directory.path}/pronunciation-$stamp.sqlite3';
      var repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(dbPath),
      ))!;
      addTearDown(() => repo.close());
      final catalog = await PronunciationCatalog.load();
      final productionCacheProbe = await tester.runAsync(
        () => LocalAudioCache()
            .resolve(catalog.entries.values.first)
            .timeout(const Duration(seconds: 15)),
      );
      final all = VocabularyCsv.parse(
        await rootBundle.loadString('assets/vocabulary/verified100.csv'),
      );
      final rows = all.where((e) => catalog.entries.containsKey(e.id)).toList();
      final columns = [
        ...VocabularyCsv.columns,
        ...VocabularyCsv.optionalColumns,
      ];
      final sixCsv = Csv().encode([
        columns,
        for (final e in rows)
          [for (final column in columns) e.fields[column] ?? ''],
      ]);
      await tester.runAsync(() => repo.importCsv(sixCsv));
      final before = (await tester.runAsync(repo.readWords))!;
      final log = AcceptanceLogSink();
      final bundle = OfflineTestBundle();
      final cacheDirectory = Directory(
        '${directory.path}/cache resources-$stamp/发音',
      );
      final services = PronunciationServices(
        store: repo,
        logger: AppLogger(sink: log),
        cache: LocalAudioCache(
          directory: () async => cacheDirectory,
          bundle: bundle,
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('native-capture-root'),
          child: EnglishLearningApp(
            repository: SharedPreferencesSettingsRepository(),
            logger: AppLogger(),
            config: AppConfig.developmentPreset(),
            learningRepository: repo,
            pronunciationServices: services,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-vocabulary')));
      await tester.pumpAndSettle();
      await waitFor(tester, find.byKey(const Key('open-pronunciation')));
      await tester.tap(find.byKey(const Key('open-pronunciation')));
      await tester.pumpAndSettle();
      final playback = <Map<String, Object?>>[];
      final frames = <String>[];
      for (final c in catalog.entries.values) {
        await tester.tap(find.byKey(ValueKey('pronunciation-word-${c.id}')));
        await tester.pumpAndSettle();
        await waitFor(tester, find.byKey(const Key('confirm-self-reading')));
        expect(find.byKey(const Key('phonics-note')), findsNothing);
        await tester.ensureVisible(
          find.byKey(const Key('confirm-self-reading')),
        );
        await tester.tap(find.byKey(const Key('confirm-self-reading')));
        await tester.pumpAndSettle();
        for (var n = 0; n < (c.word == 'tree' ? 2 : 1); n++) {
          final attempt = '${c.word}-$n';
          await tester.runAsync(
            () => File('${directory.path}/audio-stage.json').writeAsString(
              jsonEncode({
                'stamp': stamp,
                'pid': pid,
                'word': c.word,
                'attempt': attempt,
                'phase': 'play',
              }),
              flush: true,
            ),
          );
          await tester.ensureVisible(
            find.byKey(const Key('play-pronunciation')),
          );
          if (n == 1) bundle.unavailable = true;
          await tester.tap(find.byKey(const Key('play-pronunciation')));
          try {
            await waitFor(tester, find.text('播放完成，请对照后自评'));
          } catch (_) {
            await captureFrame(tester, directory, 'failed-$stamp');
            await tester.runAsync(
              () => File('${directory.path}/failure-$stamp.json').writeAsString(
                jsonEncode({
                  'word': c.word,
                  'logs': log.records,
                  'texts': tester
                      .widgetList<Text>(find.byType(Text))
                      .map((v) => v.data)
                      .toList(),
                }),
              ),
            );
            await tester.runAsync(
              () => File('${directory.path}/audio-stage.json').writeAsString(
                jsonEncode({
                  'stamp': stamp,
                  'pid': pid,
                  'phase': 'finished',
                  'passed': false,
                }),
                flush: true,
              ),
            );
            rethrow;
          } finally {
            bundle.unavailable = false;
          }
          expect(find.byKey(const Key('pronunciation-error')), findsNothing);
          playback.add({
            'word': c.word,
            'attempt': attempt,
            'completed': true,
            'pid': pid,
          });
        }
        if (c.word == 'autumn') {
          frames.add(
            await captureFrame(
              tester,
              directory,
              'pronunciation-autumn-$stamp',
            ),
          );
        }
        final grade = find.byKey(
          const ValueKey('pronunciation-grade-familiar'),
        );
        await tester.ensureVisible(grade);
        await tester.tap(grade);
        await waitFor(tester, find.byKey(const Key('pronunciation-saved')));
        expect(
          (await tester.runAsync(() => repo.readPronunciation(c.id)))!.grade,
          PronunciationGrade.familiar,
        );
        // A second tap after acknowledgement must not create an event.
        expect(tester.widget<OutlinedButton>(grade).onPressed, isNull);
        final context = tester.element(find.byType(Scaffold).last);
        Navigator.of(context).pop();
        await tester.pumpAndSettle();
      }
      await tester.runAsync(
        () => File('${directory.path}/audio-stage.json').writeAsString(
          jsonEncode({
            'stamp': stamp,
            'pid': pid,
            'phase': 'finished',
            'passed': true,
          }),
          flush: true,
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(repo.close);
      repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(dbPath),
      ))!;
      final after = (await tester.runAsync(repo.readWords))!;
      expect(
        after
            .map(
              (w) => [
                w.entry.id,
                w.status,
                w.reviewCount,
                w.dueAt,
                w.pronunciationStatus,
              ],
            )
            .toList(),
        before
            .map(
              (w) => [
                w.entry.id,
                w.status,
                w.reviewCount,
                w.dueAt,
                w.pronunciationStatus,
              ],
            )
            .toList(),
      );
      expect(await tester.runAsync(repo.reviewEventCount), 0);
      for (final c in catalog.entries.values) {
        expect(
          (await tester.runAsync(() => repo.readPronunciation(c.id)))!.label,
          '基本会读',
        );
      }
      await tester.runAsync(
        () =>
            File('${directory.path}/pronunciation-result-$stamp.json')
                .writeAsString(
                  jsonEncode({
                    'stamp': stamp,
                    'pid': pid,
                    'db_path': dbPath,
                    'sample_count': 6,
                    'word_ids': catalog.entries.keys.toList(),
                    'playback': playback,
                    'disk_reopen_preserved': true,
                    'meaning_progress_unchanged': true,
                    'review_events': 0,
                    'production_cache_probe': productionCacheProbe!.path,
                    'offline_cached_replay_without_asset_source': true,
                    'frames': frames,
                  }),
                  flush: true,
                ),
      );
    },
  );
}
