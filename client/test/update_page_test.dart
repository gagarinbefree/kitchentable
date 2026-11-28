import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kitchentable/chat.dart';
import 'package:kitchentable/inbox.dart';
import 'package:kitchentable/main.dart';
import 'package:kitchentable/updates.dart';
import 'package:material_ui/material_ui.dart';

import 'support/direct_fake.dart';

class _Updates extends AppUpdates {
  int installs = 0;
  @override
  Future<UpdateCheck> check() async =>
      (installed: '1.0.9', available: AppRelease(10, '1.0.10', 100, 'a' * 64));

  @override
  Future<String> install(
    AppRelease release,
    http.Client client,
    void Function(double) progress,
    bool Function() active,
  ) async {
    expect(active(), isTrue);
    installs++;
    return 'installer';
  }
}

void main() {
  testWidgets('Cancel closes the automatic offer; settings can open it again', (
    tester,
  ) async {
    final updates = _Updates();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          directTransportProvider.overrideWithValue(DirectFake()),
          updatesProvider.overrideWithValue(updates),
        ],
        child: MyApp(
          home: InboxPage(
            checkUpdatesOnStart: true,
            conversation: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Доступна версия 1.0.10'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.text('Абоненты'), findsOneWidget);
    expect(updates.installs, 0);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Обновления'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Установить'));
    await tester.pumpAndSettle();
    expect(updates.installs, 1);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.text('Настройки'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
