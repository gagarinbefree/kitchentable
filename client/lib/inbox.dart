import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'chat.dart';
import 'room_transport.dart';

class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({required this.conversation, super.key});
  final Widget Function(int? peer) conversation;

  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage> {
  final _number = TextEditingController();
  late final AppLifecycleListener _lifecycle;
  String? _error;
  bool _lookingUp = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(directChatProvider.notifier).refreshInbox(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _number.dispose();
    super.dispose();
  }

  void _open(int? peer) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => widget.conversation(peer)));
  }

  Future<void> _lookup() async {
    if (_lookingUp) return;
    final peer = int.tryParse(_number.text.trim());
    final me = ref.read(directChatProvider).number;
    if (peer == null || peer <= 0 || peer == me) {
      setState(() => _error = 'Введите номер другого абонента');
      return;
    }
    setState(() {
      _error = null;
      _lookingUp = true;
    });
    try {
      final exists = await ref
          .read(directChatProvider.notifier)
          .subscriberExists(peer);
      if (!mounted) return;
      if (exists) {
        _number.clear();
        _open(peer);
      } else {
        setState(() => _error = 'Абонент не найден');
      }
    } on Exception {
      if (mounted) setState(() => _error = 'Нет связи с сервером');
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(directChatProvider);
    final me = inbox.number;
    final threads = <int, Message>{};
    for (final message in inbox.messages.reversed) {
      final peer = message.sender == me.toString()
          ? message.recipient!
          : int.parse(message.sender);
      threads.putIfAbsent(peer, () => message);
    }
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Сообщения',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  FButton(
                    variant: .outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => _open(null),
                    child: const Text('Общий чат'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (me != null) SelectableText('Мой номер: $me'),
              Text(switch (inbox.connection) {
                Connection.connecting => 'Подключение…',
                Connection.online => 'На связи',
                Connection.offline => 'Соединение потеряно · повторяем',
              }, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FTextField(
                      control: FTextFieldControl.managed(controller: _number),
                      hint: 'Номер абонента',
                      keyboardType: TextInputType.number,
                      maxLines: 1,
                      onSubmit: (_) => _lookup(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FButton(
                    mainAxisSize: MainAxisSize.min,
                    onPress: _lookingUp || inbox.connection != Connection.online
                        ? null
                        : _lookup,
                    child: const Text('Открыть'),
                  ),
                ],
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              Expanded(
                child: threads.isEmpty
                    ? const Center(child: Text('Личных сообщений пока нет'))
                    : ListView(
                        children: [
                          for (final thread in threads.entries)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('Абонент ${thread.key}'),
                              subtitle: Text(
                                thread.value.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _open(thread.key),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
