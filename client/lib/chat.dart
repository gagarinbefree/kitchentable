import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'room_transport.dart';
import 'unread.dart';

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
  const ChatState(
    this.messages,
    this.connection, [
    this.number,
    this.contacts = const [],
  ]);
  final List<int> contacts;
  final int? number;
  final List<Message> messages;
  final Connection connection;
}

class DirectChat extends Notifier<ChatState> {
  late DirectTransport _transport;
  Timer? _retry;
  int _session = 0;
  bool _ready = false;
  bool _reading = false;
  bool _dirty = false;

  @override
  ChatState build() {
    _transport = ref.watch(directTransportProvider);
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
      final number = await _transport.myNumber();
      if (!_current(session)) return;
      state = ChatState(
        state.messages,
        state.connection,
        number,
        state.contacts,
      );
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
    state = ChatState(
      state.messages,
      Connection.offline,
      state.number,
      state.contacts,
    );
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
        final contacts = await _transport.contacts();
        if (!_current(session)) return;
        if (page.isNotEmpty ||
            state.connection != Connection.online ||
            !listEquals(state.contacts, contacts)) {
          state = ChatState(
            [...current, ...page],
            Connection.online,
            state.number,
            contacts,
          );
        }
        if (page.length == 200) {
          _dirty = true;
        } else {
          ref
              .read(unreadProvider)
              .receive(state.messages, state.number!, contacts.toSet());
        }
      } while (_dirty);
    } on Exception {
      _disconnect(session);
    } finally {
      if (_current(session)) _reading = false;
    }
  }

  Future<void> refreshInbox() => _refresh(_session);
  Future<String> createInvite() => _transport.createInvite();
  Future<int> previewInvite(String token) => _transport.previewInvite(token);
  Future<int> acceptInvite(String token) async {
    final peer = await _transport.acceptInvite(token);
    await refreshInbox();
    return peer;
  }

  Future<void> hideContact(int peer) async {
    if (!_ready) throw const FormatException('Disconnected');
    await _transport.hideContact(peer);
    await refreshInbox();
  }

  Future<void> sendTo(int number, String text, String token) async {
    if (!_ready) throw const FormatException('Disconnected');
    final session = _session;
    await _transport.sendTo(number, token, text);
    unawaited(_refresh(session));
  }
}
