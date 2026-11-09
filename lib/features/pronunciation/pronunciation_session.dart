import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/features/pronunciation/local_audio_cache.dart';
import 'package:english_learning/features/pronunciation/pronunciation_content.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/pronunciation/standard_audio_player.dart';

enum PlaybackPhase { idle, loading, playing, completed, stopped, failed }

final class PronunciationSession extends ChangeNotifier {
  PronunciationSession({
    required this.content,
    required this.store,
    required this.cache,
    required this.player,
    required this.logger,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 15),
  }) : _clock = clock ?? DateTime.now;
  final PronunciationContent content;
  final PronunciationStore store;
  final PronunciationAudioCache cache;
  final StandardAudioPlayer player;
  final AppLogger logger;
  final DateTime Function() _clock;
  final Duration timeout;
  PronunciationProgress progress = const PronunciationProgress();
  PlaybackPhase phase = PlaybackPhase.idle;
  bool triedReading = false, saving = false, saved = false;
  bool _disposed = false;
  int _generation = 0;
  String? error, _attemptId;
  DateTime? _assessedAt;
  bool get busy =>
      phase == PlaybackPhase.loading || phase == PlaybackPhase.playing;
  bool get canAssess => phase == PlaybackPhase.completed && !saving && !saved;

  Future<void> restore() async {
    progress = await store.readPronunciation(content.id);
    _notify();
  }

  void confirmReading() {
    triedReading = true;
    _notify();
  }

  Future<void> play() async {
    if (_disposed || !triedReading || busy || saving) return;
    final generation = ++_generation;
    saved = false;
    _assessedAt = null;
    error = null;
    phase = PlaybackPhase.loading;
    _attemptId = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _notify();
    try {
      final file = await cache.resolve(content).timeout(timeout);
      if (_disposed || generation != _generation) return;
      await player
          .playFile(
            file.path,
            onStarted: () {
              if (!_disposed && generation == _generation) {
                phase = PlaybackPhase.playing;
                _notify();
              }
            },
          )
          .timeout(timeout);
      if (_disposed || generation != _generation) return;
      phase = PlaybackPhase.completed;
    } catch (e, stack) {
      if (_disposed || generation != _generation) return;
      phase = PlaybackPhase.failed;
      error = e is FormatException ? e.message : '音频加载或播放失败，请检查输出设备后重试。';
      logger.error(
        'Pronunciation playback failed',
        error: e,
        stackTrace: stack,
      );
      try {
        await player.stop();
      } catch (_) {
        /* Original error retained. */
      }
    }
    _notify();
  }

  Future<void> stop() async {
    ++_generation;
    phase = PlaybackPhase.stopped;
    try {
      await player.stop();
    } catch (e, stack) {
      logger.error('Audio stop failed', error: e, stackTrace: stack);
    }
    _notify();
  }

  Future<bool> assess(PronunciationGrade grade) async {
    if (_disposed || !canAssess) return false;
    saving = true;
    error = null;
    _notify();
    final at = _assessedAt ??= _clock().toUtc();
    try {
      await store.recordPronunciation(
        entryId: content.id,
        grade: grade,
        audioAssetId: content.assetId,
        attemptId: _attemptId!,
        at: at,
      );
      progress = PronunciationProgress(
        grade: grade,
        assessedAt: at,
        sourceId: content.assetId,
      );
      saved = true;
      return true;
    } catch (e, stack) {
      error = '发音自评保存失败，请重试。词义复习记录未改变。';
      logger.error(
        'Pronunciation assessment failed',
        error: e,
        stackTrace: stack,
      );
      return false;
    } finally {
      saving = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(
      player.dispose().catchError((Object e, StackTrace stack) {
        logger.error('Audio dispose failed', error: e, stackTrace: stack);
      }),
    );
    super.dispose();
  }
}
