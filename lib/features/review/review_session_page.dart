import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/word_reading_practice.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/review/study_queue.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:english_learning/ui/status_badge.dart';

enum ReviewSessionMode {
  /// Mode 1: Due meaning review session (only studied words with `dueAt <= now`).
  due,

  /// Mode 2: Weak word consolidation (`forgotten` and `familiar` words).
  weak,
}

final class ReviewSessionPage extends StatefulWidget {
  const ReviewSessionPage({
    required this.controller,
    required this.mode,
    this.pronunciation,
    super.key,
  });

  final VocabularyController controller;
  final ReviewSessionMode mode;
  final PronunciationServices? pronunciation;

  @override
  State<ReviewSessionPage> createState() => _ReviewSessionPageState();
}

class _ReviewSessionPageState extends State<ReviewSessionPage> {
  final FocusNode _keyboardFocusNode = FocusNode(
    debugLabel: 'ReviewSessionKeyboardFocus',
  );
  bool _initialized = false;
  List<String> _sessionIds = const [];
  int _currentIndex = 0;
  bool _revealed = false;
  bool _saving = false;
  bool _playbackBusy = false;
  bool _allowFormalGradeInWeakMode = false;

  /// Formal grades recorded during this session (`entryId -> ReviewGrade`).
  final Map<String, ReviewGrade> _formalResults = {};

  /// Temporary practice outcomes recorded in weak mode (`entryId -> remembered`).
  final Map<String, bool> _tempPracticeResults = {};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _tryInitQueue();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!_initialized && widget.controller.loaded) {
      setState(_tryInitQueue);
    }
  }

  void _tryInitQueue() {
    if (_initialized || !widget.controller.loaded) return;
    final now = widget.controller.nowUtc;
    final words = switch (widget.mode) {
      ReviewSessionMode.due => widget.controller.dueReviewWords(now),
      ReviewSessionMode.weak => widget.controller.weakReviewWords(now),
    };
    _sessionIds = words.map((w) => w.entry.id).toList(growable: false);
    _initialized = true;
  }

  StudyWord? get _currentWord {
    if (!_initialized || _currentIndex >= _sessionIds.length) return null;
    return widget.controller.find(_sessionIds[_currentIndex]);
  }

  bool get _canGradeFormal => !_saving && !_playbackBusy && _revealed;

  bool _isEditableTextFocused() {
    final primary = FocusManager.instance.primaryFocus;
    final context = primary?.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_isEditableTextFocused()) return KeyEventResult.ignored;
    final current = _currentWord;
    if (current == null || _saving || _playbackBusy) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      if (!_revealed) {
        setState(() => _revealed = true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (!_revealed) return KeyEventResult.ignored;

    if (widget.mode == ReviewSessionMode.due || _allowFormalGradeInWeakMode) {
      if (key == LogicalKeyboardKey.digit1 ||
          key == LogicalKeyboardKey.numpad1) {
        unawaited(_submitFormalGrade(current.entry, ReviewGrade.forgotten));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit2 ||
          key == LogicalKeyboardKey.numpad2) {
        unawaited(_submitFormalGrade(current.entry, ReviewGrade.familiar));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit3 ||
          key == LogicalKeyboardKey.numpad3) {
        unawaited(_submitFormalGrade(current.entry, ReviewGrade.mastered));
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _submitFormalGrade(
    VocabularyEntry entry,
    ReviewGrade grade,
  ) async {
    if (!_canGradeFormal) return;
    setState(() => _saving = true);
    final ok = await widget.controller.review(
      entry.id,
      grade,
      widget.controller.nowUtc,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _formalResults[entry.id] = grade;
        _advanceToNext();
      }
    });
  }

  void _submitTemporaryPractice(
    VocabularyEntry entry, {
    required bool remembered,
  }) {
    if (_saving || _playbackBusy || !_revealed) return;
    setState(() {
      _tempPracticeResults[entry.id] = remembered;
      _advanceToNext();
    });
  }

  void _advanceToNext() {
    _currentIndex++;
    _revealed = false;
    _playbackBusy = false;
    _allowFormalGradeInWeakMode = false;
  }

  void _openNewWords(BuildContext context) {
    final nextNew = widget.controller.newLearnableWords().firstOrNull;
    if (nextNew != null) {
      context.pushReplacement(AppRouter.wordPath(nextNew.entry.id));
    } else {
      context.pushReplacement(AppRouter.vocabulary);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      if (!_initialized && widget.controller.loaded) {
        _tryInitQueue();
      }
      final title = switch (widget.mode) {
        ReviewSessionMode.due => '今日到期复习',
        ReviewSessionMode.weak => '薄弱词专项巩固',
      };

      return Focus(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              if (_initialized &&
                  _sessionIds.isNotEmpty &&
                  _currentIndex < _sessionIds.length)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: StatusBadge(
                      label: '进度 ${_currentIndex + 1} / ${_sessionIds.length}',
                      status: 'neutral',
                      textKey: const Key('session-progress-badge'),
                    ),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: !_initialized
                    ? const Center(child: CircularProgressIndicator())
                    : _sessionIds.isEmpty
                    ? _buildEmptyState(context)
                    : _currentIndex >= _sessionIds.length
                    ? _buildCompletionState(context)
                    : _buildActiveCard(context, _currentWord!),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final isDueMode = widget.mode == ReviewSessionMode.due;
    final hasNewWords = widget.controller.newLearnableWords().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: SectionCard(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isDueMode
                      ? Icons.event_available_outlined
                      : Icons.check_circle_outline,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isDueMode ? '暂无今日到期复习任务' : '暂无薄弱词记录',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isDueMode ? '今天暂无到期复习，先去学习一些新词吧。' : '当前暂无被评为「遗忘」或「眼熟」的薄弱词记录。',
              key: isDueMode
                  ? const Key('no-due-review-hint')
                  : const Key('no-weak-words-hint'),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                if (hasNewWords)
                  FilledButton.icon(
                    key: const Key('start-new-words'),
                    onPressed: () => _openNewWords(context),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('去学习新词'),
                  ),
                OutlinedButton.icon(
                  key: const Key('back-home'),
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('返回首页'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionState(BuildContext context) {
    final theme = Theme.of(context);
    final isDueMode = widget.mode == ReviewSessionMode.due;
    final mastered = _formalResults.values
        .where((g) => g == ReviewGrade.mastered)
        .length;
    final familiar = _formalResults.values
        .where((g) => g == ReviewGrade.familiar)
        .length;
    final forgotten = _formalResults.values
        .where((g) => g == ReviewGrade.forgotten)
        .length;
    final rememberedTemp = _tempPracticeResults.values.where((v) => v).length;
    final againTemp = _tempPracticeResults.values.where((v) => !v).length;
    final stats = widget.controller.dashboardStats();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SectionCard(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.task_alt_rounded,
                  color: theme.colorScheme.primary,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isDueMode ? '今日到期复习已完成' : '薄弱词巩固练习已完成',
                    key: isDueMode
                        ? const Key('review-session-complete')
                        : const Key('weak-session-complete'),
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isDueMode
                  ? '本轮共完成 ${_sessionIds.length} 个到期单词的回忆与评级，所有学习进度已实时写入本地 SQLite。'
                  : '本轮共巩固 ${_sessionIds.length} 个薄弱单词。临时巩固不会打乱原有的间隔复习计划。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (_formalResults.isNotEmpty) ...[
                  StatusBadge(
                    label: '本轮掌握：$mastered 词',
                    status: 'mastered',
                    textKey: const Key('summary-mastered-count'),
                  ),
                  StatusBadge(
                    label: '本轮眼熟：$familiar 词',
                    status: 'familiar',
                    textKey: const Key('summary-familiar-count'),
                  ),
                  StatusBadge(
                    label: '本轮遗忘：$forgotten 词',
                    status: 'forgotten',
                    textKey: const Key('summary-forgotten-count'),
                  ),
                ],
                if (_tempPracticeResults.isNotEmpty) ...[
                  StatusBadge(
                    label: '临时记住：$rememberedTemp 词',
                    status: 'mastered',
                    textKey: const Key('summary-temp-remembered'),
                  ),
                  StatusBadge(
                    label: '仍需再记：$againTemp 词',
                    status: 'forgotten',
                    textKey: const Key('summary-temp-again'),
                  ),
                ],
                StatusBadge(
                  label: '当前剩余到期：${stats.remainingReviewCount} 词',
                  status: stats.remainingReviewCount == 0
                      ? 'mastered'
                      : 'familiar',
                  textKey: const Key('summary-remaining-due'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  key: const Key('session-back-home'),
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.home_outlined, size: 18),
                  label: const Text('返回学习首页'),
                ),
                if (isDueMode && stats.weakWordsCount > 0)
                  OutlinedButton.icon(
                    key: const Key('session-open-weak'),
                    onPressed: () =>
                        context.pushReplacement(AppRouter.reviewWeak),
                    icon: const Icon(Icons.fitness_center_outlined, size: 18),
                    label: Text('巩固薄弱词（${stats.weakWordsCount}）'),
                  ),
                if (stats.newLearnableCount > 0)
                  OutlinedButton.icon(
                    key: const Key('session-open-new'),
                    onPressed: () => _openNewWords(context),
                    icon: const Icon(Icons.auto_stories_outlined, size: 18),
                    label: const Text('继续学习新词'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCard(BuildContext context, StudyWord word) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final entry = word.entry;
    final total = _sessionIds.length;
    final currentStep = _currentIndex + 1;
    final remaining = total - _currentIndex;
    final isDueMode = widget.mode == ReviewSessionMode.due;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.controller.error != null) ...[
            StatusBanner(
              message: widget.controller.error!,
              tone: BannerTone.danger,
            ),
            const SizedBox(height: 12),
          ],

          // Session Progress Bar & Mode Banner
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '当前第 $currentStep 词 / 共 $total 词（剩余 $remaining 词）',
                      key: const Key('session-progress-text'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '快捷键：Space 查看答案 · 1 遗忘 · 2 眼熟 · 3 掌握',
                      key: const Key('shortcut-hint'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    key: const Key('session-progress-bar'),
                    value: currentStep / total,
                    minHeight: 6,
                  ),
                ),
                if (!isDueMode) ...[
                  const SizedBox(height: 10),
                  Text(
                    '临时巩固模式：默认仅做自测与回忆练习，不改动正式到期时间（due_utc）。',
                    key: const Key('weak-temp-mode-banner'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 1. Word Headword Card
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(
                      label:
                          '${BookStudyOrder.stageLabel(entry.fields['book_category'])} · ${entry.libraryClass}',
                      status: 'primary',
                      icon: Icons.bookmark_border,
                    ),
                    StatusBadge(
                      label: '优先级 ${entry.fields['learning_priority'] ?? '未定'}',
                      status: 'neutral',
                    ),
                    if (widget.pronunciation != null)
                      TextButton.icon(
                        key: const Key('open-word-pronunciation'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => context.push(
                          AppRouter.pronunciationWordPath(entry.id),
                        ),
                        icon: const Icon(Icons.volume_up_outlined, size: 16),
                        label: const Text('自主认读与听音'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  entry.word,
                  key: const Key('review-word'),
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontSize: entry.word.length > 16 ? 30 : 38,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(
                      label: '词义学习：${word.statusLabel}',
                      status: word.status,
                      textKey: const Key('meaning-status'),
                    ),
                    if (word.lastReviewedAt != null)
                      Text(
                        '上次复习：${formatLocalDateTime(word.lastReviewedAt!)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (word.dueAt != null)
                      Text(
                        '计划复习：${formatLocalDateTime(word.dueAt!)}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Phonics & Pronunciation Practice (Independent of Meaning Grade)
          if (widget.pronunciation != null) ...[
            const SizedBox(height: 14),
            WordReadingPractice(
              key: ValueKey('session-reading-${entry.id}'),
              entry: entry,
              services: widget.pronunciation!,
              onSaved: widget.controller.refresh,
              onPlaybackBusyChanged: (busy) {
                if (mounted && _playbackBusy != busy) {
                  setState(() => _playbackBusy = busy);
                }
              },
            ),
          ],

          const SizedBox(height: 14),

          // 3. Meaning Recall & Rating Card
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 20,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '词义回忆与评级',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_revealed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
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
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Text(
                            '请先看着英文独立回忆主要中文词义，确认后再揭晓答案（按 Space 键可快速查看）。',
                            key: const Key('hidden-meaning-prompt'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          key: ReviewPage.revealKey,
                          onPressed: () => setState(() => _revealed = true),
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('查看答案'),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
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
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusBadge(
                              label:
                                  '词性：${entry.fields['part_of_speech'] ?? '未标'}',
                              status: 'primary',
                            ),
                            SelectableText(
                              entry.meaning,
                              key: const Key('meaning'),
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontSize: 22,
                                color: scheme.onSurface,
                              ),
                            ),
                            if ((entry.fields['meaning_note'] ?? '').isNotEmpty)
                              Text(
                                entry.fields['meaning_note']!,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                        if ((entry.fields['example_en'] ?? '').isNotEmpty ||
                            (entry.fields['example_zh'] ?? '').isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(),
                          ),
                          if ((entry.fields['example_en'] ?? '').isNotEmpty)
                            SelectableText(
                              entry.fields['example_en']!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          if ((entry.fields['example_zh'] ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              entry.fields['example_zh']!,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (isDueMode)
                    _buildFormalGradeSection(context, entry, brightness)
                  else
                    _buildWeakModeActions(context, entry, brightness),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormalGradeSection(
    BuildContext context,
    VocabularyEntry entry,
    Brightness brightness,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '评级提示：若只是看着拼写熟悉、无法独立想起准确词义，请选择「眼熟」或「遗忘」，不要默认选「掌握」。',
          key: const Key('rating-guidance'),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '1 遗忘（无法独立想起正确词义 · 10 分钟后重现） · 2 眼熟（有印象但不够确定 · 1 天后复习） · 3 掌握（无需提示准确回忆 · 7 天后复习）',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _GradeActionButton(
              buttonKey: ReviewPage.gradeKey(ReviewGrade.forgotten),
              label: '1 · 遗忘 · 10 分钟',
              palette: AppTheme.forgottenColors(brightness),
              onPressed: _canGradeFormal
                  ? () => _submitFormalGrade(entry, ReviewGrade.forgotten)
                  : null,
            ),
            _GradeActionButton(
              buttonKey: ReviewPage.gradeKey(ReviewGrade.familiar),
              label: '2 · 眼熟 · 1 天',
              palette: AppTheme.familiarColors(brightness),
              onPressed: _canGradeFormal
                  ? () => _submitFormalGrade(entry, ReviewGrade.familiar)
                  : null,
            ),
            _GradeActionButton(
              buttonKey: ReviewPage.gradeKey(ReviewGrade.mastered),
              label: '3 · 掌握 · 7 天',
              palette: AppTheme.masteredColors(brightness),
              onPressed: _canGradeFormal
                  ? () => _submitFormalGrade(entry, ReviewGrade.mastered)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeakModeActions(
    BuildContext context,
    VocabularyEntry entry,
    Brightness brightness,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('临时巩固自检（不改变正式复习计划与到期时间）', style: theme.textTheme.labelLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              key: const Key('weak-practice-again'),
              onPressed: !_saving && !_playbackBusy
                  ? () => _submitTemporaryPractice(entry, remembered: false)
                  : null,
              icon: const Icon(Icons.replay_outlined, size: 18),
              label: const Text('仍需再记 · 下一词'),
            ),
            FilledButton.icon(
              key: const Key('weak-practice-remembered'),
              onPressed: !_saving && !_playbackBusy
                  ? () => _submitTemporaryPractice(entry, remembered: true)
                  : null,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('这次记住了 · 下一词'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('toggle-formal-grade'),
            onPressed: () => setState(
              () => _allowFormalGradeInWeakMode = !_allowFormalGradeInWeakMode,
            ),
            icon: Icon(
              _allowFormalGradeInWeakMode
                  ? Icons.expand_less
                  : Icons.edit_calendar_outlined,
              size: 18,
            ),
            label: Text(
              _allowFormalGradeInWeakMode ? '收起正式评级更新' : '需要同步更新正式学习评级？',
            ),
          ),
        ),
        if (_allowFormalGradeInWeakMode) ...[
          const SizedBox(height: 8),
          _buildFormalGradeSection(context, entry, brightness),
        ],
      ],
    );
  }
}

class _GradeActionButton extends StatelessWidget {
  const _GradeActionButton({
    required this.buttonKey,
    required this.label,
    required this.palette,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final StatusColors palette;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: buttonKey,
    style: OutlinedButton.styleFrom(
      foregroundColor: palette.foreground,
      backgroundColor: onPressed != null
          ? palette.background.withValues(alpha: 0.75)
          : null,
      side: BorderSide(
        color: onPressed != null
            ? palette.border
            : Theme.of(context).colorScheme.outlineVariant,
        width: 1.3,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ),
    onPressed: onPressed,
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}
