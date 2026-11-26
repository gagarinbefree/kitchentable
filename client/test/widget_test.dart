import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:kitchentable/chat.dart';
import 'package:kitchentable/room_transport.dart';
import 'package:kitchentable/main.dart';

class FakeRoom implements RoomTransport {
  final rows = <Message>[];
  final tokens = <String>[];
  late VoidCallback notify;
  late VoidCallback drop;
  int connections = 0;

  @override
  Future<void> connect(VoidCallback onMessage, VoidCallback onClose) async {
    connections++;
    notify = onMessage;
    drop = onClose;
  }

  @override
  Future<List<Message>> history(int after) async =>
      rows.where((row) => row.id > after).toList();

  @override
  Future<void> send(String author, String token, String text) async {
    tokens.add(token);
    if (tokens.length == 1) throw Exception('ack lost');
    rows.add(Message(1, author, text, DateTime(2026)));
    notify();
  }

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets(
    'retry uses the same token; push and reconnect load missing messages',
    (tester) async {
      final room = FakeRoom();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            senderProvider.overrideWithValue(
              'aaaaaaaa-1111-4111-8111-111111111111',
            ),
            transportProvider.overrideWithValue(room),
          ],
          child: const MyApp(home: ChatPage()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('На связи'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'Привет!');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Отправить').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Не удалось отправить. Попробуйте ещё раз.'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Отправить').first);
      await tester.pumpAndSettle();
      expect(room.tokens, hasLength(2));
      expect(room.tokens.first, room.tokens.last);
      expect(find.text('Привет!'), findsOneWidget);
      room.drop();
      room.rows.add(Message(2, 'bbbbbbbb', 'До встречи', DateTime(2026)));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(room.connections, greaterThan(1));
      expect(find.text('До встречи'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
