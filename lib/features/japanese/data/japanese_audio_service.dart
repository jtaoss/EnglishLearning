import 'package:flutter/foundation.dart';
import 'package:english_learning/features/japanese/domain/gojuon_data.dart';
import 'package:english_learning/features/japanese/domain/japanese_vocab_entry.dart';
import 'package:english_learning/features/pronunciation/local_speech.dart';

enum JapaneseAudioStatus {
  played('播放成功'),
  noVoice('未安装日语语音'),
  unsupported('不支持的平台'),
  error('播放异常');

  const JapaneseAudioStatus(this.label);
  final String label;
}

@immutable
final class JapaneseAudioResult {
  const JapaneseAudioResult({required this.status, required this.message});

  final JapaneseAudioStatus status;
  final String message;

  bool get isSuccess => status == JapaneseAudioStatus.played;
}

/// Safe Japanese audio playback service.
/// Explicitly refuses to play Japanese text through English or incompatible TTS voices.
final class JapaneseAudioService {
  JapaneseAudioService({LocalSpeech? localSpeech})
    : _speech = localSpeech ?? defaultLocalSpeech();

  final LocalSpeech? _speech;

  /// Attempt to play pronunciation for a Kana item.
  Future<JapaneseAudioResult> playKana(KanaItem kana) async {
    return _speakJapanese(kana.hiragana, kana.romaji);
  }

  /// Attempt to play pronunciation for a vocabulary entry.
  Future<JapaneseAudioResult> playWord(JapaneseVocabEntry entry) async {
    // Prefer reading kana if available, otherwise headword
    final textToSpeak = entry.kana.isNotEmpty ? entry.kana : entry.japanese;
    return _speakJapanese(textToSpeak, entry.romajiOriginal);
  }

  Future<JapaneseAudioResult> _speakJapanese(
    String text,
    String romajiHint,
  ) async {
    if (_speech == null) {
      return const JapaneseAudioResult(
        status: JapaneseAudioStatus.unsupported,
        message: '当前平台或环境不支持本地语音合成。',
      );
    }

    try {
      final voice = await _speech.voice();
      if (voice == null) {
        return const JapaneseAudioResult(
          status: JapaneseAudioStatus.noVoice,
          message: '当前系统未检测到可用语音合成引擎。未播放发音。',
        );
      }

      final locale = voice.locale.toLowerCase();
      // Strict Japanese check: must be ja or ja-JP. Never use en-US or zh-CN.
      final isJapanese = locale.startsWith('ja');
      if (!isJapanese) {
        return JapaneseAudioResult(
          status: JapaneseAudioStatus.noVoice,
          message:
              '当前系统语音引擎（${voice.name} · $locale）不是日语语音包。已拦截播放，避免发生错误发音。请在 Windows 设置中安装「日语」语音。',
        );
      }

      var started = false;
      await _speech.speak(
        text,
        onStarted: () {
          started = true;
        },
      );

      return JapaneseAudioResult(
        status: started
            ? JapaneseAudioStatus.played
            : JapaneseAudioStatus.error,
        message: '已通过系统日语语音播放。',
      );
    } catch (e) {
      return JapaneseAudioResult(
        status: JapaneseAudioStatus.error,
        message: '播放失败: $e',
      );
    }
  }

  Future<void> stop() async {
    await _speech?.stop();
  }

  Future<void> dispose() async {
    await _speech?.dispose();
  }
}
