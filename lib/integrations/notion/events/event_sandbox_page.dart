import 'package:flutter/material.dart';

import 'event_model.dart';
import 'event_sandbox_controller.dart';

final class EventSandboxPage extends StatefulWidget {
  const EventSandboxPage({super.key, required this.controller});
  final EventSandboxController controller;
  @override
  State<EventSandboxPage> createState() => _EventSandboxPageState();
}

class _EventSandboxPageState extends State<EventSandboxPage> {
  final _token = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.controller.restore();
  }

  @override
  void dispose() {
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
        appBar: AppBar(title: const Text('同步实验 · 模拟学习事件')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text('本页只生成并上传 24 条模拟事件，不上传你的真实学习历史。'),
                  const SizedBox(height: 12),
                  const SelectableText('独立测试库：$eventSandboxSource'),
                  const Text('正式词库继续只读同步；词义和发音自评不受本实验影响。'),
                  const SizedBox(height: 20),
                  Text(
                    c.configured ? '测试凭据：已安全保存' : '测试凭据：尚未配置',
                    key: const Key('event-config'),
                  ),
                  TextField(
                    key: const Key('event-token'),
                    controller: _token,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    enabled: !c.busy,
                    decoration: const InputDecoration(
                      labelText: '独立测试集成密钥',
                      helperText: '只存入 Windows 凭据管理器，不显示已存密钥。',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton(
                        key: const Key('event-save'),
                        onPressed: c.busy
                            ? null
                            : () {
                                final v = _token.text;
                                _token.clear();
                                c.save(v);
                              },
                        child: const Text('安全保存测试凭据'),
                      ),
                      OutlinedButton(
                        key: const Key('event-seed'),
                        onPressed: c.busy ? null : c.seed,
                        child: const Text('本地生成 24 条模拟事件'),
                      ),
                      FilledButton(
                        key: const Key('event-sync'),
                        onPressed: c.busy || !c.configured || c.rows.isEmpty
                            ? null
                            : c.sync,
                        child: const Text('上传 / 对账 / 恢复'),
                      ),
                    ],
                  ),
                  if (c.busy) const LinearProgressIndicator(),
                  if (c.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(c.message!, key: const Key('event-result')),
                    ),
                  if (c.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(c.error!, key: const Key('event-error')),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    '本地模拟事件 ${c.rows.length} 条 · 已同步 ${c.rows.where((r) => r.state == 'synced').length} 条',
                    key: const Key('event-count'),
                  ),
                  const Text(
                    '结果不明的创建只查询对账。暂时查不到不会自动重建；冲突保留原始事件，等待复核。重试会遵守已保存的等待时间。',
                  ),
                  for (final r in c.rows)
                    ListTile(
                      dense: true,
                      title: Text(
                        '${r.event.sequence}. ${r.event.type} · ${r.event.grade}',
                      ),
                      subtitle: Text(
                        '${r.event.id}\n${_label(r.state)}${r.nextAttempt == null ? '' : ' · 下次检查 ${r.nextAttempt!.toLocal()}'}',
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

String _label(String state) => switch (state) {
  'pending' => '待上传 / 重试',
  'sending' => '发送中，重启后需对账',
  'uncertain' => '结果不明，待对账',
  'synced' => '已同步',
  'conflict' => '冲突，待复核',
  _ => '受阻，待复核',
};
