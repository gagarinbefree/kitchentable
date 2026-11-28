import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:signalr_netcore/signalr_client.dart';

const chatServer = String.fromEnvironment(
  'CHAT_SERVER',
  defaultValue: 'http://192.168.31.84:8787',
);

class Message {
  const Message(
    this.id,
    this.sender,
    this.text,
    this.time, {
    required this.recipient,
  });
  factory Message.fromJson(Map<String, dynamic> json) => Message(
    json['id'] as int,
    json['sender'] as int,
    json['body'] as String,
    DateTime.parse(json['sentAt'] as String).toLocal(),
    recipient: json['recipient'] as int,
  );
  final int recipient;
  final int id;
  final int sender;
  final String text;
  final DateTime time;
}

abstract interface class DirectTransport {
  Future<void> connect(VoidCallback onMessage, VoidCallback onClose);
  Future<List<Message>> history(int after);
  Future<void> close();
  Future<int> myNumber();
  Future<List<int>> contacts();
  Future<String> createInvite();
  Future<int> previewInvite(String token);
  Future<int> acceptInvite(String token);
  Future<void> sendTo(int number, String token, String text);
}

class SignalRDirect implements DirectTransport {
  SignalRDirect(this.credential);
  final String credential;
  HubConnection? _hub;

  @override
  Future<void> connect(VoidCallback onMessage, VoidCallback onClose) async {
    final hub = HubConnectionBuilder()
        .withUrl(
          '$chatServer/direct',
          options: HttpConnectionOptions(
            transport: HttpTransportType.WebSockets,
            skipNegotiation: true,
            accessTokenFactory: () async => credential,
          ),
        )
        .build();
    _hub = hub;
    hub.on('MessagesAvailable', (_) => onMessage());
    hub.on('ContactsChanged', (_) => onMessage());
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

  Future<Object?> _request(String method, [List<Object>? args]) => _connected
      .invoke(method, args: args)
      .timeout(const Duration(seconds: 10));
  @override
  Future<int> myNumber() async => await _request('MyNumber') as int;
  @override
  Future<List<int>> contacts() async =>
      (await _request('Contacts') as List).cast<int>();
  @override
  Future<String> createInvite() async =>
      await _request('CreateInvite') as String;
  @override
  Future<int> previewInvite(String token) async =>
      await _request('PreviewInvite', [token]) as int;
  @override
  Future<int> acceptInvite(String token) async =>
      await _request('AcceptInvite', [token]) as int;
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
