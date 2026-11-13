import 'package:flutter/material.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/ui/status_badge.dart';
import 'package:english_learning/ui/empty_state.dart';
import 'package:english_learning/features/japanese/domain/japanese_vocab_entry.dart';
import 'package:english_learning/features/japanese/domain/japanese_controller.dart';
import 'package:english_learning/features/japanese/domain/japanese_review_state.dart';
import 'package:go_router/go_router.dart';

final class JapaneseVocabularyPage extends StatefulWidget {
  const JapaneseVocabularyPage({required this.controller, super.key});

  final JapaneseController controller;

  @override
  State<JapaneseVocabularyPage> createState() => _JapaneseVocabularyPageState();
}

class _JapaneseVocabularyPageState extends State<JapaneseVocabularyPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedLesson = '全部';
  String _selectedPos = '全部';
  bool _showFurigana = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<JapaneseVocabEntry> _filteredEntries() {
    return widget.controller.entries.where((e) {
      if (_selectedLesson != '全部' && e.lessonOriginal != _selectedLesson) {
        return false;
      }
      if (_selectedPos != '全部' && e.posOriginal != _selectedPos) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final matchJp = e.japanese.toLowerCase().contains(_searchQuery);
        final matchKana = e.kana.toLowerCase().contains(_searchQuery);
        final matchZh = e.zhCnCandidate.toLowerCase().contains(_searchQuery);
        final matchEn = e.englishOriginal.toLowerCase().contains(_searchQuery);
        final matchId = e.sampleId.toLowerCase().contains(_searchQuery);
        if (!matchJp && !matchKana && !matchZh && !matchEn && !matchId) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final entries = _filteredEntries();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Irodori 试点词汇 (100 词)'),
        actions: [
          IconButton(
            tooltip: _showFurigana ? '隐藏假名注音' : '显示假名注音',
            icon: Icon(
              _showFurigana
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () {
              setState(() => _showFurigana = !_showFurigana);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Search and Filter Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Search TextField
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '搜索日语汉字、假名、中文候选释义或英文...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => _searchController.clear(),
                                )
                              : null,
                          filled: true,
                          fillColor: scheme.surfaceContainerLow,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Filter Row
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('课次：', style: theme.textTheme.bodySmall),
                          for (final l in ['全部', '1', '2', '3'])
                            ChoiceChip(
                              label: Text(l == '全部' ? '全部' : '第 $l 课'),
                              selected: _selectedLesson == l,
                              onSelected: (_) {
                                setState(() => _selectedLesson = l);
                              },
                            ),
                          const SizedBox(width: 8),
                          Text('词性：', style: theme.textTheme.bodySmall),
                          for (final p in ['全部', 'Exp', 'N', 'V', 'A', 'Adv'])
                            ChoiceChip(
                              label: Text(p),
                              selected: _selectedPos == p,
                              onSelected: (_) {
                                setState(() => _selectedPos = p);
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Notice Banner
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: StatusBanner(
                    message: '试点数据源共 100 词，中文释义均为模型拟定候选（0 个人工确认），已明确标记待校对。点击进入词卡可体验双维度回忆练习。',
                    tone: BannerTone.warning,
                  ),
                ),

                // Results list
                Expanded(
                  child: entries.isEmpty
                      ? const EmptyState(
                          title: '没有匹配的试点词条',
                          message: '请尝试更换搜索关键字或清除筛选条件。',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          itemCount: entries.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final record = widget.controller.reviewState
                                .getRecord(entry.sampleId);

                            return _buildVocabListItem(
                              entry: entry,
                              record: record,
                              theme: theme,
                              scheme: scheme,
                              brightness: brightness,
                              showFurigana: _showFurigana,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVocabListItem({
    required JapaneseVocabEntry entry,
    required JapaneseWordReviewRecord record,
    required ThemeData theme,
    required ColorScheme scheme,
    required Brightness brightness,
    required bool showFurigana,
  }) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        key: Key('vocab-item-${entry.sampleId}'),
        onTap: () => context.push(AppRouter.japaneseWordPath(entry.sampleId)),
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top badges
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    StatusBadge(label: entry.sampleId, status: 'neutral'),
                    StatusBadge(label: entry.lessonLabel, status: 'neutral'),
                    StatusBadge(label: entry.posLabel, status: 'neutral'),
                  ],
                ),
                StatusBadge(
                  label: entry.auditBadgeLabel,
                  colors: AppTheme.familiarColors(brightness),
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Japanese Headword & Kana
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  entry.japanese,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (showFurigana &&
                    entry.kana.isNotEmpty &&
                    entry.kana != entry.japanese) ...[
                  const SizedBox(width: 10),
                  Text(
                    '【${entry.kana}】',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),

            // Candidate Chinese meaning
            Text(
              '候选释义: ${entry.coreMeaning}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),

            // Review status indicators (if practiced)
            if (record.isGraded) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (record.meaningGrade != null)
                    _buildGradeBadge('词义', record.meaningGrade!, brightness),
                  if (record.readingGrade != null)
                    _buildGradeBadge('读音', record.readingGrade!, brightness),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGradeBadge(
    String dimension,
    JapaneseRecallGrade grade,
    Brightness brightness,
  ) {
    final colors = switch (grade) {
      JapaneseRecallGrade.mastered => AppTheme.masteredColors(brightness),
      JapaneseRecallGrade.familiar => AppTheme.familiarColors(brightness),
      JapaneseRecallGrade.forgotten => AppTheme.forgottenColors(brightness),
    };
    return StatusBadge(label: '$dimension: ${grade.label}', colors: colors);
  }
}
