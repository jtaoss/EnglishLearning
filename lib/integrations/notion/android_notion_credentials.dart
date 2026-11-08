import 'package:flutter/services.dart';

import 'notion_credentials.dart';
import 'notion_models.dart';

/// AndroidKeyStore AES-GCM; ciphertext is private and excluded from backup.
final class AndroidNotionCredentials implements NotionCredentials {
  AndroidNotionCredentials({this.testNamespace});
  final String? testNamespace;
  static const channel = MethodChannel(
    'english_learning/android_notion_credentials',
  );
  Map<String, Object?> get args => {
    if (testNamespace != null) 'test_namespace': testNamespace,
  };
  Future<T?> _invoke<T>(String method, [String? value]) async {
    try {
      return await channel.invokeMethod<T>(method, {...args, 'value': ?value});
    } catch (_) {
      throw const NotionFailure('Android 安全存储不可用。凭据未写入普通文件，请重试或重新授权。');
    }
  }

  static void _scope(NotionAccount account) {
    if (account.dataSourceId != notionPilotSource) {
      throw const NotionFailure('Android 只允许访问已核定的 100 词数据源。');
    }
  }

  @override
  Future<NotionAccount?> read() async {
    final value = await _invoke<String>('read');
    if (value == null) return null;
    final account = NotionAccount.decode(value);
    _scope(account);
    return account;
  }

  @override
  Future<void> save(NotionAccount account) async {
    _scope(account);
    await _invoke<void>('write', account.encode());
  }

  @override
  Future<void> delete() async {
    await _invoke<void>('delete');
  }
}
