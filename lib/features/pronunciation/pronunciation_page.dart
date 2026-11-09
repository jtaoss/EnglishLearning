import 'dart:async';

import 'package:flutter/material.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_session.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:english_learning/features/pronunciation/word_reading_practice.dart';

final class PronunciationPage extends StatefulWidget {
  const PronunciationPage({
    required this.entryId,
    required this.word,
    required this.services,
    this.entry,
    this.onSaved,
    super.key,
  });
  final String entryId, word;
  final PronunciationServices services;
  final VocabularyEntry? entry;
  final Future<void> Function()? onSaved;
  @override
  State<PronunciationPage> createState() => _PronunciationPageState();
}

class _PronunciationPageState extends State<PronunciationPage>
    with WidgetsBindingObserver {
  PronunciationSession? _session;
  bool _loading = true;
  String? _loadError;
  bool _savedNotified = false;

  void _changed() {
    final saved = _session?.saved ?? false;
    final callback = widget.onSaved;
    final logger = widget.services.logger;
    if (saved && !_savedNotified && callback != null) {
      unawaited(
        callback().catchError((Object error, StackTrace stack) {
          logger.error(
            'Reading saved; refresh failed',
            error: error,
            stackTrace: stack,
          );
        }),
      );
    }
    _savedNotified = saved;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final session = await widget.services.open(widget.entryId, widget.word);
      if (!mounted) {
        session?.dispose();
        return;
      }
      setState(() {
        _session = session;
        session?.addListener(_changed);
        _loading = false;
      });
    } catch (e, stack) {
      widget.services.logger.error(
        'Pronunciation page load failed',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        setState(() {
          _loadError = '发音资源暂时无法加载，请重试。';
          _loading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      final session = _session;
      if (session != null && session.busy) unawaited(session.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session?.removeListener(_changed);
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('认读与听音')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _loading
              ? const CircularProgressIndicator()
              : _loadError != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!),
                    TextButton(onPressed: _load, child: const Text('重试')),
                  ],
                )
              : _session == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: widget.entry != null
                      ? SingleChildScrollView(
                          child: WordReadingPractice(
                            entry: widget.entry!,
                            services: widget.services,
                            onSaved: widget.onSaved,
                          ),
                        )
                      : const Text(
                          '此词尚未配置已授权音频。词义学习仍可继续。',
                          key: Key('audio-missing'),
                        ),
                )
              : PronunciationPractice(session: _session!),
        ),
      ),
    ),
  );
}

final class PronunciationPractice extends StatelessWidget {
  const PronunciationPractice({required this.session, super.key});
  final PronunciationSession session;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final c = session;
      final content = c.content;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              content.word,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            Text(
              '发音自评：${c.progress.label}',
              key: const Key('pronunciation-status'),
            ),
            if (c.progress.dueAt != null)
              Text('下次认读复习：${c.progress.dueAt!.toLocal()}'),
            if (c.progress.grade != null)
              Text('上次核对来源：${c.progress.sourceLabel}'),
            const Text('自评用于个人练习，不是自动发音评分；词义复习记录单独保存。'),
            const SizedBox(height: 24),
            if (!c.triedReading) ...[
              const Text('先看英文，自主读一遍。确认后再显示提示和播放录音。'),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('confirm-self-reading'),
                onPressed: c.confirmReading,
                child: const Text('我已自主认读'),
              ),
            ],
            if (c.triedReading) ...[
              Text(
                content.listenToRemember ? '建议听音记忆' : '常见自然拼读提示',
                key: const Key('phonics-kind'),
              ),
              Text('字母提示：${content.segments.join(' · ')}'),
              Text(content.note, key: const Key('phonics-note')),
              const SizedBox(height: 12),
              Text(
                content.syllables.length == 1
                    ? '单音节词'
                    : '重音提示：${content.stressDisplay}（大写部分重读）',
                key: const Key('word-stress'),
              ),
              const Text('分块仅作本词认读提示，不代表可推广到所有同形拼写。'),
              Text(content.reviewStatus),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('play-pronunciation'),
                    onPressed: c.busy || c.saving ? null : c.play,
                    icon: const Icon(Icons.volume_up_outlined),
                    label: Text(
                      c.phase == PlaybackPhase.loading ? '正在加载…' : '听音核对 · 美式',
                    ),
                  ),
                  OutlinedButton(
                    key: const Key('stop-pronunciation'),
                    onPressed: c.busy ? c.stop : null,
                    child: const Text('停止'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(switch (c.phase) {
                PlaybackPhase.idle => '等待播放',
                PlaybackPhase.loading => '正在准备本地音频',
                PlaybackPhase.playing => '正在播放',
                PlaybackPhase.completed => '播放完成，请对照后自评',
                PlaybackPhase.stopped => '已停止；完整听音后可自评',
                PlaybackPhase.failed => '播放未完成',
              }, key: const Key('playback-state')),
              if (c.error != null)
                Text(
                  c.error!,
                  key: const Key('pronunciation-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final grade in PronunciationGrade.values)
                    OutlinedButton(
                      key: ValueKey('pronunciation-grade-${grade.name}'),
                      onPressed: c.canAssess ? () => c.assess(grade) : null,
                      child: Text(grade.label),
                    ),
                ],
              ),
              if (c.saving) const LinearProgressIndicator(),
              if (c.saved)
                const Text('发音自评已保存', key: Key('pronunciation-saved')),
            ],
            const SizedBox(height: 24),
            ExpansionTile(
              title: const Text('录音来源与许可'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    '美式社区真人录音 · ${content.author}\n${content.license}\n${content.sourceUrl}\n${content.licenseUrl}\n'
                    '${content.changes}\n允许本地缓存与离线播放。非考试官方录音。\n'
                    '提示核对来源：\n${content.evidenceUrls.join('\n')}',
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
