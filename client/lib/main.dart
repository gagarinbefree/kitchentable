import 'dart:async';
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'chat.dart';
import 'inbox.dart';
import 'room_transport.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (error) {
    FlutterError.presentError(error);
    unawaited(reportDiagnostic('flutter-error'));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(reportDiagnostic('platform-error'));
    return false;
  };
  final prefs = SharedPreferencesAsync();
  var sender = await prefs.getString('chat.sender');
  if (sender == null) {
    sender = const Uuid().v4();
    await prefs.setString('chat.sender', sender);
  }
  var credential = await prefs.getString('direct.deviceKey');
  if (credential == null) {
    final random = Random.secure();
    credential = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await prefs.setString('direct.deviceKey', credential);
  }
  runApp(
    ProviderScope(
      overrides: [
        senderProvider.overrideWithValue(sender),
        credentialProvider.overrideWithValue(credential),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({this.home, super.key});
  final Widget? home;
  @override
  Widget build(BuildContext context) {
    final theme = FTheme.neutral.light.touch;
    return MaterialApp(
      title: 'KitchenTable',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      theme: theme.toApproximateMaterialTheme(),
      builder: (context, child) => FTheme(
        data: theme,
        child: FTooltipGroup(child: child!),
      ),
      home: home ?? InboxPage(conversation: (peer) => ChatPage(peer: peer)),
    );
  }
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({this.peer, super.key});
  final int? peer;
  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _draft = TextEditingController();
  bool _sending = false;
  bool _sendFailed = false;
  String? _token;
  String? _lastText;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _draft.text.trim();
    if (_sending || text.isEmpty) return;
    if (_lastText != text) _token = const Uuid().v4();
    _lastText = text;
    setState(() {
      _sending = true;
      _sendFailed = false;
    });
    try {
      final peer = widget.peer;
      if (peer == null) {
        await ref.read(chatProvider.notifier).send(text, _token!);
      } else {
        await ref.read(directChatProvider.notifier).sendTo(peer, text, _token!);
      }
      if (!mounted) return;
      if (_draft.text.trim() == text) _draft.clear();
      _lastText = null;
    } on Exception {
      unawaited(reportDiagnostic('send-failed'));
      if (mounted) setState(() => _sendFailed = true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    final chat = peer == null
        ? ref.watch(chatProvider)
        : ref.watch(directChatProvider);
    final sender = peer == null
        ? ref.watch(senderProvider)
        : chat.number.toString();
    final messages = peer == null
        ? chat.messages
        : chat.messages
              .where(
                (row) => row.sender == peer.toString() || row.recipient == peer,
              )
              .toList();
    final colors = Theme.of(context).colorScheme;
    final status = switch (chat.connection) {
      Connection.connecting => 'Подключение…',
      Connection.online => 'На связи',
      Connection.offline => 'Соединение потеряно · повторяем',
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      if (Navigator.of(context).canPop()) const BackButton(),
                      CircleAvatar(
                        backgroundColor: colors.primaryContainer,
                        child: Icon(
                          Icons.forum_outlined,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            peer == null ? 'Общий чат' : 'Абонент $peer',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            status,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: messages.isEmpty
                      ? Center(
                          child: Text(
                            chat.connection == Connection.online
                                ? 'Сообщений пока нет'
                                : status,
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message =
                                messages[messages.length - 1 - index];
                            return _Bubble(
                              message: message,
                              mine: message.sender == sender,
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                if (_sendFailed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Не удалось отправить. Попробуйте ещё раз.',
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: FTextField(
                          control: FTextFieldControl.managed(
                            controller: _draft,
                          ),
                          hint: 'Сообщение',
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 2000,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _draft,
                        builder: (context, value, _) => FButton(
                          onPress: value.text.trim().isEmpty || _sending
                              ? null
                              : _send,
                          mainAxisSize: MainAxisSize.min,
                          child: const Text('Отправить'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});
  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time = message.time;
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final author = mine
        ? 'Вы'
        : message.recipient == null
        ? 'Гость ${message.sender.substring(0, 4)}'
        : 'Абонент ${message.sender}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: .84,
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: mine
                  ? colors.primaryContainer
                  : colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$author · $clock',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 3),
                SelectionArea(child: Text(message.text)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
