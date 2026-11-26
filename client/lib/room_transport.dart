import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:signalr_netcore/signalr_client.dart';

const chatServer = String.fromEnvironment(
  'CHAT_SERVER',
  defaultValue: 'http://192.168.31.84:8787',
);

class Message {
  const Message(this.id, this.sender, this.text, this.time, {this.recipient});
  factory Message.fromJson(Map<String, dynamic> json) => Message(
    json['id'] as int,
    json['sender'].toString(),
    json['body'] as String,
    DateTime.parse(json['sentAt'] as String).toLocal(),
    recipient: json['recipient'] as int?,
  );
  final int? recipient;
  final int id;
  final String sender;
  final String text;
  final DateTime time;
}

abstract interface class HistoryTransport {
  Future<void> connect(VoidCallback onMessage, VoidCallback onClose);
  Future<List<Message>> history(int after);
  Future<void> close();
}

abstract interface class RoomTransport implements HistoryTransport {
  Future<void> send(String author, String token, String text);
}

abstract interface class DirectTransport implements HistoryTransport {
  Future<int> myNumber();
  Future<bool> subscriberExists(int number);
  Future<void> sendTo(int number, String token, String text);
}

abstract class SignalRHistory implements HistoryTransport {
  SignalRHistory(this.path, [this.credential]);
  final String path;
  final String? credential;
  HubConnection? _hub;

  @override
  Future<void> connect(VoidCallback onMessage, VoidCallback onClose) async {
    final hub = HubConnectionBuilder()
        .withUrl(
          '$chatServer/$path',
          options: HttpConnectionOptions(
            transport: HttpTransportType.WebSockets,
            skipNegotiation: true,
            accessTokenFactory: credential == null
                ? null
                : () async => credential!,
          ),
        )
        .build();
    _hub = hub;
    hub.on('MessagesAvailable', (_) => onMessage());
    hub.onclose(({error}) => onClose());
    await hub.start()?.timeout(const Duration(seconds: 12));
  }

  HubConnection get _connected =>
      _hub ?? (throw const FormatException('Disconnected'));

  @override
  Future<List<Message>> history(int after) async {
    final data = await _connected
        .invoke('History', args: [after])
        .timeout(const Duration(seconds: 12));
    return (data as List)
        .map((row) => Message.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> close() async {
    final previous = _hub;
    _hub = null;
    try {
      await previous?.stop();
    } on Exception {
      /* The connection is already closing. */
    }
  }
}

class SignalRRoom extends SignalRHistory implements RoomTransport {
  SignalRRoom() : super('chat');
  @override
  Future<void> send(String author, String token, String text) async {
    await _connected
        .invoke('SendMessage', args: [author, token, text])
        .timeout(const Duration(seconds: 8));
  }
}

class SignalRDirect extends SignalRHistory implements DirectTransport {
  SignalRDirect(String credential) : super('direct', credential);
  Future<Object?> _request(String method, [List<Object>? args]) => _connected
      .invoke(method, args: args)
      .timeout(const Duration(seconds: 10));
  @override
  Future<int> myNumber() async => await _request('MyNumber') as int;
  @override
  Future<bool> subscriberExists(int number) async =>
      await _request('SubscriberExists', [number]) as bool;
  @override
  Future<void> sendTo(int number, String token, String text) async {
    await _request('SendTo', [number, token, text]);
  }
}

Future<void> reportDiagnostic(String code) async {
  if (!const bool.fromEnvironment('HAWK_ENABLED')) return;
  final client = http.Client();
  try {
    await client
        .post(Uri.parse('$chatServer/diagnostics/$code'))
        .timeout(const Duration(seconds: 3));
  } on Exception {
    // Reporting must also work as a no-op when the device is offline.
  } finally {
    client.close();
  }
}
