import 'package:flutter/services.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';

abstract interface class NotionCredentials {
  Future<NotionAccount?> read();
  Future<void> save(NotionAccount account);
  Future<void> delete();
}

/// Uses WinCred in the existing Windows runner, with no plaintext file fallback.
final class WindowsNotionCredentials implements NotionCredentials {
  WindowsNotionCredentials({this.testNamespace, this.eventSandbox = false});
  final String? testNamespace;
  final bool eventSandbox;
  static const channel = MethodChannel('english_learning/notion_credentials');
  Map<String, Object?> get _args => {
    if (testNamespace != null) 'test_namespace': testNamespace,
    if (eventSandbox) 'purpose': 'event_sandbox',
  };
  Future<T?> _invoke<T>(String method, [String? value]) async {
    try {
      return await channel.invokeMethod<T>(method, {..._args, 'value': ?value});
    } catch (_) {
      throw const NotionFailure('Windows 安全存储暂时不可用，请重试；没有写入普通文件。');
    }
  }

  @override
  Future<NotionAccount?> read() async {
    final value = await _invoke<String>('read');
    return value == null ? null : NotionAccount.decode(value);
  }

  @override
  Future<void> save(NotionAccount account) async {
    await _invoke<void>('write', account.encode());
  }

  @override
  Future<void> delete() async {
    await _invoke<void>('delete');
  }
}
