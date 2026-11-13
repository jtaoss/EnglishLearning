import 'package:flutter/material.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/ui/status_badge.dart';
import 'package:english_learning/features/japanese/domain/kana_quiz.dart';
import 'package:english_learning/features/japanese/domain/japanese_controller.dart';

final class KanaPracticePage extends StatefulWidget {
  const KanaPracticePage({required this.controller, super.key});

  final JapaneseController controller;

  @override
  State<KanaPracticePage> createState() => _KanaPracticePageState();
}

class _KanaPracticePageState extends State<KanaPracticePage> {
  KanaPracticeMode _selectedMode = KanaPracticeMode.kanaToRomaji;
  late KanaQuizSession _session;

  @override
  void initState() {
    super.initState();
    _startSession(_selectedMode);
  }

  void _startSession(KanaPracticeMode mode) {
    setState(() {
      _selectedMode = mode;
      _session = KanaQuizSession.create(mode: mode, count: 10);
    });
  }

  void _selectOption(String option) {
    if (_session.isCurrentAnswered) return;
    setState(() {
      _session.answerCurrent(option);
    });
  }

  void _next() {
    setState(() {
      _session.next();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    return Scaffold(
      appBar: AppBar(title: const Text('假名基础练习')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Mode Selector Tabs
                  SectionCard(
                    padding: const EdgeInsets.all(12),
                    child: SegmentedButton<KanaPracticeMode>(
                      key: const Key('practice-mode-segmented'),
                      segments: const [
                        ButtonSegment(
                          value: KanaPracticeMode.kanaToRomaji,
                          label: Text('看假名选读音'),
                        ),
                        ButtonSegment(
                          value: KanaPracticeMode.romajiToKana,
                          label: Text('看罗马字选假名'),
                        ),
                        ButtonSegment(
                          value: KanaPracticeMode.hiraganaKatakanaMatch,
                          label: Text('平片假名互选'),
                        ),
                      ],
                      selected: {_selectedMode},
                      onSelectionChanged: (set) => _startSession(set.first),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Session content
                  if (_session.isFinished)
                    _buildSummaryCard(theme, scheme, brightness)
                  else
                    _buildQuestionCard(theme, scheme, brightness),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme,
    ColorScheme scheme,
    Brightness brightness,
  ) {
    final correct = _session.correctCount;
    final total = _session.totalQuestions;
    final percent = (correct / total * 100).round();

    return SectionCard(
      padding: const EdgeInsets.all(28),
      borderColor: scheme.primary.withValues(alpha: 0.3),
      child: Column(
        children: [
          StatusBadge(
            label: '练习已完成',
            colors: AppTheme.masteredColors(brightness),
            icon: Icons.check_circle_outline,
          ),
          const SizedBox(height: 18),
          Text(
            '本次得分: $correct / $total',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '正确率：$percent% · 模式：${_selectedMode.label}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                key: const Key('restart-practice-btn'),
                onPressed: () => _startSession(_selectedMode),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('再练一组 (10 题)'),
              ),
              const SizedBox(width: 14),
              OutlinedButton(
                onPressed: () {
                  final nextMode = switch (_selectedMode) {
                    KanaPracticeMode.kanaToRomaji =>
                      KanaPracticeMode.romajiToKana,
                    KanaPracticeMode.romajiToKana =>
                      KanaPracticeMode.hiraganaKatakanaMatch,
                    KanaPracticeMode.hiraganaKatakanaMatch =>
                      KanaPracticeMode.kanaToRomaji,
                  };
                  _startSession(nextMode);
                },
                child: const Text('尝试其他模式'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(
    ThemeData theme,
    ColorScheme scheme,
    Brightness brightness,
  ) {
    final q = _session.currentQuestion;
    final answered = _session.isCurrentAnswered;
    final chosen = _session.currentAnswer;
    final isCorrect = _session.isCurrentCorrect;

    return SectionCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatusBadge(
                label:
                    '第 ${_session.currentIndex + 1} / ${_session.totalQuestions} 题',
                status: 'neutral',
              ),
              StatusBadge(
                label: q.promptNote,
                colors: AppTheme.infoColors(brightness),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Big prompt
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                q.prompt,
                key: const Key('practice-question-prompt'),
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Options (4 choices)
          for (final opt in q.options) ...[
            _buildOptionButton(
              opt: opt,
              q: q,
              answered: answered,
              chosen: chosen,
              theme: theme,
              scheme: scheme,
              brightness: brightness,
            ),
            const SizedBox(height: 10),
          ],

          // Feedback & Next Button
          if (answered) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCorrect
                    ? AppTheme.masteredColors(brightness).background
                    : AppTheme.forgottenColors(brightness).background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isCorrect
                      ? AppTheme.masteredColors(brightness).border
                      : AppTheme.forgottenColors(brightness).border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCorrect ? Icons.check_circle : Icons.cancel,
                    color: isCorrect
                        ? AppTheme.masteredColors(brightness).foreground
                        : AppTheme.forgottenColors(brightness).foreground,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isCorrect
                          ? '回答正确！${q.targetKana.hiragana} / ${q.targetKana.katakana} (${q.targetKana.romaji})'
                          : '回答错误。正确答案是: ${q.correctAnswer} (${q.targetKana.mnemonicHint})',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isCorrect
                            ? AppTheme.masteredColors(brightness).foreground
                            : AppTheme.forgottenColors(brightness).foreground,
                      ),
                    ),
                  ),
                  FilledButton(
                    key: const Key('practice-next-btn'),
                    onPressed: _next,
                    child: Text(
                      _session.currentIndex < _session.totalQuestions - 1
                          ? '下一题'
                          : '查看结果',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionButton({
    required String opt,
    required KanaQuizQuestion q,
    required bool answered,
    required String? chosen,
    required ThemeData theme,
    required ColorScheme scheme,
    required Brightness brightness,
  }) {
    Color? bgColor;
    Color? borderColor;
    Color? textColor;

    if (answered) {
      if (opt == q.correctAnswer) {
        final colors = AppTheme.masteredColors(brightness);
        bgColor = colors.background;
        borderColor = colors.border;
        textColor = colors.foreground;
      } else if (opt == chosen) {
        final colors = AppTheme.forgottenColors(brightness);
        bgColor = colors.background;
        borderColor = colors.border;
        textColor = colors.foreground;
      }
    }

    return Material(
      color: bgColor ?? scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor ?? scheme.outlineVariant),
      ),
      child: InkWell(
        key: Key('practice-option-$opt'),
        onTap: answered ? null : () => _selectOption(opt),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                opt,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: textColor ?? scheme.onSurface,
                ),
              ),
              if (answered && opt == q.correctAnswer)
                Icon(
                  Icons.check,
                  color: AppTheme.masteredColors(brightness).foreground,
                  size: 20,
                ),
              if (answered && opt == chosen && opt != q.correctAnswer)
                Icon(
                  Icons.close,
                  color: AppTheme.forgottenColors(brightness).foreground,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
