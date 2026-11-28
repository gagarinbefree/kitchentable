import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_page.dart';

const _themeKey = 'appearance.spectrumTheme';
final themePreferencesProvider = Provider((ref) => SharedPreferencesAsync());
final initialThemeModeProvider = Provider((ref) => ThemeMode.light);
final themeModeProvider = NotifierProvider<SpectrumThemeMode, ThemeMode>(
  SpectrumThemeMode.new,
);

Future<ThemeMode> readThemeMode(SharedPreferencesAsync prefs) async =>
    await prefs.getString(_themeKey) == 'dark'
    ? ThemeMode.dark
    : ThemeMode.light;

class SpectrumThemeMode extends Notifier<ThemeMode> {
  Future<void> _pending = Future.value();

  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  Future<void> select(ThemeMode mode) {
    // Preserve tap order even when two preference writes overlap.
    final write = _pending.then((_) async {
      if (!ref.mounted || state == mode) return;
      await ref.read(themePreferencesProvider).setString(_themeKey, mode.name);
      if (ref.mounted) state = mode;
    });
    _pending = write.catchError((Object _) {});
    return write;
  }
}

const _blue = Color(0xFF0000CD);
const _cyan = Color(0xFF00FFFF);
const _yellow = Color(0xFFFFFF00);
const _paper = Color(0xFFCDCDCD);
const _black = Colors.black;
const _white = Colors.white;

final spectrumLight = _theme(false);
final spectrumBlack = _theme(true);

ThemeData _theme(bool dark) {
  final surface = dark ? _black : _white;
  final ink = dark ? _white : _black;
  final panel = dark ? _black : _paper;
  final accent = dark ? _cyan : _blue;
  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: accent,
    onPrimary: dark ? _black : _white,
    primaryContainer: _blue,
    onPrimaryContainer: dark ? _yellow : _white,
    secondary: dark ? _yellow : _blue,
    onSecondary: dark ? _black : _white,
    secondaryContainer: dark ? _cyan : _blue,
    onSecondaryContainer: dark ? _black : _white,
    tertiary: dark ? const Color(0xFFFF00FF) : const Color(0xFFCD00CD),
    onTertiary: _black,
    error: dark ? const Color(0xFFFF0000) : const Color(0xFFCD0000),
    onError: dark ? _black : _white,
    surface: surface,
    onSurface: ink,
    surfaceContainerLowest: surface,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: panel,
    surfaceContainerHighest: panel,
    onSurfaceVariant: ink,
    outline: dark ? _paper : _black,
    outlineVariant: _paper,
    surfaceTint: Colors.transparent,
  );
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: shape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: shape),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: surface,
      foregroundColor: ink,
    ),
  );
}

class SpectrumStripes extends StatelessWidget {
  const SpectrumStripes({super.key});

  @override
  Widget build(BuildContext context) => Transform(
    transform: Matrix4.skewX(-0.35),
    alignment: Alignment.center,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in const [
          Color(0xFFFF0000),
          _yellow,
          Color(0xFF00CD00),
          _cyan,
        ])
          SizedBox(width: 7, height: 12, child: ColoredBox(color: color)),
      ],
    ),
  );
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Обновления'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const UpdatePage()),
              ),
            ),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Чёрная')),
              ],
              selected: {mode},
              onSelectionChanged: (selection) async {
                try {
                  await ref
                      .read(themeModeProvider.notifier)
                      .select(selection.single);
                } on Exception {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Не удалось сохранить тему'),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
