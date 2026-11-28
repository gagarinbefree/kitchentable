import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchentable/chat.dart';
import 'package:kitchentable/main.dart';
import 'package:kitchentable/settings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/direct_fake.dart';

class MemoryPreferences extends Fake implements SharedPreferencesAsync {
  final values = <String, String>{};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  testWidgets(
    'settings switches both themes across routes and restores the saved choice',
    (tester) async {
      final prefs = MemoryPreferences();
      Future<void> launch() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              directTransportProvider.overrideWithValue(
                DirectFake()..peers.add(100002),
              ),
              themePreferencesProvider.overrideWithValue(prefs),
              initialThemeModeProvider.overrideWithValue(
                await readThemeMode(prefs),
              ),
            ],
            child: const MyApp(),
          ),
        );
        await tester.pumpAndSettle();
      }

      Color surface(String label) =>
          Theme.of(tester.element(find.text(label).last)).colorScheme.surface;
      await launch();
      expect(surface('Абоненты'), Colors.white);
      for (final dark in [true, false]) {
        final expected = dark ? Colors.black : Colors.white;
        await tester.tap(find.byTooltip('Настройки'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(dark ? 'Чёрная' : 'Светлая'));
        await tester.pumpAndSettle();
        expect(find.text('Тема ZX Spectrum'), findsNothing);
        final theme = Theme.of(tester.element(find.byType(SettingsPage)));
        expect(theme.colorScheme.surface, expected);
        final defaults = ThemeData(colorScheme: theme.colorScheme);
        expect(
          theme.textTheme.bodyMedium!.fontSize,
          defaults.typography.englishLike.bodyMedium!.fontSize,
        );
        expect(theme.iconTheme.size, defaults.iconTheme.size);
        expect(theme.visualDensity, defaults.visualDensity);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(surface('Абоненты'), expected);
        await tester.tap(find.text('Абонент 100002'));
        await tester.pumpAndSettle();
        expect(surface('Абонент 100002'), expected);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Добавить абонента'));
        await tester.pumpAndSettle();
        expect(surface('Сканировать QR'), expected);
        expect(
          tester.widget<QrImageView>(find.byType(QrImageView)).backgroundColor,
          Colors.white,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await launch();
        expect(surface('Абоненты'), expected);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
