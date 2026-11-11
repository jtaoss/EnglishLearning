import 'dart:async';

import 'package:flutter/material.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_session.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:english_learning/features/pronunciation/word_reading_practice.dart';
import 'package:english_learning/ui/status_badge.dart';

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
          constraints: const BoxConstraints(maxWidth: 760),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: SectionCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusBanner(
                          message: _loadError!,
                          tone: BannerTone.danger,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : _session == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: widget.entry != null
                      ? SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SectionCard(
                                child: Text(
                                  widget.word,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge,
                                ),
                              ),
                              const SizedBox(height: 16),
                              WordReadingPractice(
                                entry: widget.entry!,
                                services: widget.services,
                                onSaved: widget.onSaved,
                              ),
                            ],
                          ),
                        )
                      : const SectionCard(
                          child: Text(
                            '此词尚未配置已授权音频。词义学习仍可继续。',
                            key: Key('audio-missing'),
                          ),
                        ),
                )
              : PronunciationPractice(session: _session!),
        ),
      ),
    ),
  );
}

final class PronunciationPractice extends StatelessWidget {
  const PronunciationPractice({
    required this.session,
    this.embedded = false,
    super.key,
  });
  final PronunciationSession session;
  final bool embedded;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final c = session;
      final content = c.content;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final brightness = theme.brightness;

      final body = SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!embedded) ...[
              Text(content.word, style: theme.textTheme.headlineLarge),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.headphones_outlined,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '真人标准音频与自然拼读',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                StatusBadge(
                  label: '发音自评：${c.progress.label}',
                  status: c.progress.grade?.name ?? c.progress.label,
                  textKey: const Key('pronunciation-status'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (c.progress.dueAt != null)
                  Text(
                    '下次认读复习：${formatLocalDateTime(c.progress.dueAt!)}',
                    style: theme.textTheme.bodySmall,
                  ),
                if (c.progress.grade != null)
                  Text(
                    '上次核对来源：${c.progress.sourceLabel}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '自评用于个人练习，不是自动发音评分；词义复习记录单独保存。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (!c.triedReading)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(
                        '先看英文，自主读一遍。确认后再显示提示和播放录音。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      key: const Key('confirm-self-reading'),
                      onPressed: c.confirmReading,
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('我已自主认读'),
                    ),
                  ],
                ),
              ),
            if (c.triedReading) ...[
              Container(
                padding: const EdgeInsets.all(14),
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
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusBadge(
                          label: content.listenToRemember
                              ? '建议听音记忆'
                              : '常见自然拼读提示',
                          colors: content.listenToRemember
                              ? AppTheme.familiarColors(brightness)
                              : AppTheme.infoColors(brightness),
                          textKey: const Key('phonics-kind'),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Text(
                            '字母提示：${content.segments.join(' · ')}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Text(
                            content.syllables.length == 1
                                ? '单音节词'
                                : '重音提示：${content.stressDisplay}（大写部分重读）',
                            key: const Key('word-stress'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      content.note,
                      key: const Key('phonics-note'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '分块仅作本词认读提示，不代表可推广到所有同形拼写。',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      content.reviewStatus,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          key: const Key('play-pronunciation'),
                          onPressed: c.busy || c.saving ? null : c.play,
                          icon: const Icon(Icons.volume_up_outlined, size: 18),
                          label: Text(
                            c.phase == PlaybackPhase.loading
                                ? '正在加载…'
                                : '听音核对 · 美式',
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const Key('stop-pronunciation'),
                          onPressed: c.busy ? c.stop : null,
                          icon: const Icon(
                            Icons.stop_circle_outlined,
                            size: 18,
                          ),
                          label: const Text('停止'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      switch (c.phase) {
                        PlaybackPhase.idle => '等待播放',
                        PlaybackPhase.loading => '正在准备本地音频',
                        PlaybackPhase.playing => '正在播放',
                        PlaybackPhase.completed => '播放完成，请对照后自评',
                        PlaybackPhase.stopped => '已停止；完整听音后可自评',
                        PlaybackPhase.failed => '播放未完成',
                      },
                      key: const Key('playback-state'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.phase == PlaybackPhase.completed
                            ? AppTheme.masteredColors(brightness).foreground
                            : scheme.onSurfaceVariant,
                        fontWeight: c.phase == PlaybackPhase.completed
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (c.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        c.error!,
                        key: const Key('pronunciation-error'),
                        style: TextStyle(color: scheme.error),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '发音自评（听音核对后选择）',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final grade in PronunciationGrade.values)
                    _buildGradeButton(context, c, grade),
                ],
              ),
              if (c.saving) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
              if (c.saved) ...[
                const SizedBox(height: 10),
                const StatusBadge(
                  label: '发音自评已保存',
                  status: 'mastered',
                  icon: Icons.check_circle_outline,
                  textKey: Key('pronunciation-saved'),
                ),
              ],
            ],
            const SizedBox(height: 16),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('录音来源与许可', style: theme.textTheme.titleSmall),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    '美式社区真人录音 · ${content.author}\n${content.license}\n${content.sourceUrl}\n${content.licenseUrl}\n'
                    '${content.changes}\n允许本地缓存与离线播放。非考试官方录音。\n'
                    '提示核对来源：\n${content.evidenceUrls.join('\n')}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      if (embedded) return body;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: body,
      );
    },
  );

  Widget _buildGradeButton(
    BuildContext context,
    PronunciationSession c,
    PronunciationGrade grade,
  ) {
    final brightness = Theme.of(context).brightness;
    final palette = AppTheme.statusColorsFor(grade.name, brightness);
    final enabled = c.canAssess;
    return OutlinedButton(
      key: ValueKey('pronunciation-grade-${grade.name}'),
      style: enabled
          ? OutlinedButton.styleFrom(
              foregroundColor: palette.foreground,
              backgroundColor: palette.background.withValues(alpha: 0.55),
              side: BorderSide(color: palette.border, width: 1.2),
            )
          : null,
      onPressed: enabled ? () => c.assess(grade) : null,
      child: Text(grade.label),
    );
  }
}
