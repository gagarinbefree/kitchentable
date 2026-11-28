import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchentable/chat.dart';
import 'package:kitchentable/main.dart';
import 'package:kitchentable/profiles.dart';
import 'package:kitchentable/room_transport.dart';
import 'package:material_ui/material_ui.dart';

import 'support/direct_fake.dart';

void main() {
  testWidgets(
    'contact removal requires confirmation and cancellation keeps the contact',
    (tester) async {
      final transport = DirectFake()..peers.addAll([100002, 100003]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directTransportProvider.overrideWithValue(transport),
            initialProfileNamesProvider.overrideWithValue({100002: 'Миша'}),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Редактировать имя абонента 100002'));
      await tester.pumpAndSettle();
      Future<void> confirmDialog() async {
        await tester.tap(find.text('Скрыть из списка'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('Миша'),
          ),
          findsOneWidget,
        );
        expect(transport.peers, contains(100002));
      }

      await confirmDialog();
      await tester.tap(find.widgetWithText(TextButton, 'Отмена').last);
      await tester.pumpAndSettle();
      expect(transport.peers, [100002, 100003]);
      await confirmDialog();
      await tester.tap(find.text('Скрыть'));
      await tester.pumpAndSettle();
      expect(find.text('Абоненты'), findsOneWidget);
      expect(transport.peers, [100003]);
      expect(find.text('Миша'), findsNothing);
      transport.peers.add(100002);
      transport.rows.add(
        Message(10, 100002, 'Я снова здесь', DateTime(2026), recipient: 100001),
      );
      transport.changed();
      await tester.pumpAndSettle();
      expect(find.text('Миша'), findsOneWidget);
      expect(find.text('Я снова здесь'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
