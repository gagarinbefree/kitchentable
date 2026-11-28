import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchentable/chat.dart';
import 'package:kitchentable/room_transport.dart';

import '../support/direct_fake.dart';

void main() {
  test('refresh includes missed messages once and keeps the subscriber number', () async {
    final transport = DirectFake();
    final container = ProviderContainer(
      overrides: [directTransportProvider.overrideWithValue(transport)],
    );
    addTearDown(container.dispose);
    final online = Completer<void>();
    container.listen(directChatProvider, (_, state) {
      if (state.connection == Connection.online && !online.isCompleted) {
        online.complete();
      }
    });
    await online.future;

    transport.rows.add(
      Message(17, 100002, 'hello', DateTime.utc(2026), recipient: 100001),
    );
    final inbox = container.read(directChatProvider.notifier);
    await inbox.refreshInbox();
    await inbox.refreshInbox();
    final state = container.read(directChatProvider);
    expect(state.number, 100001);
    expect(state.messages.map((row) => row.id), [17]);
    expect(transport.recipients, isEmpty);
  });

  test('direct message decoding keeps the sender, recipient and timestamp', () {
    final message = Message.fromJson({
      'id': 42,
      'sender': 100001,
      'recipient': 100002,
      'body': 'reply',
      'sentAt': '2026-11-26T10:30:00Z',
    });
    expect(message.id, 42);
    expect(message.sender, 100001);
    expect(message.recipient, 100002);
    expect(message.text, 'reply');
    expect(message.time.toUtc(), DateTime.utc(2026, 11, 26, 10, 30));
  });
}
