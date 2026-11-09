import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:english_learning/features/pronunciation/standard_audio_player.dart';

final class LocalVoice {
  const LocalVoice(this.name, this.locale);
  final String name, locale;
  String get sourceId => 'windows-tts:sapi:$locale:$name';
}

abstract interface class LocalSpeech {
  Future<LocalVoice?> voice();
  Future<void> speak(String word, {required void Function() onStarted});
  Future<void> stop();
  Future<void> dispose();
}

LocalSpeech? defaultLocalSpeech() =>
    Platform.isWindows ? WindowsLocalSpeech() : null;

/// Uses only the installed Microsoft Desktop SAPI voice. No audio file exports.
final class WindowsLocalSpeech implements LocalSpeech {
  static const channel = MethodChannel('english_learning/local_speech');
  int _generation = 0;
  int? _nativeId;
  @override
  Future<LocalVoice?> voice() async {
    try {
      final result = await channel.invokeMapMethod<String, dynamic>('voice');
      return result == null
          ? null
          : LocalVoice(result['name'] as String, result['locale'] as String);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> speak(String word, {required void Function() onStarted}) async {
    final generation = ++_generation;
    final id = await channel.invokeMethod<int>('speak', {'text': word});
    if (id == null) throw StateError('Local speech did not start.');
    if (generation != _generation) {
      await channel.invokeMethod<void>('stop', {'id': id});
      throw PlaybackInterrupted();
    }
    _nativeId = id;
    onStarted();
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (generation == _generation) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (generation != _generation) break;
      if (await channel.invokeMethod<bool>('status', {'id': id}) == true) {
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        await stop();
        throw TimeoutException('Local speech timed out.');
      }
    }
    throw PlaybackInterrupted();
  }

  @override
  Future<void> stop() async {
    ++_generation;
    final id = _nativeId;
    _nativeId = null;
    if (id != null) {
      try {
        await channel.invokeMethod<void>('stop', {'id': id});
      } on PlatformException {
        /* Already superseded or finished. */
      }
    }
  }

  @override
  Future<void> dispose() => stop();
}
