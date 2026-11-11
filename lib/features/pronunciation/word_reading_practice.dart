import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/features/pronunciation/pronunciation_page.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_session.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:english_learning/features/pronunciation/local_speech.dart';
import 'package:english_learning/ui/status_badge.dart';

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
    if (_audio != null) {
      return PronunciationPractice(session: _audio!, embedded: true);
    }
    if (_error != null && !_read) {
      return SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusBanner(message: _error!, tone: BannerTone.danger),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试读取'),
            ),
          ],
        ),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final fields = widget.entry.fields;
    final canGrade =
        !_saving &&
        !_saved &&
        !_ttsPlaying &&
        (_voice == null || _ttsCompleted);

    return SectionCard(
      backgroundColor: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.record_voice_over_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '自然拼读与发音练习',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_progress.grade != null)
                    Text(
                      '上次核对来源：${_progress.sourceLabel}',
                      key: const Key('reading-source'),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (_progress.dueAt != null)
                    Text(
                      '下次认读复习：${formatLocalDateTime(_progress.dueAt!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  StatusBadge(
                    label: '发音自评：${_progress.label}',
                    status: _progress.grade?.name ?? _progress.label,
                    textKey: const Key('pronunciation-status'),
                  ),
                ],
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            StatusBanner(
              message: _error!,
              tone: BannerTone.danger,
              textKey: const Key('pronunciation-error'),
            ),
          ],
          const SizedBox(height: 10),
          if (!_read)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Text(
                      '先看英文，自主读一遍，再查看拼读、音节与重音提示。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
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
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('我已自主认读'),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Text(
                          '音节：${fields['syllables']?.isNotEmpty == true ? fields['syllables'] : '待补充'}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Text(
                          '重音：${fields['stress']?.isNotEmpty == true ? fields['stress'] : '待核验'}',
                          key: const Key('word-stress'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        fields['reading_review_status'] ?? '认读提示待核验',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fields['phonics_note']?.isNotEmpty == true
                        ? fields['phonics_note']!
                        : '拼读提示待核验，请勿仅凭拼写猜测读音。',
                    key: const Key('phonics-note'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const Divider(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.graphic_eq_outlined,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '此词尚未配置已授权音频。词义学习仍可继续。',
                              key: const Key('audio-missing'),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      if (_voice != null)
                        Text(
                          'Windows 本地 TTS（合成语音）· ${_voice!.name} · ${_voice!.locale}',
                          key: const Key('tts-source'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                    ],
                  ),
                  if (_voice != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '系统合成语音用于备用核对，不是真人录音；多读音请结合词性和提示。',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('play-local-tts'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _ttsPlaying || _saving
                              ? null
                              : () => _playTts(),
                          icon: Icon(
                            _ttsCompleted
                                ? Icons.replay_outlined
                                : Icons.volume_up_outlined,
                            size: 17,
                          ),
                          label: Text(
                            _ttsCompleted ? '再次播放系统 TTS' : '播放系统 TTS',
                          ),
                        ),
                        if (fields['example_en']?.isNotEmpty == true)
                          OutlinedButton.icon(
                            key: const Key('play-local-tts-context'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _ttsPlaying || _saving
                                ? null
                                : () => _playTts(contextSentence: true),
                            icon: const Icon(
                              Icons.record_voice_over_outlined,
                              size: 17,
                            ),
                            label: const Text('播放例句核对多音'),
                          ),
                        if (_ttsPlaying)
                          TextButton.icon(
                            key: const Key('stop-local-tts'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _stopTts,
                            icon: const Icon(
                              Icons.stop_circle_outlined,
                              size: 17,
                            ),
                            label: const Text('停止'),
                          ),
                        Text(
                          _ttsPlaying
                              ? '正在播放系统 TTS…'
                              : _ttsCompleted
                              ? '系统 TTS 已完整播放，可评发音。'
                              : '完整播放后再评发音；也可跳过听音，仅完成词义复习。',
                          key: const Key('tts-playback-status'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _ttsCompleted
                                ? AppTheme.masteredColors(brightness).foreground
                                : scheme.onSurfaceVariant,
                            fontWeight: _ttsCompleted
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 4),
                    Text(
                      '本机未提供可用的美式英语本地 TTS。下面仅保存自主认读自评，未经过录音核对。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  '发音自评（与下方词义评级独立保存）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    for (final grade in PronunciationGrade.values)
                      _buildPronunciationGradeButton(
                        context: context,
                        grade: grade,
                        enabled: canGrade,
                      ),
                  ],
                ),
              ],
            ),
            if (_saving) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if (_saved) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(
                    label: '发音自评已保存',
                    status: 'mastered',
                    icon: Icons.check_circle_outline,
                    textKey: const Key('pronunciation-saved'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _read = false;
                    }),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('再练习一次'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPronunciationGradeButton({
    required BuildContext context,
    required PronunciationGrade grade,
    required bool enabled,
  }) {
    final brightness = Theme.of(context).brightness;
    final palette = AppTheme.statusColorsFor(grade.name, brightness);
    return OutlinedButton(
      key: ValueKey('pronunciation-grade-${grade.name}'),
      style: enabled
          ? OutlinedButton.styleFrom(
              foregroundColor: palette.foreground,
              backgroundColor: palette.background.withValues(alpha: 0.55),
              side: BorderSide(color: palette.border, width: 1.2),
              visualDensity: VisualDensity.compact,
            )
          : OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
      onPressed: enabled ? () => _assess(grade) : null,
      child: Text(grade.label),
    );
  }
}
