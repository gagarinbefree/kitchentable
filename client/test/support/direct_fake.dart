import 'package:flutter/foundation.dart';
import 'package:kitchentable/room_transport.dart';

class DirectFake implements DirectTransport {
  final rows = <Message>[];
  late VoidCallback changed;
  final recipients = <int>[];
  final peers = <int>[];
  @override
  Future<void> connect(VoidCallback onMessage, VoidCallback onClose) async {
    changed = onMessage;
  }

  @override
  Future<int> myNumber() async => 100001;
  @override
  Future<List<int>> contacts() async => List.of(peers);
  @override
  Future<String> createInvite() async => 'a' * 64;
  @override
  Future<int> previewInvite(String token) async => 100002;
  @override
  Future<int> acceptInvite(String token) async {
    if (!peers.contains(100002)) peers.add(100002);
    changed();
    return 100002;
  }

  @override
  Future<void> hideContact(int peer) async {
    peers.remove(peer);
    changed();
  }

  @override
  Future<List<Message>> history(int after) async =>
      rows.where((m) => m.id > after).toList();
  @override
  Future<void> sendTo(int number, String token, String text) async {
    recipients.add(number);
    rows.add(
      Message(rows.length + 1, 100001, text, DateTime(2026), recipient: number),
    );
    changed();
  }

  @override
  Future<void> close() async {}
}
