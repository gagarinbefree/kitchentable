import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'chat.dart';
import 'contact_invite.dart';

class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({required this.conversation, super.key});
  final Widget Function(int? peer) conversation;
  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage> {
  late final AppLifecycleListener _lifecycle;

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
    super.dispose();
  }

  void _open(int? peer) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => widget.conversation(peer)));
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(directChatProvider);
    final previews = <int, String>{};
    for (final message in inbox.messages) {
      final peer = message.sender == inbox.number.toString()
          ? message.recipient!
          : int.parse(message.sender);
      previews[peer] = message.text;
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
                      'Абоненты',
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
              if (inbox.number != null)
                SelectableText('Мой номер: ${inbox.number}'),
              Text(switch (inbox.connection) {
                Connection.connecting => 'Подключение…',
                Connection.online => 'На связи',
                Connection.offline => 'Соединение потеряно · повторяем',
              }, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FButton(
                onPress: inbox.connection == Connection.online
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ContactInvitePage(),
                          ),
                        );
                      }
                    : null,
                child: const Text('Добавить абонента'),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              Expanded(
                child: inbox.contacts.isEmpty
                    ? const Center(child: Text('Пока нет абонентов'))
                    : ListView.builder(
                        itemCount: inbox.contacts.length,
                        itemBuilder: (_, index) {
                          final peer = inbox.contacts[index];
                          final preview = previews[peer];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Абонент $peer'),
                            subtitle: preview == null
                                ? null
                                : Text(
                                    preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => _open(peer),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
