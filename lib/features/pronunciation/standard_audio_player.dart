import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

abstract interface class StandardAudioPlayer {
  Future<void> playFile(String path, {required void Function() onStarted});
  Future<void> stop();
  Future<void> dispose();
}

final class PlaybackInterrupted implements Exception {}

/// A new native player for each attempt keeps late completion events isolated.
final class AudioplayersStandardAudioPlayer implements StandardAudioPlayer {
  AudioPlayer? _player;
  Completer<void>? _completion;
  StreamSubscription<void>? _completedSubscription;
  StreamSubscription<AudioEvent>? _errorSubscription;
  int _generation = 0;

  @override
  Future<void> playFile(
    String path, {
    required void Function() onStarted,
  }) async {
    final generation = ++_generation;
    await _clear();
    if (generation != _generation) throw PlaybackInterrupted();
    final player = AudioPlayer();
    _player = player;
    final done = Completer<void>();
    _completion = done;
    // Attach an error listener before native preparation can emit an error.
    unawaited(done.future.catchError((Object _) {}));
    _completedSubscription = player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    _errorSubscription = player.eventStream.listen(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
    );
    await player.setReleaseMode(ReleaseMode.stop);
    if (_player != player) throw PlaybackInterrupted();
    await player.play(DeviceFileSource(path));
    if (_player != player) throw PlaybackInterrupted();
    onStarted();
    try {
      await done.future;
    } finally {
      // Release the completed attempt before the UI offers another playback.
      // Ownership check prevents an old attempt from disposing a newer player.
      if (_player == player) await _clear();
    }
  }

  @override
  Future<void> stop() async {
    ++_generation;
    await _clear();
  }

  Future<void> _clear() async {
    final player = _player;
    _player = null;
    final done = _completion;
    _completion = null;
    if (done != null && !done.isCompleted) {
      done.completeError(PlaybackInterrupted());
    }
    await _completedSubscription?.cancel();
    await _errorSubscription?.cancel();
    _completedSubscription = null;
    _errorSubscription = null;
    if (player != null) await player.dispose();
  }

  @override
  Future<void> dispose() => stop();
}
