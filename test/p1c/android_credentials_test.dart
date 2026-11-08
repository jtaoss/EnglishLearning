import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/integrations/notion/android_notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const dummy = 'fixture_only_android_not_a_real_token';
  final calls = <MethodCall>[];
  String? stored;
  setUp(() {
    stored = null;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidNotionCredentials.channel, (
          call,
        ) async {
          calls.add(call);
          switch (call.method) {
            case 'read':
              return stored;
            case 'write':
              stored = (call.arguments as Map)['value'] as String;
            case 'delete':
              stored = null;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidNotionCredentials.channel, null),
  );

  test(
    'Android channel preserves account and isolates test namespace',
    () async {
      final credentials = AndroidNotionCredentials(testNamespace: 'unit_only');
      expect(await credentials.read(), isNull);
      await credentials.save(
        NotionAccount(dataSourceId: notionPilotSource, token: dummy),
      );
      expect((await credentials.read())!.token, dummy);
      await credentials.delete();
      expect(await credentials.read(), isNull);
      expect(
        calls.every(
          (c) => (c.arguments as Map)['test_namespace'] == 'unit_only',
        ),
        true,
      );
    },
  );

  test(
    'Production Android namespace is absent from native arguments',
    () async {
      await AndroidNotionCredentials().read();
      expect(
        (calls.single.arguments as Map).containsKey('test_namespace'),
        false,
      );
    },
  );

  test('Unapproved source rejected before calling platform storage', () async {
    await expectLater(
      AndroidNotionCredentials().save(
        NotionAccount(
          dataSourceId: '11111111-1111-4111-8111-111111111111',
          token: dummy,
        ),
      ),
      throwsA(isA<NotionFailure>()),
    );
    expect(calls, isEmpty);
  });

  test('Native errors do not expose credential or exception details', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidNotionCredentials.channel, (_) async {
          throw PlatformException(
            code: 'internal',
            message: dummy,
            details: dummy,
          );
        });
    try {
      await AndroidNotionCredentials().read();
      fail('Expected safe error');
    } on NotionFailure catch (error) {
      expect(error.toString(), isNot(contains(dummy)));
      expect(error.toString(), contains('安全存储不可用'));
    }
  });

  test('Malformed saved account fails closed with a safe message', () async {
    stored = dummy;
    await expectLater(
      AndroidNotionCredentials().read(),
      throwsA(
        isA<NotionFailure>().having(
          (e) => e.message,
          'safe message',
          isNot(contains(dummy)),
        ),
      ),
    );
  });

  test(
    'Stored account cannot silently widen the Android source scope',
    () async {
      stored = NotionAccount(
        dataSourceId: '11111111-1111-4111-8111-111111111111',
        token: dummy,
      ).encode();
      await expectLater(
        AndroidNotionCredentials().read(),
        throwsA(isA<NotionFailure>()),
      );
    },
  );
}
