import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:english_learning/features/pronunciation/pronunciation_page.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_session.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:english_learning/features/pronunciation/local_speech.dart';

/// Self-reading remains available when no licensed recording exists.
final class WordReadingPractice extends StatefulWidget {
  const WordReadingPractice({
    super.key,
    required this.entry,
    required this.services,
    this.onSaved,
    this.clock,
    this.onPlaybackBusyChanged,
  });
  final VocabularyEntry entry;
  final PronunciationServices services;
  final Future<void> Function()? onSaved;
  final DateTime Function()? clock;
  final ValueChanged<bool>? onPlaybackBusyChanged;
  @override
  State<WordReadingPractice> createState() => _WordReadingPracticeState();
}

class _WordReadingPracticeState extends State<WordReadingPractice>
    with WidgetsBindingObserver {
  PronunciationSession? _audio;
  PronunciationProgress _progress = const PronunciationProgress();
  bool _loading = true, _read = false, _saving = false, _saved = false;
  bool _audioNotified = false;
  bool _lastBusy = false;
  String? _error;
  String _attempt = '';
  DateTime? _attemptAt;
  LocalSpeech? _speech;
  LocalVoice? _voice;
  bool _ttsPlaying = false, _ttsCompleted = false;
  int _ttsGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    PronunciationSession? audio;
    try {
      audio = await widget.services.open(widget.entry.id, widget.entry.word);
      final progress =
          audio?.progress ??
          await widget.services.store.readPronunciation(widget.entry.id);
      LocalSpeech? speech;
      LocalVoice? voice;
      if (audio == null) {
        speech = widget.services.speechFactory();
        voice = await speech?.voice();
      }
      if (!mounted) {
        audio?.dispose();
        await speech?.dispose();
        return;
      }
      _audio = audio;
      _speech = speech;
      _voice = voice;
      audio?.addListener(_audioChanged);
      setState(() {
        _progress = progress;
        _loading = false;
      });
    } catch (_) {
      audio?.dispose();
      if (mounted) {
        setState(() {
          _error = '认读记录暂时无法读取，请重试。';
          _loading = false;
        });
      }
    }
  }

  void _audioChanged() {
    final busy = _audio?.busy ?? false;
    if (busy != _lastBusy) {
      _lastBusy = busy;
      widget.onPlaybackBusyChanged?.call(busy);
    }
    final saved = _audio?.saved ?? false;
    if (saved && !_audioNotified) _notifySaved();
    _audioNotified = saved;
  }

  void _notifySaved() {
    final callback = widget.onSaved;
    final logger = widget.services.logger;
    if (callback != null) {
      unawaited(
        callback().catchError((Object error, StackTrace stack) {
          logger.error(
            'Reading saved; vocabulary refresh failed',
            error: error,
            stackTrace: stack,
          );
        }),
      );
    }
  }

  Future<void> _assess(PronunciationGrade grade) async {
    if (!_read ||
        _saving ||
        _saved ||
        _ttsPlaying ||
        (_voice != null && !_ttsCompleted)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final at = _attemptAt ??= (widget.clock ?? DateTime.now)().toUtc();
    try {
      final source = _ttsCompleted
          ? _voice!.sourceId
          : 'self-reading:${widget.entry.id}';
      await widget.services.store.recordPronunciation(
        entryId: widget.entry.id,
        grade: grade,
        audioAssetId: source,
        attemptId: _attempt,
        at: at,
      );
      if (!mounted) return;
      setState(() {
        _progress = PronunciationProgress(
          grade: grade,
          assessedAt: at,
          sourceId: source,
        );
        _saved = true;
      });
      _notifySaved();
    } catch (_) {
      if (mounted) setState(() => _error = '发音自评保存失败，请重试。词义记录未改变。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _playTts({bool contextSentence = false}) async {
    if (!_read || _voice == null || _ttsPlaying || _saving) return;
    final generation = ++_ttsGeneration;
    _attemptAt = null;
    _attempt = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    setState(() {
      _ttsPlaying = true;
      _ttsCompleted = false;
      _saved = false;
      _error = null;
    });
    widget.onPlaybackBusyChanged?.call(true);
    try {
      final text = contextSentence
          ? widget.entry.fields['example_en']!
          : widget.entry.word;
      await _speech!.speak(text, onStarted: () {});
      if (mounted && generation == _ttsGeneration) {
        setState(() => _ttsCompleted = true);
      }
    } catch (_) {
      if (mounted && generation == _ttsGeneration) {
        setState(() => _error = 'TTS 播放未完成，未记录发音练习。可重试或继续词义学习。');
      }
      if (generation == _ttsGeneration) await _speech?.stop();
    } finally {
      if (mounted && generation == _ttsGeneration) {
        setState(() => _ttsPlaying = false);
        widget.onPlaybackBusyChanged?.call(false);
      }
    }
  }

  Future<void> _stopTts() async {
    ++_ttsGeneration;
    await _speech?.stop();
    if (mounted) {
      setState(() {
        _ttsPlaying = false;
        _ttsCompleted = false;
      });
      widget.onPlaybackBusyChanged?.call(false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && (_audio?.busy ?? false)) {
      unawaited(_audio!.stop());
    }
    if (state != AppLifecycleState.resumed && _ttsPlaying) {
      unawaited(_stopTts());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audio?.removeListener(_audioChanged);
    _audio?.dispose();
    ++_ttsGeneration;
    unawaited(_speech?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator();
    if (_audio != null) return PronunciationPractice(session: _audio!);
    if (_error != null && !_read) {
      return Column(
        children: [
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('重试读取')),
        ],
      );
    }
    final fields = widget.entry.fields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('发音自评：${_progress.label}', key: const Key('pronunciation-status')),
        if (_progress.grade != null)
          Text(
            '上次核对来源：${_progress.sourceLabel}',
            key: const Key('reading-source'),
          ),
        if (_progress.dueAt != null)
          Text('下次认读复习：${_progress.dueAt!.toLocal()}'),
        if (_error != null)
          Text(_error!, key: const Key('pronunciation-error')),
        if (!_read) ...[
          const Text('先看英文，自主读一遍，再查看拼读、音节与重音提示。'),
          OutlinedButton(
            key: const Key('confirm-self-reading'),
            onPressed: () {
              _attemptAt = null;
              _attempt = List.generate(
                16,
                (_) => Random.secure()
                    .nextInt(256)
                    .toRadixString(16)
                    .padLeft(2, '0'),
              ).join();
              setState(() {
                _read = true;
                _saved = false;
                _ttsCompleted = false;
              });
            },
            child: const Text('我已自主认读'),
          ),
        ] else ...[
          Text(
            fields['phonics_note']?.isNotEmpty == true
                ? fields['phonics_note']!
                : '拼读提示待核验，请勿仅凭拼写猜测读音。',
            key: const Key('phonics-note'),
          ),
          Text(
            '音节：${fields['syllables']?.isNotEmpty == true ? fields['syllables'] : '待补充'}',
          ),
          Text(
            '重音：${fields['stress']?.isNotEmpty == true ? fields['stress'] : '待核验'}',
            key: const Key('word-stress'),
          ),
          Text(fields['reading_review_status'] ?? '认读提示待核验'),
          const SizedBox(height: 8),
          const Text('此词尚未配置已授权音频。词义学习仍可继续。', key: Key('audio-missing')),
          if (_voice != null) ...[
            Text(
              'Windows 本地 TTS（合成语音）· ${_voice!.name} · ${_voice!.locale}',
              key: const Key('tts-source'),
            ),
            const Text('系统合成语音用于备用核对，不是真人录音；多读音请结合词性和提示。'),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  key: const Key('play-local-tts'),
                  onPressed: _ttsPlaying || _saving ? null : () => _playTts(),
                  child: Text(_ttsCompleted ? '再次播放系统 TTS' : '播放系统 TTS'),
                ),
                if (fields['example_en']?.isNotEmpty == true)
                  OutlinedButton(
                    key: const Key('play-local-tts-context'),
                    onPressed: _ttsPlaying || _saving
                        ? null
                        : () => _playTts(contextSentence: true),
                    child: const Text('播放例句核对多音'),
                  ),
                if (_ttsPlaying)
                  TextButton(
                    key: const Key('stop-local-tts'),
                    onPressed: _stopTts,
                    child: const Text('停止'),
                  ),
              ],
            ),
            Text(
              _ttsPlaying
                  ? '正在播放系统 TTS…'
                  : _ttsCompleted
                  ? '系统 TTS 已完整播放，可评发音。'
                  : '完整播放后再评发音；也可跳过听音，仅完成词义复习。',
              key: const Key('tts-playback-status'),
            ),
          ] else ...[
            const Text('本机未提供可用的美式英语本地 TTS。下面仅保存自主认读自评，未经过录音核对。'),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final grade in PronunciationGrade.values)
                OutlinedButton(
                  key: ValueKey('pronunciation-grade-${grade.name}'),
                  onPressed:
                      _saving ||
                          _saved ||
                          _ttsPlaying ||
                          (_voice != null && !_ttsCompleted)
                      ? null
                      : () => _assess(grade),
                  child: Text(grade.label),
                ),
            ],
          ),
          if (_saving) const LinearProgressIndicator(),
          if (_saved) ...[
            const Text('发音自评已保存', key: Key('pronunciation-saved')),
            TextButton(
              onPressed: () => setState(() {
                _read = false;
              }),
              child: const Text('再练习一次'),
            ),
          ],
        ],
      ],
    );
  }
}
