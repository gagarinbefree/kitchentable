import 'dart:async';
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'chat.dart';
import 'inbox.dart';
import 'profiles.dart';
import 'room_transport.dart';
import 'settings.dart';
import 'unread.dart';

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
  var credential = await prefs.getString('direct.deviceKey');
  if (credential == null) {
    final random = Random.secure();
    credential = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await prefs.setString('direct.deviceKey', credential);
  }
  final mode = await readThemeMode(prefs);
  final profilePrefs = openProfilePreferences();
  final names = await readProfileNames(profilePrefs);
  final unread = await loadAndroidUnread();
  runApp(
    ProviderScope(
      overrides: [
        unreadProvider.overrideWithValue(unread),
        credentialProvider.overrideWithValue(credential),
        themePreferencesProvider.overrideWithValue(prefs),
        initialThemeModeProvider.overrideWithValue(mode),
        profilePreferencesProvider.overrideWithValue(profilePrefs),
        initialProfileNamesProvider.overrideWithValue(names),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({this.home, super.key});
  final Widget? home;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      theme: spectrumLight,
      darkTheme: spectrumBlack,
      themeMode: ref.watch(themeModeProvider),
      title: 'KitchenTable',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: {
        const Locale('en'),
        ...kMaterialSupportedLanguages.map(Locale.new),
      },
      home: home ?? InboxPage(conversation: (peer) => ChatPage(peer: peer)),
    );
  }
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({required this.peer, super.key});
  final int peer;
  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _draft = TextEditingController();
  bool _sending = false;
  bool _sendFailed = false;
  String? _token;
  String? _lastText;

  late final UnreadLedger _unread;
  late final AppLifecycleListener _lifecycle;
  bool _currentRoute = false;

  @override
  void initState() {
    super.initState();
    _unread = ref.read(unreadProvider);
    _lifecycle = AppLifecycleListener(
      onStateChange: (_) => _updateVisibility(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentRoute = ModalRoute.isCurrentOf(context) ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateVisibility();
    });
  }

  void _updateVisibility() {
    if (_currentRoute &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _unread.showConversation(widget.peer);
    } else {
      _unread.hideConversation(widget.peer);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _unread.hideConversation(widget.peer);
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
      await ref
          .read(directChatProvider.notifier)
          .sendTo(widget.peer, text, _token!);
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
    final names = ref.watch(profileNamesProvider);
    final peerName = names[peer] ?? 'Абонент $peer';
    final chat = ref.watch(directChatProvider);
    final messages = chat.messages
        .where((row) => row.sender == peer || row.recipient == peer)
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              peerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              status,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
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
                            final mine = message.sender == chat.number;
                            return _Bubble(
                              message: message,
                              mine: mine,
                              author: mine ? (names[null] ?? 'Вы') : peerName,
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
                        child: TextField(
                          controller: _draft,
                          decoration: const InputDecoration(
                            hintText: 'Сообщение',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 2000,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _draft,
                        builder: (context, value, _) => FilledButton(
                          onPressed: value.text.trim().isEmpty || _sending
                              ? null
                              : _send,
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
  const _Bubble({
    required this.message,
    required this.mine,
    required this.author,
  });
  final String author;
  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time = message.time;
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final ink = mine ? colors.onPrimaryContainer : colors.onSurface;
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
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: mine ? colors.primaryContainer : colors.outlineVariant,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$author · $clock',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: ink),
                ),
                const SizedBox(height: 3),
                SelectionArea(
                  child: Text(message.text, style: TextStyle(color: ink)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
