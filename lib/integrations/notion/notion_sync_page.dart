import 'package:flutter/material.dart';
import 'package:english_learning/integrations/notion/notion_sync_controller.dart';

final class NotionSyncPage extends StatefulWidget {
  const NotionSyncPage({super.key, required this.controller});
  final NotionSyncController controller;
  @override
  State<NotionSyncPage> createState() => _NotionSyncPageState();
}

class _NotionSyncPageState extends State<NotionSyncPage> {
  late final _source = TextEditingController(text: widget.controller.sourceId);
  final _token = TextEditingController();
  @override
  void dispose() {
    _source.dispose();
    _token.clear();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return Scaffold(
        appBar: AppBar(title: const Text('Notion 只读同步')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    c.isMobile
                        ? '将云端 100 词样本缓存到这台手机，断网后继续学习。'
                        : '将云端 100 词样本缓存到这台电脑，断网后继续学习。',
                  ),
                  const SizedBox(height: 12),
                  const Text('只更新词条内容；词义学习记录和发音自评独立保存在本机。'),
                  const SizedBox(height: 20),
                  Text(
                    c.configured ? '连接凭据：已安全保存' : '连接凭据：尚未配置',
                    key: const Key('notion-config-status'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('notion-source'),
                    controller: _source,
                    enabled: !c.busy && !c.isMobile,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '数据源 ID',
                      helperText: '使用已授权数据源的 ID，区别于数据库页面 ID。',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('notion-token'),
                    controller: _token,
                    enabled: !c.busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: InputDecoration(
                      labelText: 'Notion 只读集成密钥',
                      helperText: '存入${c.storageLabel}；不显示已保存密钥。',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton(
                        key: const Key('notion-save'),
                        onPressed: c.busy
                            ? null
                            : () async {
                                final token = _token.text;
                                _token.clear();
                                await c.save(_source.text, token);
                              },
                        child: const Text('安全保存配置'),
                      ),
                      FilledButton.icon(
                        key: const Key('notion-sync'),
                        onPressed: c.busy || !c.configured
                            ? null
                            : () => c.sync(),
                        icon: const Icon(Icons.sync),
                        label: const Text('同步 100 词'),
                      ),
                      OutlinedButton(
                        key: const Key('notion-full-sync'),
                        onPressed: c.busy || !c.configured
                            ? null
                            : () => c.sync(full: true),
                        child: const Text('重新核对 100 词'),
                      ),
                      TextButton(
                        key: const Key('notion-forget'),
                        onPressed: c.busy || !c.configured
                            ? null
                            : () => c.forget(),
                        child: const Text('删除连接凭据'),
                      ),
                    ],
                  ),
                  if (c.busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    '已关联缓存：${c.state.linkedWords} / 100 词',
                    key: const Key('notion-cache-count'),
                  ),
                  Text(
                    '上次成功同步：${c.state.syncedAt?.toLocal().toString() ?? '尚未同步'}',
                  ),
                  if (c.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(c.message!, key: const Key('notion-result')),
                    ),
                  if (c.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        c.error!,
                        key: const Key('notion-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const ExpansionTile(
                    title: Text('创建只读集成与授权'),
                    children: [
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: SelectableText(
                          '1. 在 notion.so/profile/integrations 创建个人内部集成，仅启用 Read content。\n'
                          '2. 在目标数据库右上角菜单中连接该集成。\n'
                          '3. 将密钥粘贴到上方输入框，点击安全保存配置。\n'
                          '4. 点击同步；首次需要返回全部 100 个已核验稳定 ID。\n\n'
                          '密钥不要发送到聊天或保存到普通文件。删除凭据不会删除本地词库。\n'
                          '云端归档或删除的词不会自动删除本地学习历史；请人工核对。',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
