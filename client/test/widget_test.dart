import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:kitchentable/chat.dart';
import 'package:kitchentable/room_transport.dart';
import 'package:kitchentable/main.dart';

import 'support/direct_fake.dart';

class RetryTransport extends DirectFake {
  final tokens = <String>[];
  late VoidCallback drop;
  int connections = 0;

  @override
  Future<void> connect(VoidCallback onMessage, VoidCallback onClose) async {
    connections++;
    drop = onClose;
    await super.connect(onMessage, onClose);
  }

  @override
  Future<void> sendTo(int number, String token, String text) async {
    tokens.add(token);
    if (tokens.length == 1) throw Exception('ack lost');
    await super.sendTo(number, token, text);
  }
}

void main() {
  testWidgets(
    'retry uses the same token; push and reconnect load missing messages',
    (tester) async {
      final direct = RetryTransport();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [directTransportProvider.overrideWithValue(direct)],
          child: const MyApp(home: ChatPage(peer: 100002)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('На связи'), findsOneWidget);
      final send = find.widgetWithText(FilledButton, 'Отправить');
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      final composer = find.byType(TextField);
      expect(tester.widget<TextField>(composer).maxLength, 2000);
      await tester.enterText(composer, 'Привет!');
      await tester.pump();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(
        find.text('Не удалось отправить. Попробуйте ещё раз.'),
        findsOneWidget,
      );
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(direct.tokens, hasLength(2));
      expect(direct.tokens.first, direct.tokens.last);
      expect(find.text('Привет!'), findsOneWidget);
      direct.drop();
      direct.rows.add(
        Message(2, 100002, 'До встречи', DateTime(2026), recipient: 100001),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(direct.connections, greaterThan(1));
      expect(find.text('До встречи'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
