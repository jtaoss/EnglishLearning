import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/word_reading_practice.dart';
import 'package:english_learning/ui/status_badge.dart';

final class ReviewPage extends StatefulWidget {
  const ReviewPage({
    required this.controller,
    required this.entryId,
    this.hasPronunciation = false,
    this.pronunciationServices,
    super.key,
  });
  final VocabularyController controller;
  final String entryId;
  final bool hasPronunciation;
  final PronunciationServices? pronunciationServices;
  static const revealKey = Key('reveal-answer');
  static Key gradeKey(ReviewGrade grade) => ValueKey('grade-${grade.name}');
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  bool _revealed = false;
  bool _saved = false;
  bool _saving = false;
  int _readingGeneration = 0;
  bool _readingBusy = false;

  Future<void> _grade(ReviewGrade grade) async {
    if (!_revealed || _saved || _saving) return;
    setState(() => _saving = true);
    final saved = await widget.controller.review(
      widget.entryId,
      grade,
      widget.controller.nowUtc,
    );
    if (mounted) {
      setState(() {
        _saving = false;
        _saved = saved;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final word = c.find(widget.entryId);
      if (word == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('词卡')),
          body: const Center(child: Text('未找到该词条，请返回词库。')),
        );
      }
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final brightness = theme.brightness;
      final entry = word.entry;
      final paused = entry.libraryClass == '暂缓';
      final overdue = c
          .dueWords(c.nowUtc, libraryClass: null)
          .where(
            (w) =>
                w.entry.id != entry.id &&
                ((w.dueAt != null && !w.dueAt!.isAfter(c.nowUtc)) ||
                    w.isPronunciationDue(c.nowUtc)),
          )
          .firstOrNull;
      final next =
          overdue ??
          c
              .dueWords(c.nowUtc, libraryClass: entry.libraryClass)
              .where((w) => w.entry.id != entry.id)
              .firstOrNull;
      final canGradeMeaning = !_saved && !_saving && !c.busy && _revealed;

      return Scaffold(
        appBar: AppBar(title: const Text('词卡')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Word Hero Card
                    SectionCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  StatusBadge(
                                    label:
                                        '${entry.fields['book_category']} · ${entry.libraryClass}',
                                    colors: AppTheme.infoColors(brightness),
                                    icon: Icons.bookmark_border,
                                  ),
                                  if (entry
                                          .fields['learning_priority']
                                          ?.isNotEmpty ==
                                      true)
                                    StatusBadge(
                                      label:
                                          '优先级 ${entry.fields['learning_priority']}',
                                      status: 'neutral',
                                    ),
                                ],
                              ),
                              if (widget.hasPronunciation)
                                TextButton.icon(
                                  key: const Key('word-pronunciation'),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: _readingBusy
                                      ? null
                                      : () async {
                                          if (_readingBusy) {
                                            return;
                                          }
                                          await context.push(
                                            AppRouter.pronunciationWordPath(
                                              entry.id,
                                            ),
                                          );
                                          if (!mounted) return;
                                          await c.refresh();
                                          if (mounted) {
                                            setState(
                                              () => _readingGeneration++,
                                            );
                                          }
                                        },
                                  icon: const Icon(
                                    Icons.volume_up_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('自主认读与听音'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            entry.word,
                            key: const Key('review-word'),
                            style: theme.textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusBadge(
                                label: '词义学习：${word.statusLabel}',
                                status: word.status,
                              ),
                              if (word.reviewCount > 0)
                                StatusBadge(
                                  label: '已复习 ${word.reviewCount} 次',
                                  status: 'neutral',
                                ),
                              if (word.dueAt != null && !_saved)
                                StatusBadge(
                                  label: '下次复习 ${_localDate(word.dueAt!)}',
                                  status: 'neutral',
                                  icon: Icons.schedule_outlined,
                                  textKey: const Key('persisted-due'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. Pronunciation & Phonics Practice Card
                    if (widget.pronunciationServices != null) ...[
                      WordReadingPractice(
                        key: ValueKey(
                          'reading-${entry.id}-$_readingGeneration',
                        ),
                        entry: entry,
                        services: widget.pronunciationServices!,
                        clock: () => c.nowUtc,
                        onPlaybackBusyChanged: (busy) {
                          if (mounted) setState(() => _readingBusy = busy);
                        },
                        onSaved: () async {
                          await c.refresh();
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 3. Meaning Recall & Grading Card
                    SectionCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.psychology_alt_outlined,
                                size: 18,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '词义回忆与掌握评级',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (!_revealed)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              child: Wrap(
                                spacing: 16,
                                runSpacing: 10,
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 460,
                                    ),
                                    child: Text(
                                      '请先看着英文单词独立回忆中文词义，再点击右侧按钮核对答案。',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  FilledButton.icon(
                                    key: ReviewPage.revealKey,
                                    onPressed: () =>
                                        setState(() => _revealed = true),
                                    icon: const Icon(
                                      Icons.lightbulb_outline,
                                      size: 18,
                                    ),
                                    label: const Text('查看答案'),
                                  ),
                                ],
                              ),
                            ),
                          if (_revealed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (entry
                                              .fields['part_of_speech']
                                              ?.isNotEmpty ??
                                          false)
                                        StatusBadge(
                                          label:
                                              '词性：${entry.fields['part_of_speech']}',
                                          colors: AppTheme.infoColors(
                                            brightness,
                                          ),
                                          textKey: const Key('part-of-speech'),
                                        ),
                                      Text(
                                        entry.meaning,
                                        key: const Key('meaning'),
                                        style: theme.textTheme.titleLarge,
                                      ),
                                      Text(
                                        entry.fields['meaning_review_status']!,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                  if ((entry.fields['example_en']?.isNotEmpty ==
                                          true) ||
                                      (entry.fields['usage_note']?.isNotEmpty ??
                                          false)) ...[
                                    const Divider(height: 16),
                                    if (entry
                                            .fields['example_en']
                                            ?.isNotEmpty ==
                                        true) ...[
                                      Text(
                                        entry.fields['example_en']!,
                                        key: const Key('example-en'),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        entry.fields['example_zh'] ?? '',
                                        key: const Key('example-zh'),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                    if (entry
                                            .fields['usage_note']
                                            ?.isNotEmpty ??
                                        false)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          entry.fields['usage_note']!,
                                          key: const Key('usage-note'),
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (paused)
                            const StatusBanner(
                              message: '暂缓词仅供查看，不安排复习。',
                              tone: BannerTone.warning,
                            ),
                          if (!paused) ...[
                            Text(
                              '词义评级（查看答案后选择，与发音自评相互独立）',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                for (final grade in ReviewGrade.values)
                                  _buildMeaningGradeButton(
                                    context: context,
                                    grade: grade,
                                    enabled: canGradeMeaning,
                                  ),
                              ],
                            ),
                          ],
                          if (_saving) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(),
                          ],
                          if (c.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              c.error!,
                              style: TextStyle(color: scheme.error),
                            ),
                          ],
                          if (_saved) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.masteredColors(brightness)
                                    .background,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppTheme.masteredColors(brightness)
                                      .border,
                                ),
                              ),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 18,
                                        color: AppTheme.masteredColors(
                                          brightness,
                                        ).foreground,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          '已保存 · 下次复习 ${_localDate(word.dueAt!)}',
                                          key: const Key('review-saved'),
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: AppTheme.masteredColors(
                                                  brightness,
                                                ).foreground,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (next != null)
                                        FilledButton.icon(
                                          key: const Key('next-word'),
                                          onPressed: () => context.replace(
                                            AppRouter.wordPath(next.entry.id),
                                          ),
                                          icon: const Icon(
                                            Icons.arrow_forward,
                                            size: 18,
                                          ),
                                          label: const Text('下一词'),
                                        ),
                                      TextButton(
                                        onPressed: () {
                                          if (context.canPop()) {
                                            context.pop();
                                          } else {
                                            context.go(AppRouter.vocabulary);
                                          }
                                        },
                                        child: const Text('返回词库'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 4. Source & Exam Attribution Card
                    SectionCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          '查看来源与考试归属',
                          style: theme.textTheme.titleSmall,
                        ),
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.only(bottom: 8),
                            title: Text(entry.fields['source_file']!),
                            subtitle: Text(
                              'PDF 页 ${entry.fields['source_pdf_pages']} · 索引页 ${entry.fields['source_index_pages']}\n'
                              '${entry.fields['book_verification']}\n'
                              'PETS-3 2015：${entry.fields['pets2015_status']}\n'
                              'PETS-3 2025：${entry.fields['pets2025_status']}\n'
                              '稳定 ID：${entry.id}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _buildMeaningGradeButton({
    required BuildContext context,
    required ReviewGrade grade,
    required bool enabled,
  }) {
    final brightness = Theme.of(context).brightness;
    final palette = AppTheme.statusColorsFor(grade.name, brightness);
    final intervalHint = switch (grade) {
      ReviewGrade.mastered => '7 天',
      ReviewGrade.familiar => '1 天',
      ReviewGrade.forgotten => '10 分钟',
    };
    return OutlinedButton(
      key: ReviewPage.gradeKey(grade),
      style: enabled
          ? OutlinedButton.styleFrom(
              foregroundColor: palette.foreground,
              backgroundColor: palette.background.withValues(alpha: 0.65),
              side: BorderSide(color: palette.border, width: 1.3),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            )
          : OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
      onPressed: enabled ? () => _grade(grade) : null,
      child: Text('${grade.label} · $intervalHint'),
    );
  }
}

String _localDate(DateTime value) => formatLocalDateTime(value);
