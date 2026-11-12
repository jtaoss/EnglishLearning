import 'package:flutter/material.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/integrations/notion/notion_sync_controller.dart';
import 'package:english_learning/ui/status_badge.dart';

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
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final brightness = theme.brightness;

      return Scaffold(
        appBar: AppBar(title: const Text('Notion 只读同步')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // 1. Sync Scope & Status Overview Card
                  SectionCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cloud_download_outlined,
                                  size: 20,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '云端词库只读同步',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                            StatusBadge(
                              label: c.configured ? '连接凭据：已安全保存' : '连接凭据：尚未配置',
                              colors: c.configured
                                  ? AppTheme.masteredColors(brightness)
                                  : AppTheme.neutralColors(brightness),
                              icon: c.configured
                                  ? Icons.verified_user_outlined
                                  : Icons.lock_outline,
                              textKey: const Key('notion-config-status'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          c.isMobile
                              ? '将云端 100 词样本缓存到这台手机，断网后继续学习。'
                              : '将已验收的云端词库缓存到这台电脑，断网后继续学习。',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '只更新词条内容；词义学习记录和发音自评独立保存在本机。',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (!c.isMobile) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 460,
                                  ),
                                  child: Text(
                                    '正式范围是 5,332 词。100、200、500 仍保留给旧版已验收样本。此操作只读取词库，不会向 Notion 写入。',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      key: const Key('notion-target-size'),
                                      isDense: true,
                                      value: c.targetSize,
                                      items: [
                                        for (final size in c.selectableSizes)
                                          DropdownMenuItem(
                                            value: size,
                                            child: Text('$size 词'),
                                          ),
                                      ],
                                      onChanged: c.busy
                                          ? null
                                          : (size) {
                                              if (size != null) {
                                                c.selectSize(size);
                                              }
                                            },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 16,
                          runSpacing: 6,
                          children: [
                            StatusBadge(
                              label: '已关联缓存：${c.state.linkedWords} 词',
                              status: 'neutral',
                              textKey: const Key('notion-cache-count'),
                            ),
                            StatusBadge(
                              label:
                                  '上次成功同步：${c.state.syncedAt == null ? '尚未同步' : formatLocalDateTime(c.state.syncedAt!)}',
                              status: 'neutral',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Credentials & Sync Actions Card
                  SectionCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.key_outlined,
                              size: 18,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '凭据配置与同步操作',
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
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
                        const SizedBox(height: 14),
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
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              key: const Key('notion-save'),
                              onPressed: c.busy
                                  ? null
                                  : () async {
                                      final token = _token.text;
                                      _token.clear();
                                      await c.save(_source.text, token);
                                    },
                              icon: const Icon(Icons.shield_outlined, size: 18),
                              label: const Text('安全保存配置'),
                            ),
                            FilledButton.icon(
                              key: const Key('notion-sync'),
                              onPressed: c.busy || !c.configured
                                  ? null
                                  : () => c.sync(),
                              icon: const Icon(Icons.sync, size: 18),
                              label: Text(
                                '同步 ${c.isMobile ? 100 : c.targetSize} 词',
                              ),
                            ),
                            OutlinedButton.icon(
                              key: const Key('notion-full-sync'),
                              onPressed: c.busy || !c.configured
                                  ? null
                                  : () => c.sync(full: true),
                              icon: const Icon(
                                Icons.fact_check_outlined,
                                size: 18,
                              ),
                              label: Text(
                                '重新核对 ${c.isMobile ? 100 : c.targetSize} 词',
                              ),
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
                            padding: EdgeInsets.only(top: 16),
                            child: LinearProgressIndicator(),
                          ),
                        if (c.message != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: StatusBanner(
                              message: c.message!,
                              tone: BannerTone.success,
                              textKey: const Key('notion-result'),
                            ),
                          ),
                        if (c.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: StatusBanner(
                              message: c.error!,
                              tone: BannerTone.danger,
                              textKey: const Key('notion-error'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. Instructions Card
                  SectionCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        '创建只读集成与授权',
                        style: theme.textTheme.titleSmall,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SelectableText(
                            '1. 在 notion.so/profile/integrations 创建个人内部集成，仅启用 Read content。\n'
                            '2. 在目标数据库右上角菜单中连接该集成。\n'
                            '3. 将密钥粘贴到上方输入框，点击安全保存配置。\n'
                            '4. 点击同步；首次及扩容后需要完整返回所选规模的已核验稳定 ID。\n\n'
                            '密钥不要发送到聊天或保存到普通文件。删除凭据不会删除本地词库。\n'
                            '云端归档或删除的词不会自动删除本地学习历史；请人工核对。',
                            style: theme.textTheme.bodySmall,
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
      );
    },
  );
}
