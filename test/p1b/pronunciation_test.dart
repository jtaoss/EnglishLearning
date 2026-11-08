import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/local_audio_cache.dart';
import 'package:english_learning/features/pronunciation/pronunciation_content.dart';
import 'package:english_learning/features/pronunciation/pronunciation_page.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_session.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/pronunciation/standard_audio_player.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';

Map<String, dynamic> contentJson([String word = 'side']) =>
    ((jsonDecode(File('assets/pronunciation/manifest.json').readAsStringSync())
                as Map<String, dynamic>)['items']
            as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((v) => v['word'] == word);
PronunciationContent content([String word = 'side']) =>
    PronunciationContent(contentJson(word));

class DiskAssetBundle extends CachingAssetBundle {
  bool fail = false;
  @override
  Future<ByteData> load(String key) async {
    if (fail) throw StateError('bundled asset unavailable');
    return ByteData.sublistView(await File(key).readAsBytes());
  }
}

class MemoryPronunciationStore implements PronunciationStore {
  int writes = 0;
  bool fail = false;
  PronunciationProgress progress = const PronunciationProgress();
  @override
  Future<PronunciationProgress> readPronunciation(String id) async => progress;
  @override
  Future<void> recordPronunciation({
    required String entryId,
    required PronunciationGrade grade,
    required String audioAssetId,
    required String attemptId,
    required DateTime at,
  }) async {
    if (fail) throw StateError('disk unavailable');
    writes++;
    progress = PronunciationProgress(grade: grade, assessedAt: at);
  }
}

class ControlledPlayer implements StandardAudioPlayer {
  int plays = 0, stops = 0, disposals = 0;
  Completer<void>? completion;
  bool fail = false;
  @override
  Future<void> playFile(
    String path, {
    required void Function() onStarted,
  }) async {
    plays++;
    if (fail) throw StateError('audio device failure');
    completion = Completer<void>();
    onStarted();
    await completion!.future;
  }

  void complete() {
    if (!(completion?.isCompleted ?? true)) completion!.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    if (!(completion?.isCompleted ?? true)) {
      completion!.completeError(PlaybackInterrupted());
    }
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await stop();
  }
}

class FakeAudioCache implements PronunciationAudioCache {
  Completer<File>? hold;
  bool fail = false;
  @override
  Future<File> resolve(PronunciationContent c) async {
    if (fail) throw const FormatException('音频文件校验失败');
    return hold == null ? File(c.assetPath) : await hold!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('six samples preserve exact existing IDs, open licenses and sourced hints without IPA', () async {
    final catalog = await PronunciationCatalog.load(DiskAssetBundle());
    final entries = VocabularyCsv.parse(
      File('assets/vocabulary/verified100.csv').readAsStringSync(),
    );
    expect(catalog.entries.length, 6);
    for (final c in catalog.entries.values) {
      expect(entries.singleWhere((v) => v.id == c.id).word, c.word);
      expect(c.cacheAllowed, isTrue);
      expect(c.evidenceUrls.length, greaterThanOrEqualTo(3));
      expect(
        RegExp(r'[\u0250-\u02ff]').hasMatch(c.note + c.stressDisplay),
        isFalse,
      );
    }
    expect(content('notice').listenToRemember, isTrue);
    expect(content('autumn').stressDisplay, 'AU · tumn');
  });
  test('unsafe audio IDs, paths, hashes and stress ranges fail closed', () {
    for (final change in [
      {'audio_asset_id': '../outside'},
      {'asset_path': '../outside.wav'},
      {'sha256': 'wrong'},
      {'stressed_syllable': 99},
    ]) {
      expect(
        () => PronunciationContent({...contentJson(), ...change}),
        throwsFormatException,
      );
    }
  });

  group('licensed local cache', () {
    late Directory dir;
    late DiskAssetBundle bundle;
    late LocalAudioCache cache;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('english_pron_cache_');
      bundle = DiskAssetBundle();
      cache = LocalAudioCache(directory: () async => dir, bundle: bundle);
    });
    tearDown(() async {
      final path = dir.absolute.path;
      if (!path.startsWith(
        '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}english_pron_cache_',
      )) {
        throw StateError('Unsafe cleanup');
      }
      await dir.delete(recursive: true);
    });
    test(
      'offline cached file works even when asset loader subsequently fails',
      () async {
        final file = await cache.resolve(content());
        bundle.fail = true;
        expect((await cache.resolve(content())).path, file.path);
      },
    );
    test('corrupted cache repairs from licensed bundle and concurrent calls share result', () async {
      final file = await cache.resolve(content());
      await file.writeAsBytes([1, 2, 3]);
      final results = await Future.wait(
        List.generate(5, (_) => cache.resolve(content())),
      );
      expect(results.map((f) => f.path).toSet().length, 1);
      expect(
        await file.readAsBytes(),
        await File(content().assetPath).readAsBytes(),
      );
      expect(
        dir.listSync(recursive: true).where((v) => v.path.endsWith('.part')),
        isEmpty,
      );
    });
    test('missing asset or invalid hash never returns playable path', () async {
      bundle.fail = true;
      await expectLater(cache.resolve(content()), throwsStateError);
      bundle.fail = false;
      final wrong = PronunciationContent({
        ...contentJson(),
        'sha256': '0' * 64,
      });
      await expectLater(cache.resolve(wrong), throwsFormatException);
    });
    test('no caching without permission', () async {
      await expectLater(
        cache.resolve(
          PronunciationContent({...contentJson(), 'cache_allowed': false}),
        ),
        throwsFormatException,
      );
    });
  });

  group('playback learning sequence', () {
    late MemoryPronunciationStore store;
    late ControlledPlayer player;
    late FakeAudioCache cache;
    late PronunciationSession session;
    setUp(() {
      store = MemoryPronunciationStore();
      player = ControlledPlayer();
      cache = FakeAudioCache();
      session = PronunciationSession(
        content: content(),
        store: store,
        player: player,
        cache: cache,
        logger: AppLogger(),
      );
    });
    tearDown(() => session.dispose());
    Future<void> started() async {
      session.confirmReading();
      unawaited(session.play());
      await Future<void>.delayed(Duration.zero);
    }

    test('cannot play before reading; completion required; rapid repeat play and grade deduplicated', () async {
      await session.play();
      expect(player.plays, 0);
      await started();
      await session.play();
      expect(player.plays, 1);
      expect(await session.assess(PronunciationGrade.confident), isFalse);
      player.complete();
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, PlaybackPhase.completed);
      final results = await Future.wait([
        session.assess(PronunciationGrade.confident),
        session.assess(PronunciationGrade.familiar),
      ]);
      expect(results, [true, false]);
      expect(store.writes, 1);
    });
    test(
      'stopping invalidates late completion and no successful progress',
      () async {
        await started();
        await session.stop();
        await Future<void>.delayed(Duration.zero);
        expect(session.phase, PlaybackPhase.stopped);
        expect(store.writes, 0);
        expect(session.canAssess, isFalse);
      },
    );
    test(
      'navigation/dispose during loading cannot start audio later',
      () async {
        final separate = PronunciationSession(
          content: content(),
          store: store,
          player: player,
          cache: cache,
          logger: AppLogger(),
        );
        cache.hold = Completer<File>();
        separate.confirmReading();
        final play = separate.play();
        separate.dispose();
        cache.hold!.complete(File('unused.wav'));
        await play;
        expect(player.plays, 0);
      },
    );
    test(
      'cache failure, player failure and retry do not invent success',
      () async {
        cache.fail = true;
        session.confirmReading();
        await session.play();
        expect(session.phase, PlaybackPhase.failed);
        cache.fail = false;
        player.fail = true;
        await session.play();
        expect(session.phase, PlaybackPhase.failed);
        expect(store.writes, 0);
        player.fail = false;
        await started();
        player.complete();
        await Future<void>.delayed(Duration.zero);
        expect(session.phase, PlaybackPhase.completed);
      },
    );
    test('save failure can retry same completed attempt', () async {
      await started();
      player.complete();
      await Future<void>.delayed(Duration.zero);
      store.fail = true;
      expect(await session.assess(PronunciationGrade.familiar), false);
      store.fail = false;
      expect(await session.assess(PronunciationGrade.familiar), true);
      expect(store.writes, 1);
    });
    test('playback timeout stops player and retains untested state', () async {
      final timed = PronunciationSession(
        content: content(),
        store: store,
        player: player,
        cache: cache,
        logger: AppLogger(),
        timeout: const Duration(milliseconds: 20),
      );
      timed.confirmReading();
      await timed.play();
      expect(timed.phase, PlaybackPhase.failed);
      expect(player.stops, greaterThan(0));
      expect(store.progress.label, '未测试');
      timed.dispose();
    });
  });

  test('v1 migration and pronunciation assessments preserve every old row; disk restart and idempotent attempts', () async {
    final dir = await Directory.systemTemp.createTemp(
      'english_pron_migration_',
    );
    final path = '${dir.path}/learning.sqlite3';
    var repo = await SqliteLearningRepository.open(path);
    final csv = File('assets/vocabulary/verified100.csv').readAsStringSync();
    await repo.importCsv(csv);
    await repo.recordReview(
      content().id,
      ReviewGrade.mastered,
      DateTime.utc(2026, 11, 7),
    );
    await repo.close();
    var raw = sqlite3.open(path);
    raw.execute('DROP TABLE notion_word_links');
    raw.execute('DROP TABLE notion_sync_state');
    raw.execute('DROP TABLE pronunciation_progress');
    raw.execute('DROP TABLE pronunciation_events');
    raw.execute('PRAGMA user_version=1');
    raw.execute(
      'UPDATE learning_progress SET pronunciation_status=? WHERE entry_id=?',
      ['旧自评：需练习', content().id],
    );
    List<String> snapshot(Database db) => [
      for (final t in ['vocabulary', 'learning_progress', 'review_events'])
        jsonEncode(
          db
              .select('SELECT * FROM $t ORDER BY 1')
              .map((v) => v.values.toList())
              .toList(),
        ),
    ];
    final before = snapshot(raw);
    raw.close();
    repo = await SqliteLearningRepository.open(path);
    expect((await repo.readPronunciation(content().id)).label, '旧自评：需练习');
    Future<void> assess() => repo.recordPronunciation(
      entryId: content().id,
      grade: PronunciationGrade.familiar,
      audioAssetId: content().assetId,
      attemptId: 'exact-same-attempt',
      at: DateTime.utc(2026, 11, 8),
    );
    await assess();
    await assess();
    await repo.close();
    repo = await SqliteLearningRepository.open(path);
    expect(
      (await repo.readPronunciation(content().id)).grade,
      PronunciationGrade.familiar,
    );
    raw = sqlite3.open(path);
    expect(snapshot(raw), before);
    expect(
      raw.select('SELECT COUNT(*) n FROM pronunciation_events').single['n'],
      1,
    );
    expect(raw.select('PRAGMA user_version').single.values.single, 3);
    expect(raw.select('PRAGMA integrity_check').single.values.single, 'ok');
    raw.close();
    await expectLater(
      repo.recordPronunciation(
        entryId: 'unknown',
        grade: PronunciationGrade.confident,
        audioAssetId: 'x',
        attemptId: 'new-id',
        at: DateTime.now(),
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(await repo.reviewEventCount(), 1);
    await repo.close();
    if (!dir.path.startsWith(
      '${Directory.systemTemp.path}${Platform.pathSeparator}english_pron_migration_',
    )) {
      throw StateError('Unsafe cleanup');
    }
    await dir.delete(recursive: true);
  });

  testWidgets(
    'phone flow hides hints before reading, waits for playback then self-assesses without overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryPronunciationStore(), player = ControlledPlayer();
      final session = PronunciationSession(
        content: content('autumn'),
        store: store,
        player: player,
        cache: FakeAudioCache(),
        logger: AppLogger(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(body: PronunciationPractice(session: session)),
          ),
        ),
      );
      expect(find.byKey(const Key('phonics-note')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('confirm-self-reading')));
      await tester.tap(find.byKey(const Key('confirm-self-reading')));
      await tester.pumpAndSettle();
      expect(find.text('建议听音记忆'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('play-pronunciation')));
      await tester.tap(find.byKey(const Key('play-pronunciation')));
      await tester.pumpAndSettle();
      final grade = find.byKey(const ValueKey('pronunciation-grade-familiar'));
      expect(tester.widget<OutlinedButton>(grade).onPressed, isNull);
      player.complete();
      await tester.pumpAndSettle();
      await tester.ensureVisible(grade);
      await tester.tap(grade);
      await tester.pumpAndSettle();
      expect(store.writes, 1);
      expect(find.text('发音自评已保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'unconfigured word gives clear missing-audio state with no native player',
    (tester) async {
      final services = PronunciationServices(
        store: MemoryPronunciationStore(),
        logger: AppLogger(),
        catalogLoader: () async => PronunciationCatalog([]),
        playerFactory: () => throw StateError('must not create'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PronunciationPage(
            entryId: 'unknown',
            word: 'unknown',
            services: services,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('audio-missing')), findsOneWidget);
    },
  );
}
