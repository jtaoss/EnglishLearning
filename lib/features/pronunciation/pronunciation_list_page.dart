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
    appBar: AppBar(title: const Text('6 词发音练习')),
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
            final words = widget.vocabulary.words
                .where((w) => snapshot.data!.entries.containsKey(w.entry.id))
                .toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('先自主认读，再听音核对。发音自评与词义学习分开保存。'),
                if (words.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('本地还没有这些样本词。可返回词库手动导入现有 100 词样本；这里不会自动导入。'),
                  ),
                for (final word in words)
                  ListTile(
                    key: ValueKey('pronunciation-word-${word.entry.id}'),
                    title: Text(word.entry.word),
                    subtitle: const Text('美式真人录音 · 可离线播放'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(
                      AppRouter.pronunciationWordPath(word.entry.id),
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}
