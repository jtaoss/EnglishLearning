import 'package:flutter/material.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/ui/status_badge.dart';
import 'package:english_learning/features/japanese/domain/japanese_vocab_entry.dart';
import 'package:english_learning/features/japanese/domain/japanese_controller.dart';
import 'package:english_learning/features/japanese/domain/japanese_review_state.dart';
import 'package:go_router/go_router.dart';

final class JapaneseWordCardPage extends StatefulWidget {
  const JapaneseWordCardPage({
    required this.sampleId,
    required this.controller,
    super.key,
  });

  final String sampleId;
  final JapaneseController controller;

  @override
  State<JapaneseWordCardPage> createState() => _JapaneseWordCardPageState();
}

class _JapaneseWordCardPageState extends State<JapaneseWordCardPage> {
  bool _revealed = false;
  bool _showFurigana = true;
  bool _audioBusy = false;

  @override
  void didUpdateWidget(JapaneseWordCardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sampleId != widget.sampleId) {
      _revealed = false;
      _showFurigana = true;
    }
  }

  Future<void> _playAudio(JapaneseVocabEntry entry) async {
    if (_audioBusy) return;
    setState(() => _audioBusy = true);
    final result = await widget.controller.audio.playWord(entry);
    if (mounted) {
      setState(() => _audioBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.controller.find(widget.sampleId);

    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('日语试点词卡')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('未找到试点词条: ${widget.sampleId}'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRouter.japaneseVocabulary),
                child: const Text('返回试点词表'),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final record = widget.controller.reviewState.getRecord(entry.sampleId);

    final prev = widget.controller.prevEntry(entry.sampleId);
    final next = widget.controller.nextEntry(entry.sampleId);

    return Scaffold(
      appBar: AppBar(
        title: Text('试点词卡 · ${entry.sampleId}'),
        actions: [
          IconButton(
            tooltip: '上一词',
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
            onPressed: prev == null
                ? null
                : () => context.go(AppRouter.japaneseWordPath(prev.sampleId)),
          ),
          IconButton(
            tooltip: '下一词',
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            onPressed: next == null
                ? null
                : () => context.go(AppRouter.japaneseWordPath(next.sampleId)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Prominent Candidate Disclaimer Banner
                  StatusBanner(
                    message:
                        '中文释义待校对：本词条中文释义由大模型拟定候选（未经人工确认），仅供隔离演示。不可作为正式标准使用。',
                    tone: BannerTone.warning,
                    icon: Icons.warning_amber_rounded,
                  ),
                  const SizedBox(height: 16),

                  // 1. Japanese Headword Hero Card
                  SectionCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Metadata badges & audio button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  StatusBadge(
                                    label: entry.lessonLabel,
                                    colors: AppTheme.infoColors(brightness),
                                    icon: Icons.bookmark_border,
                                  ),
                                  StatusBadge(
                                    label: entry.posLabel,
                                    status: 'neutral',
                                  ),
                                  StatusBadge(
                                    label: entry.auditBadgeLabel,
                                    colors: AppTheme.familiarColors(brightness),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              key: const Key('play-japanese-word-audio'),
                              onPressed: _audioBusy
                                  ? null
                                  : () => _playAudio(entry),
                              icon: const Icon(
                                Icons.volume_up_outlined,
                                size: 20,
                              ),
                              label: const Text('听发音（日语 TTS）'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Large Japanese word
                        Text(
                          entry.japanese,
                          key: const Key('japanese-headword'),
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Furigana reading section with toggle
                        Row(
                          children: [
                            if (_showFurigana)
                              Expanded(
                                child: Text(
                                  '读音假名：${entry.kana}'
                                  '${entry.accentOriginal.isNotEmpty ? "  (声调: ${entry.accentOriginal})" : ""}',
                                  key: const Key('furigana-text'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              Expanded(
                                child: Text(
                                  '【假名读音已隐藏，请尝试独立回忆汉字读音】',
                                  key: const Key('furigana-hidden-placeholder'),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            TextButton.icon(
                              key: const Key('toggle-furigana-btn'),
                              onPressed: () {
                                setState(() => _showFurigana = !_showFurigana);
                              },
                              icon: Icon(
                                _showFurigana
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 16,
                              ),
                              label: Text(_showFurigana ? '隐藏假名' : '显示假名'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. Meaning Recall & Reveal Section
                  SectionCard(
                    padding: const EdgeInsets.all(24),
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
                            Text(
                              '词义回忆与中文释义',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        if (!_revealed) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '中文释义默认隐藏',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '请先根据日语原文与语境独立回忆中文词义。回忆完成后点击下方按钮揭晓答案。',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  key: const Key('reveal-meaning-btn'),
                                  onPressed: () {
                                    setState(() => _revealed = true);
                                  },
                                  icon: const Icon(
                                    Icons.remove_red_eye_outlined,
                                  ),
                                  label: const Text('查看中文释义'),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Revealed content
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: scheme.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '核心中文候选释义：',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: scheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  entry.coreMeaning,
                                  key: const Key('revealed-core-meaning'),
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                if (entry.extendedMeaning != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '扩展释义与语境：${entry.extendedMeaning}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                const Divider(height: 20),
                                Text(
                                  '教材原始英释：${entry.englishOriginal}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '注：此中文释义由模型根据原日语/英释/香港繁体语境拟定，未完成人工审核。',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. Two-Dimension Review Rating Hooks (Demonstration Only)
                  SectionCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.rate_review_outlined,
                                  size: 20,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '双维度独立回忆自评',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            StatusBadge(label: '仅演示，不入库', status: 'neutral'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          JapaneseReviewSessionState.demoDisclaimer,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Dimension A: Meaning Recall
                        Text(
                          '维度一 · 词义回忆（看到日语能否想起中文意思）：',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          children: [
                            _buildRatingButton(
                              label: '掌握 · 词义',
                              grade: JapaneseRecallGrade.mastered,
                              selected:
                                  record.meaningGrade ==
                                  JapaneseRecallGrade.mastered,
                              brightness: brightness,
                              onTap: () {
                                widget.controller.reviewState.setMeaningGrade(
                                  entry.sampleId,
                                  JapaneseRecallGrade.mastered,
                                );
                                setState(() {});
                              },
                            ),
                            _buildRatingButton(
                              label: '眼熟 · 词义',
                              grade: JapaneseRecallGrade.familiar,
                              selected:
                                  record.meaningGrade ==
                                  JapaneseRecallGrade.familiar,
                              brightness: brightness,
                              onTap: () {
                                widget.controller.reviewState.setMeaningGrade(
                                  entry.sampleId,
                                  JapaneseRecallGrade.familiar,
                                );
                                setState(() {});
                              },
                            ),
                            _buildRatingButton(
                              label: '遗忘 · 词义',
                              grade: JapaneseRecallGrade.forgotten,
                              selected:
                                  record.meaningGrade ==
                                  JapaneseRecallGrade.forgotten,
                              brightness: brightness,
                              onTap: () {
                                widget.controller.reviewState.setMeaningGrade(
                                  entry.sampleId,
                                  JapaneseRecallGrade.forgotten,
                                );
                                setState(() {});
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Dimension B: Reading Recall
                        Text(
                          '维度二 · 读音回忆（看到日语能否正确读出假名）：',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          children: [
                            _buildRatingButton(
                              label: '掌握 · 读音',
                              grade: JapaneseRecallGrade.mastered,
                              selected:
                                  record.readingGrade ==
                                  JapaneseRecallGrade.mastered,
                              brightness: brightness,
                              onTap: () {
                                widget.controller.reviewState.setReadingGrade(
                                  entry.sampleId,
                                  JapaneseRecallGrade.mastered,
                                );
                                setState(() {});
                              },
                            ),
                            _buildRatingButton(
                              label: '眼熟 · 读音',
                              grade: JapaneseRecallGrade.familiar,
                              selected:
                                  record.readingGrade ==
                                  JapaneseRecallGrade.familiar,
                              brightness: brightness,
                              onTap: () {
                                widget.controller.reviewState.setReadingGrade(
                                  entry.sampleId,
                                  JapaneseRecallGrade.familiar,
                                );
                                setState(() {});
                              },
                            ),
                            _buildRatingButton(
                              label: '遗忘 · 读音',
                              grade: JapaneseRecallGrade.forgotten,
                              selected:
                                  record.readingGrade ==
                                  JapaneseRecallGrade.forgotten,
                              brightness: brightness,
                              onTap: () {
                                widget.controller.reviewState.setReadingGrade(
                                  entry.sampleId,
                                  JapaneseRecallGrade.forgotten,
                                );
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 4. Source & Audit Information (Expandable)
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: const Key('expand-source-info-tile'),
                      title: Text(
                        '查看数据来源与审校归属信息',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• 样本 ID: ${entry.sampleId} · 顺序: ${entry.sampleOrder}',
                              ),
                              Text(
                                '• 官方教材工作表: ${entry.sourceSheet} (第 ${entry.sourceExcelRow} 行)',
                              ),
                              if (entry.contextPdf.isNotEmpty)
                                Text(
                                  '• 香港繁体版教材语境: ${entry.contextPdf} (页码: ${entry.contextPdfPages})',
                                ),
                              if (entry.reviewFlags.isNotEmpty)
                                Text('• 审核标记: ${entry.reviewFlags}'),
                              if (entry.ambiguityNotes.isNotEmpty)
                                Text('• 歧义说明: ${entry.ambiguityNotes}'),
                              Text(
                                '• 审核状态: ${entry.validationStatus} · 人工复核: ${entry.humanConfirmation}',
                              ),
                              Text(
                                '• 正式入库许可: ${entry.importAllowed} (本轮隔离，禁止入库)',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Bottom Navigation Actions
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('prev-card-btn'),
                        onPressed: prev == null
                            ? null
                            : () => context.go(
                                AppRouter.japaneseWordPath(prev.sampleId),
                              ),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('上一个词'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            context.go(AppRouter.japaneseVocabulary),
                        child: const Text('返回试点词表'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('next-card-btn'),
                        onPressed: next == null
                            ? null
                            : () => context.go(
                                AppRouter.japaneseWordPath(next.sampleId),
                              ),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('下一个词'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRatingButton({
    required String label,
    required JapaneseRecallGrade grade,
    required bool selected,
    required Brightness brightness,
    required VoidCallback onTap,
  }) {
    final colors = switch (grade) {
      JapaneseRecallGrade.mastered => AppTheme.masteredColors(brightness),
      JapaneseRecallGrade.familiar => AppTheme.familiarColors(brightness),
      JapaneseRecallGrade.forgotten => AppTheme.forgottenColors(brightness),
    };

    return Material(
      color: selected ? colors.background : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected
              ? colors.border
              : colors.border.withValues(alpha: 0.5),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 16, color: colors.foreground),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: colors.foreground,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
