import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'chat.dart';
import 'contact_invite.dart';
import 'profiles.dart';
import 'settings.dart';
import 'unread.dart';

class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({required this.conversation, super.key});
  final Widget Function(int peer) conversation;
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

  void _open(int peer) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => widget.conversation(peer)));
  }

  void _edit(ProfileEditor editor) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => editor));
  }

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(profileNamesProvider);
    final inbox = ref.watch(directChatProvider);
    final unread = ref.watch(unreadProvider);
    final previews = <int, String>{};
    for (final message in inbox.messages) {
      final peer = message.sender == inbox.number
          ? message.recipient
          : message.sender;
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
                  const SpectrumStripes(),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Настройки',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsPage(),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          names[null] ?? 'Мой профиль',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (inbox.number != null)
                          SelectableText('Мой номер: ${inbox.number}'),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Мой профиль',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(
                      ProfileEditor(number: inbox.number, isMine: true),
                    ),
                  ),
                ],
              ),
              Text(switch (inbox.connection) {
                Connection.connecting => 'Подключение…',
                Connection.online => 'На связи',
                Connection.offline => 'Соединение потеряно · повторяем',
              }, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: inbox.connection == Connection.online
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
                            title: Text(
                              names[peer] ?? 'Абонент $peer',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListenableBuilder(
                                  listenable: unread,
                                  builder: (context, _) {
                                    final count = unread.countFor(peer);
                                    return count == 0
                                        ? const SizedBox.shrink()
                                        : Semantics(
                                            label:
                                                'Непрочитанных сообщений: $count',
                                            excludeSemantics: true,
                                            child: Badge.count(count: count),
                                          );
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Редактировать имя абонента $peer',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () =>
                                      _edit(ProfileEditor(number: peer)),
                                ),
                              ],
                            ),
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
