import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../config.dart';

/// Live connection to a single room's ChatConsumer.
///
/// Outbound (what we send), per consumers.py `receive()`:
///   {"type": "chat_message", "message": "...", "reply_to": "<uuid>"?}
///   {"type": "typing"}
///
/// Inbound (what the consumer broadcasts):
///   chat.message  -> {... serialized message ...}
///   chat.typing   -> {"type":"chat_typing", "sender_id", "sender_name", ...}
///   chat.reaction -> {"type":"reaction", ...}
///   chat.edit / chat.poll / chat.pin -> typed payloads
class ChatSocket {
  ChatSocket({required this.roomId, required this.accessToken});

  final String roomId;
  final String accessToken;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _backoffSeconds = 1;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  final _connState = StreamController<bool>.broadcast();
  Stream<bool> get connectionState => _connState.stream;

  void connect() {
    if (_disposed) return;
    final uri = AppConfig.wsRoom(roomId, accessToken);
    try {
      _channel = WebSocketChannel.connect(uri);
      _connState.add(true);
      _backoffSeconds = 1;
      _sub = _channel!.stream.listen(
        _onData,
        onError: (e) {
          if (kDebugMode) debugPrint('ws error: $e');
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('ws connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _onData(dynamic raw) {
    try {
      final data = jsonDecode(raw as String);
      if (data is Map<String, dynamic>) _events.add(data);
    } catch (_) {/* ignore malformed frames */}
  }

  void _scheduleReconnect() {
    _connState.add(false);
    _sub?.cancel();
    _channel = null;
    if (_disposed) return;
    _reconnectTimer?.cancel();
    final wait = _backoffSeconds;
    _reconnectTimer = Timer(Duration(seconds: wait), connect);
    _backoffSeconds = (_backoffSeconds * 2).clamp(1, 30);
  }

  void _send(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(payload));
    } catch (e) {
      if (kDebugMode) debugPrint('ws send failed: $e');
    }
  }

  // ── Outbound API ────────────────────────────────────────────────────────

  void sendMessage(String text, {String? replyToId}) {
    _send({
      'type': 'chat_message',
      'message': text,
      if (replyToId != null) 'reply_to': replyToId,
    });
  }

  void sendTyping() => _send({'type': 'typing'});

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _events.close();
    _connState.close();
  }
}
