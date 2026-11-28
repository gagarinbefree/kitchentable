import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchentable/chat.dart';
import 'package:kitchentable/main.dart';
import 'package:kitchentable/room_transport.dart';
import 'package:kitchentable/unread.dart';
import 'package:material_ui/material_ui.dart';

import 'support/direct_fake.dart';

void main() {
  testWidgets('only the foreground conversation marks incoming messages read', (
    tester,
  ) async {
    final ledger = UnreadLedger();
    final direct = DirectFake()..peers.addAll([100002, 100003]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unreadProvider.overrideWithValue(ledger),
          directTransportProvider.overrideWithValue(direct),
        ],
        child: const MyApp(),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    Future<void> receive(int sender) async {
      direct.rows.add(
        Message(
          direct.rows.length + 1,
          sender,
          'hello',
          DateTime(2026),
          recipient: 100001,
        ),
      );
      direct.changed();
      await tester.pumpAndSettle();
    }

    await receive(100002);
    await receive(100003);
    expect(find.byType(Badge), findsNWidgets(2));
    await tester.tap(find.text('Абонент 100002'));
    await tester.pumpAndSettle();
    expect(ledger.total, 1);
    await receive(100002);
    expect(ledger.total, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await receive(100002);
    expect(ledger.total, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(ledger.total, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await receive(100002);
    expect(ledger.total, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
