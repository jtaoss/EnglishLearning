import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/features/pronunciation/pronunciation_content.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/ui/status_badge.dart';

final class PronunciationListPage extends StatefulWidget {
  const PronunciationListPage({
    required this.services,
    required this.vocabulary,
    super.key,
  });
  final PronunciationServices services;
  final VocabularyController vocabulary;
  @override
  State<PronunciationListPage> createState() => _PronunciationListPageState();
}

class _PronunciationListPageState extends State<PronunciationListPage> {
  late Future<PronunciationCatalog> _catalog = widget.services.catalog();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('自主认读与听音')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: FutureBuilder(
            future: _catalog,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _catalog = widget.services.catalog()),
                    child: const Text('资源读取失败，重试'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final brightness = Theme.of(context).brightness;
              final scheme = Theme.of(context).colorScheme;
              return ListenableBuilder(
                listenable: widget.vocabulary,
                builder: (context, _) {
                  final words = widget.vocabulary.words;
                  return ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: words.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SectionCard(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.hearing_outlined,
                                  color: scheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    words.isEmpty
                                        ? '本地词库为空，请先返回词库同步。'
                                        : '先自主认读，再听音核对。缺少音频也可保存自主认读自评。',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      final word = words[index - 1];
                      final hasAudio = snapshot.data!.entries.containsKey(
                        word.entry.id,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: scheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: scheme.outlineVariant),
                          ),
                          child: ListTile(
                            key: ValueKey(
                              'pronunciation-word-${word.entry.id}',
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    word.entry.word,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                StatusBadge(
                                  label: hasAudio ? '真人录音' : 'TTS / 认读',
                                  colors: hasAudio
                                      ? AppTheme.masteredColors(brightness)
                                      : AppTheme.neutralColors(brightness),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              hasAudio ? '美式真人录音 · 可离线播放' : '自主认读 · 标准音频待补充',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push(
                              AppRouter.pronunciationWordPath(word.entry.id),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    ),
  );
}
