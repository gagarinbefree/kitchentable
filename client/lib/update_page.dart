import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import 'updates.dart';

class UpdatePage extends ConsumerStatefulWidget {
  const UpdatePage({this.initial, super.key});
  final UpdateCheck? initial;
  @override
  ConsumerState<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends ConsumerState<UpdatePage> {
  UpdateCheck? _check;
  String? _message;
  bool _busy = false;
  double _progress = 0;
  http.Client? _client;

  @override
  void initState() {
    super.initState();
    _check = widget.initial;
    if (_check == null) _refresh();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  bool get _active => mounted && ModalRoute.of(context)?.isCurrent == true;

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await ref.read(updatesProvider).check();
      if (mounted) setState(() => _check = result);
    } on Exception {
      if (mounted) {
        setState(
          () => _message = 'Не удалось проверить обновления. Проверьте соединение и повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install(AppRelease release) async {
    final client = http.Client();
    _client = client;
    setState(() {
      _message = null;
      _busy = true;
      _progress = 0;
    });
    try {
      final result = await ref.read(updatesProvider).install(release, client, (
        value,
      ) {
        if (mounted && (value * 100).floor() != (_progress * 100).floor()) {
          setState(() => _progress = value);
        }
      }, () => _active);
      if (mounted && result == 'permission') {
        setState(
          () => _message = 'Для обновления разрешите установку из KitchenTable в настройках Android. Затем нажмите «Установить» ещё раз.',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _message =
              error.message ?? 'Не удалось открыть установщик Android.',
        );
      }
    } on Exception {
      if (mounted) {
        setState(
          () => _message =
              'Не удалось загрузить или проверить APK. Повторите попытку.',
        );
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() {
          _client = null;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = _check?.available;
    return Scaffold(
      appBar: AppBar(title: const Text('Обновления')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_check != null) Text('Установлена версия ${_check!.installed}'),
            if (release != null) ...[
              const SizedBox(height: 8),
              Text(
                'Доступна версия ${release.version}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Размер APK — ${(release.size / 1048576).toStringAsFixed(1)} МБ',
              ),
            ] else if (_check != null)
              const Text('У вас последняя версия.'),
            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(
                  value: _client == null || _progress == 0 ? null : _progress,
                ),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_message!),
              ),
            const SizedBox(height: 16),
            if (release != null)
              FilledButton(
                onPressed: _busy ? null : () => _install(release),
                child: const Text('Установить'),
              )
            else if (!_busy)
              OutlinedButton(
                onPressed: _refresh,
                child: const Text('Проверить снова'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }
}
