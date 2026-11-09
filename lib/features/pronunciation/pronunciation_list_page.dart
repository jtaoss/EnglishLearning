import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/features/pronunciation/pronunciation_content.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';

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
    body: FutureBuilder(
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
        return ListenableBuilder(
          listenable: widget.vocabulary,
          builder: (context, _) {
            final words = widget.vocabulary.words;
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: words.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Text(
                    words.isEmpty
                        ? '本地词库为空，请先返回词库同步。'
                        : '先自主认读，再听音核对。缺少音频也可保存自主认读自评。',
                  );
                }
                final word = words[index - 1];
                return ListTile(
                  key: ValueKey('pronunciation-word-${word.entry.id}'),
                  title: Text(word.entry.word),
                  subtitle: Text(
                    snapshot.data!.entries.containsKey(word.entry.id)
                        ? '美式真人录音 · 可离线播放'
                        : '自主认读 · 标准音频待补充',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    AppRouter.pronunciationWordPath(word.entry.id),
                  ),
                );
              },
            );
          },
        );
      },
    ),
  );
}
