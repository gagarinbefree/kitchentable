import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchentable/chat.dart';
import 'package:kitchentable/main.dart';
import 'package:kitchentable/room_transport.dart';

import 'support/direct_fake.dart';

void main() {
  testWidgets('resume fetches personal messages missed in the background', (
    tester,
  ) async {
    final direct = DirectFake();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [directTransportProvider.overrideWithValue(direct)],
        child: const MyApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    direct.peers.add(100002);
    direct.rows.add(
      Message(
        1,
        '100002',
        'Пока приложение свёрнуто',
        DateTime(2026),
        recipient: 100001,
      ),
    );
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(find.text('Пока приложение свёрнуто'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'start a personal dialogue and receive a separate incoming conversation',
    (tester) async {
      final direct = DirectFake();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [directTransportProvider.overrideWithValue(direct)],
          child: const MyApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Мой номер: 100001'), findsOneWidget);
      expect(find.text('Номер абонента'), findsNothing);
      expect(find.text('Пока нет абонентов'), findsOneWidget);
      await tester.tap(find.text('Добавить абонента'));
      await tester.pumpAndSettle();
      expect(find.text('Сканировать QR'), findsOneWidget);
      direct.peers.add(100002);
      direct.changed();
      await tester.pumpAndSettle();
      expect(find.text('Абоненты'), findsOneWidget);
      expect(find.text('Абонент 100002'), findsOneWidget);
      expect(direct.rows, isEmpty);
      await tester.tap(find.text('Абонент 100002'));
      await tester.pumpAndSettle();
      expect(find.text('Абонент 100002'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate((w) => w is EditableText && !w.readOnly),
        'Только тебе',
      );
      await tester.pump();
      await tester.tap(find.text('Отправить'));
      await tester.pumpAndSettle();
      expect(direct.recipients, [100002]);
      direct.peers.add(100003);
      direct.rows.add(
        Message(
          2,
          '100003',
          'Другая переписка',
          DateTime(2026),
          recipient: 100001,
        ),
      );
      direct.changed();
      await tester.pumpAndSettle();
      expect(find.text('Другая переписка'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Абонент 100003'));
      await tester.pumpAndSettle();
      expect(find.text('Другая переписка'), findsOneWidget);
      expect(find.text('Только тебе'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
