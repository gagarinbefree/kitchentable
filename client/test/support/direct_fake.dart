import 'package:flutter/foundation.dart';
import 'package:kitchentable/room_transport.dart';

class DirectFake implements DirectTransport {
  final rows = <Message>[];
  late VoidCallback changed;
  final recipients = <int>[];
  @override
  Future<void> connect(VoidCallback onMessage, VoidCallback onClose) async {
    changed = onMessage;
  }

  @override
  Future<int> myNumber() async => 100001;
  @override
  Future<bool> subscriberExists(int number) async => number == 100002;
  @override
  Future<List<Message>> history(int after) async =>
      rows.where((m) => m.id > after).toList();
  @override
  Future<void> sendTo(int number, String token, String text) async {
    recipients.add(number);
    rows.add(
      Message(
        rows.length + 1,
        '100001',
        text,
        DateTime(2026),
        recipient: number,
      ),
    );
    changed();
  }

  @override
  Future<void> close() async {}
}
