import 'package:flutter_test/flutter_test.dart';
import 'package:kitchentable/room_transport.dart';
import 'package:kitchentable/unread.dart';

Message row(int id, int sender, int recipient) =>
    Message(id, sender, 'text', DateTime(2026), recipient: recipient);

void main() {
  test('counts new incoming messages per conversation across restarts', () {
    final ledger = UnreadLedger();
    final history = [row(1, 2, 1)];
    ledger.receive(history, 1, {2, 3});
    expect(ledger.total, 0);
    history.addAll([row(2, 2, 1), row(3, 1, 2), row(4, 3, 1), row(5, 2, 1)]);
    ledger.receive(history, 1, {2, 3});
    ledger.receive(history, 1, {2, 3});
    expect(ledger.total, 3);
    final restored = UnreadLedger.decode(ledger.encode());
    restored.receive(history, 1, {2, 3});
    expect(restored.total, 3);
    restored.showConversation(2);
    expect(restored.total, 1);
    history.add(row(6, 2, 1));
    restored.receive(history, 1, {2, 3});
    expect(restored.total, 1);
    restored.showConversation(null);
    history.add(row(7, 2, 1));
    restored.receive(history, 1, {2, 3});
    expect(restored.total, 2);
    restored.showConversation(3);
    expect(restored.total, 1);
    restored.showConversation(2);
    expect(restored.total, 0);
  });
  test('the returning peer shows only the new unread message', () {
    final ledger = UnreadLedger();
    final messages = <Message>[];
    ledger.receive(messages, 1, {2, 3});
    messages.addAll([row(1, 2, 1), row(2, 3, 1)]);
    ledger.receive(messages, 1, {2, 3});
    final restored = UnreadLedger.decode(ledger.encode());
    restored.receive(messages, 1, {3});
    expect(restored.total, 1);
    messages.add(row(3, 2, 1));
    restored.receive(messages, 1, {2, 3});
    expect(restored.countFor(2), 1);
    restored.receive(messages, 1, {2, 3});
    expect(restored.total, 2);
  });
}
