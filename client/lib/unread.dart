import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'room_transport.dart';

final unreadProvider = Provider((ref) => UnreadLedger());

class UnreadLedger extends ChangeNotifier {
  int? _owner;
  int _cursor = 0;
  int? _visiblePeer;
  bool _synced = false;
  final _counts = <int, int>{};

  int countFor(int peer) => _counts[peer] ?? 0;
  int get total => _counts.values.fold(0, (sum, count) => sum + count);

  UnreadLedger();

  factory UnreadLedger.decode(String? value) {
    final ledger = UnreadLedger();
    if (value == null) return ledger;
    final data = jsonDecode(value) as Map<String, dynamic>;
    ledger._owner = data['owner'] as int?;
    ledger._cursor = data['cursor'] as int;
    for (final entry in (data['counts'] as Map<String, dynamic>).entries) {
      ledger._counts[int.parse(entry.key)] = entry.value as int;
    }
    return ledger;
  }

  String encode() => jsonEncode({
    'owner': _owner,
    'cursor': _cursor,
    'counts': {for (final e in _counts.entries) e.key.toString(): e.value},
  });

  // Receive a complete, ordered history after the last page of each sync.
  void receive(List<Message> history, int owner, Set<int> contacts) {
    _synced = true;
    final last = history.isEmpty ? 0 : history.last.id;
    if (_owner != owner) {
      // Existing conversations predate read tracking on the first launch.
      _owner = owner;
      _cursor = last;
      _counts.clear();
      notifyListeners();
      return;
    }
    final previousCount = _counts.length;
    _counts.removeWhere(
      (peer, _) => peer == _visiblePeer || !contacts.contains(peer),
    );
    if (last <= _cursor) {
      if (_counts.length != previousCount) notifyListeners();
      return;
    }
    for (final message in history.reversed) {
      if (message.id <= _cursor) break;
      if (message.recipient == owner &&
          message.sender != _visiblePeer &&
          contacts.contains(message.sender)) {
        _counts[message.sender] = countFor(message.sender) + 1;
      }
    }
    _cursor = last;
    notifyListeners();
  }

  void showConversation(int? peer) {
    _visiblePeer = peer;
    if (_synced && _counts.remove(peer) != null) notifyListeners();
  }

  void hideConversation(int peer) {
    if (_visiblePeer == peer) _visiblePeer = null;
  }
}

const _badgeChannel = MethodChannel('kitchentable/unread');

Future<UnreadLedger> loadAndroidUnread() async {
  final saved = await _badgeChannel.invokeMethod<String>('load');
  final ledger = UnreadLedger.decode(saved);
  ledger.addListener(() {
    unawaited(
      _badgeChannel
          .invokeMethod<void>('save', {
            'snapshot': ledger.encode(),
            'count': ledger.total,
          })
          .catchError((Object error, StackTrace stack) {
            FlutterError.reportError(
              FlutterErrorDetails(exception: error, stack: stack),
            );
          }),
    );
  });
  return ledger;
}
