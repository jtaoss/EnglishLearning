import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';

final class ReviewPage extends StatefulWidget {
  const ReviewPage({
    required this.controller,
    required this.entryId,
    this.hasPronunciation = false,
    super.key,
  });
  final VocabularyController controller;
  final String entryId;
  final bool hasPronunciation;
  static const revealKey = Key('reveal-answer');
  static Key gradeKey(ReviewGrade grade) => ValueKey('grade-${grade.name}');
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  bool _revealed = false;
  bool _saved = false;
  bool _saving = false;

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
      final entry = word.entry;
      final paused = entry.libraryClass == '暂缓';
      final next = c
          .dueWords(c.nowUtc, libraryClass: entry.libraryClass)
          .where((w) => w.entry.id != entry.id)
          .firstOrNull;
      return Scaffold(
        appBar: AppBar(title: const Text('词卡')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${entry.fields['book_category']} · ${entry.libraryClass}',
                    ),
                    const SizedBox(height: 24),
                    Text(
                      entry.word,
                      key: const Key('review-word'),
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    Text('词义学习：${word.statusLabel}'),
                    if (widget.hasPronunciation)
                      TextButton.icon(
                        key: const Key('word-pronunciation'),
                        onPressed: () => context.push(
                          AppRouter.pronunciationWordPath(entry.id),
                        ),
                        icon: const Icon(Icons.volume_up_outlined),
                        label: const Text('自主认读与听音'),
                      ),
                    if (word.dueAt != null && !_saved)
                      Text(
                        '下次复习 ${_localDate(word.dueAt!)}',
                        key: const Key('persisted-due'),
                      ),
                    const SizedBox(height: 24),
                    if (!_revealed)
                      FilledButton(
                        key: ReviewPage.revealKey,
                        onPressed: () => setState(() => _revealed = true),
                        child: const Text('查看答案'),
                      ),
                    if (_revealed) ...[
                      if (entry.fields['part_of_speech']?.isNotEmpty ?? false)
                        Text(
                          '词性：${entry.fields['part_of_speech']}',
                          key: const Key('part-of-speech'),
                        ),
                      Text(
                        entry.meaning,
                        key: const Key('meaning'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(entry.fields['meaning_review_status']!),
                      if (entry.fields['usage_note']?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            entry.fields['usage_note']!,
                            key: const Key('usage-note'),
                          ),
                        ),
                    ],
                    const SizedBox(height: 24),
                    if (paused) const Text('暂缓词仅供查看，不安排复习。'),
                    if (!paused)
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final grade in ReviewGrade.values)
                            OutlinedButton(
                              key: ReviewPage.gradeKey(grade),
                              onPressed:
                                  !_revealed || _saved || _saving || c.busy
                                  ? null
                                  : () => _grade(grade),
                              child: Text(grade.label),
                            ),
                        ],
                      ),
                    if (_saving) const LinearProgressIndicator(),
                    if (c.error != null)
                      Text(
                        c.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_saved) ...[
                      const SizedBox(height: 16),
                      Text(
                        '已保存 · 下次复习 ${_localDate(word.dueAt!)}',
                        key: const Key('review-saved'),
                      ),
                      const SizedBox(height: 12),
                      if (next != null)
                        FilledButton(
                          key: const Key('next-word'),
                          onPressed: () => context.replace(
                            AppRouter.wordPath(next.entry.id),
                          ),
                          child: const Text('下一词'),
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
                    const SizedBox(height: 24),
                    ExpansionTile(
                      title: const Text('查看来源与考试归属'),
                      children: [
                        ListTile(
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
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

String _localDate(DateTime value) {
  final date = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}
