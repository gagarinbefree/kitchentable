import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'room_transport.dart';

final senderProvider = Provider<String>(
  (ref) => throw StateError('Missing sender'),
);
final transportProvider = Provider<RoomTransport>((ref) => SignalRRoom());
final chatProvider = NotifierProvider<Chat, ChatState>(Chat.new);

final credentialProvider = Provider<String>(
  (ref) => throw StateError('Missing device credential'),
);
final directTransportProvider = Provider<DirectTransport>(
  (ref) => SignalRDirect(ref.watch(credentialProvider)),
);
final directChatProvider = NotifierProvider<DirectChat, ChatState>(
  DirectChat.new,
);

enum Connection { connecting, online, offline }

class ChatState {
  const ChatState(this.messages, this.connection, [this.number]);
  final int? number;
  final List<Message> messages;
  final Connection connection;
}

abstract class MessageFeed<T extends HistoryTransport>
    extends Notifier<ChatState> {
  T get transport;
  Future<int?> identify() async => null;
  late T _transport;
  Timer? _retry;
  int _session = 0;
  bool _ready = false;
  bool _reading = false;
  bool _dirty = false;

  @override
  ChatState build() {
    _transport = transport;
    _retry = Timer(Duration.zero, _connect);
    ref.onDispose(() {
      _session++;
      _retry?.cancel();
      unawaited(_transport.close());
    });
    return const ChatState([], Connection.connecting);
  }

  bool _current(int session) => ref.mounted && session == _session;

  Future<void> _connect() async {
    final session = ++_session;
    try {
      await _transport.connect(
        () => _refresh(session),
        () => _disconnect(session),
      );
      if (!_current(session)) return;
      final number = await identify();
      if (!_current(session)) return;
      state = ChatState(state.messages, state.connection, number);
      _ready = true;
      await _refresh(session);
    } on Exception {
      _disconnect(session);
    }
  }

  void _disconnect(int session) {
    if (!_current(session)) return;
    _session++;
    _ready = false;
    _reading = false;
    _dirty = false;
    state = ChatState(state.messages, Connection.offline, state.number);
    unawaited(_transport.close());
    _retry = Timer(const Duration(seconds: 2), _connect);
  }

  Future<void> _refresh(int session) async {
    if (!_current(session)) return;
    _dirty = true;
    if (!_ready || _reading) return;
    _reading = true;
    try {
      do {
        _dirty = false;
        final current = state.messages;
        final page = await _transport.history(
          current.isEmpty ? 0 : current.last.id,
        );
        if (!_current(session)) return;
        if (page.isNotEmpty || state.connection != Connection.online) {
          state = ChatState(
            [...current, ...page],
            Connection.online,
            state.number,
          );
        }
        if (page.length == 200) _dirty = true;
      } while (_dirty);
    } on Exception {
      _disconnect(session);
    } finally {
      if (_current(session)) _reading = false;
    }
  }

  Future<void> deliver(Future<void> Function() action) async {
    if (!_ready) throw const FormatException('Disconnected');
    final session = _session;
    await action();
    unawaited(_refresh(session));
  }
}

class Chat extends MessageFeed<RoomTransport> {
  @override
  RoomTransport get transport => ref.watch(transportProvider);
  Future<void> send(String text, String token) =>
      deliver(() => _transport.send(ref.read(senderProvider), token, text));
}

class DirectChat extends MessageFeed<DirectTransport> {
  @override
  DirectTransport get transport => ref.watch(directTransportProvider);
  @override
  Future<int?> identify() => _transport.myNumber();
  Future<void> refreshInbox() => _refresh(_session);
  Future<bool> subscriberExists(int number) =>
      _transport.subscriberExists(number);
  Future<void> sendTo(int number, String text, String token) =>
      deliver(() => _transport.sendTo(number, token, text));
}
