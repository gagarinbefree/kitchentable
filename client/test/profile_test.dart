import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchentable/chat.dart';
import 'package:kitchentable/main.dart';
import 'package:kitchentable/profiles.dart';
import 'package:kitchentable/room_transport.dart';
import 'package:material_ui/material_ui.dart';

import 'support/device_preferences.dart';
import 'support/direct_fake.dart';

void main() {
  testWidgets('names are editable, private to a device and survive restart', (
    tester,
  ) async {
    final device = DevicePreferences();
    final otherDevice = DevicePreferences();
    final direct = DirectFake()
      ..peers.addAll([100002, 100003])
      ..rows.add(
        Message(1, 100002, 'Привет', DateTime(2026), recipient: 100001),
      );

    Future<void> launch(DevicePreferences prefs) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directTransportProvider.overrideWithValue(direct),
            profilePreferencesProvider.overrideWithValue(prefs),
            initialProfileNamesProvider.overrideWithValue(
              await readProfileNames(prefs),
            ),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> edit(
      String tooltip,
      String value, {
      bool cancel = false,
    }) async {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), value);
      await tester.tap(find.text(cancel ? 'Отмена' : 'Сохранить'));
      await tester.pumpAndSettle();
    }

    const peerEdit = 'Редактировать имя абонента 100002';
    await launch(device);
    await edit('Мой профиль', 'Саша');
    await edit(peerEdit, '  Миша  ');
    await edit(peerEdit, 'Ошибка', cancel: true);
    await launch(device);
    expect(find.text('Саша'), findsOneWidget);
    expect(find.text('Мой номер: 100001'), findsOneWidget);
    expect(find.text('Абонент 100003'), findsOneWidget);
    await tester.tap(find.text('Миша'));
    await tester.pumpAndSettle();
    expect(find.text('Миша'), findsOneWidget);
    expect(find.textContaining('Миша ·'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ответ');
    await tester.pump();
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();
    expect(direct.recipients, [100002]);
    expect(find.textContaining('Саша ·'), findsOneWidget);
    await launch(otherDevice);
    expect(find.text('Саша'), findsNothing);
    expect(find.text('Абонент 100002'), findsOneWidget);
    await launch(device);
    await edit(peerEdit, '   ');
    await edit('Мой профиль', '');
    await launch(device);
    expect(find.text('Абонент 100002'), findsOneWidget);
    expect(find.text('Саша'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
