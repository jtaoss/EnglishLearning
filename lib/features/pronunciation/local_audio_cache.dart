import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:english_learning/features/pronunciation/pronunciation_content.dart';

abstract interface class PronunciationAudioCache {
  Future<File> resolve(PronunciationContent content);
}

/// Only explicitly licensed bundled assets are cached. No remote URL is fetched.
final class LocalAudioCache implements PronunciationAudioCache {
  LocalAudioCache({
    Future<Directory> Function()? directory,
    AssetBundle? bundle,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _bundle = bundle ?? rootBundle;
  final Future<Directory> Function() _directory;
  final AssetBundle _bundle;
  final Map<String, Future<File>> _pending = {};

  @override
  Future<File> resolve(PronunciationContent content) {
    return _pending.putIfAbsent(content.assetId, () async {
      try {
        return await _resolve(content);
      } finally {
        _pending.remove(content.assetId);
      }
    });
  }

  Future<File> _resolve(PronunciationContent content) async {
    if (!content.cacheAllowed) throw const FormatException('此音频未获准离线缓存。');
    final root = await _directory();
    final folder = Directory(p.join(root.path, 'pronunciation', 'cache'));
    await folder.create(recursive: true);
    // MSIX/AppContainer can virtualize Roaming onto another volume. Use the
    // resolved directory for both sides of publication, not its logical alias.
    final resolvedFolder = await folder.resolveSymbolicLinks();
    final file = File(
      p.join(
        resolvedFolder,
        '${content.assetId}-${content.sha256.substring(0, 16)}.wav',
      ),
    );
    if (await file.exists() &&
        sha256.convert(await file.readAsBytes()).toString() == content.sha256) {
      return file;
    }
    final data = await _bundle.load(content.assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (sha256.convert(bytes).toString() != content.sha256) {
      throw const FormatException('音频文件校验失败，请恢复应用资源后重试。');
    }
    final temporary = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      try {
        return await temporary.rename(file.path);
      } on FileSystemException catch (error) {
        // Some redirected providers still reject rename as EXDEV. Cache data
        // is disposable: copy, then verify before ever returning a file.
        if (error.osError?.errorCode != 17 && error.osError?.errorCode != 18) {
          rethrow;
        }
        await temporary.copy(file.path);
        if (sha256.convert(await file.readAsBytes()).toString() !=
            content.sha256) {
          throw const FormatException('缓存写入未完成，请重试。');
        }
        return file;
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
