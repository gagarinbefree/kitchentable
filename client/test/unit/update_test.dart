import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchentable/updates.dart';

void main() {
  final release = {
    'tag_name': 'v1.0.10',
    'draft': false,
    'prerelease': false,
    'assets': [
      {
        'name': 'KitchenTable-Android.apk',
        'state': 'uploaded',
        'size': 120,
        'digest': 'sha256:${'a' * 64}',
      },
    ],
  };
  test('only a newer stable release with the published APK is installable', () {
    final update = findUpdate(release, 9)!;
    expect(update.version, '1.0.10');
    expect(findUpdate(release, 10), isNull);
    expect(findUpdate(release, 11), isNull);
    expect(findUpdate({...release, 'prerelease': true}, 9), isNull);
    expect(
      () => findUpdate({...release, 'assets': []}, 9),
      throwsFormatException,
    );
  });
  test(
    'only a verified download reaches the installer and cancel stops handoff',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('kitchentable/updates');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final directory = await Directory.systemTemp.createTemp(
        'kt-update-test-',
      );
      final calls = <String>[];
      var active = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'directory' => directory.path,
          'verify' => null,
          'install' => 'installer',
          _ => throw UnsupportedError(call.method),
        };
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      });
      final bytes = [1, 2, 3];
      final release = AppRelease(
        10,
        '1.0.10',
        3,
        sha256.convert(bytes).toString(),
      );
      final service = AppUpdates();
      var requests = 0;
      var payload = [3, 2, 1];
      final client = MockClient((request) async {
        expect(request.url, release.url);
        requests++;
        return http.Response.bytes(payload, 200);
      });
      addTearDown(client.close);
      Future<String> install() =>
          service.install(release, client, (_) {}, () => active);
      await expectLater(install(), throwsFormatException);
      expect(calls, ['directory']);
      payload = bytes;
      active = false;
      expect(await install(), 'cancelled');
      expect(calls, ['directory', 'directory']);
      active = true;
      expect(await install(), 'installer');
      expect(calls.sublist(2), ['directory', 'verify', 'install']);
      expect(requests, 2);
    },
  );
}
