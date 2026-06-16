import 'dart:async';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/chat_socket.dart';
import '../services/sound_service.dart';
import '../theme/eo_theme.dart';
import '../widgets/eo_avatar.dart';
import '../widgets/message_bubble.dart';
import 'create_poll_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.room});
  final ChatRoom room;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api = ApiService.instance;
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  ChatSocket? _socket;
  final List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _connected = false;

  // typing indicator
  final Map<String, DateTime> _typers = {};
  final Map<String, String> _typerNames = {};
  Timer? _typingClock;
  Timer? _pollTimer;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  String? _replyingToId;
  String _replyingToText = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _typingClock = Timer.periodic(const Duration(seconds: 1), (_) => _pruneTypers());
  }

  Future<void> _bootstrap() async {
    final history = await _api.messages(widget.room.id);
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(history);
      _loading = false;
    });
    _scrollToBottom(animated: false);
    _openSocket();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollMessages());
  }

  Future<void> _pollMessages() async {
    if (!mounted) return;
    final latest = await _api.messages(widget.room.id);
    if (!mounted || latest.isEmpty) return;
    final existingIds = _messages.map((m) => m.id).toSet();
    final incoming = latest.where((m) => !existingIds.contains(m.id)).toList();
    if (incoming.isEmpty) return;
    final hasFromOthers = incoming.any((m) => !m.isMine);
    setState(() => _messages.addAll(incoming));
    if (hasFromOthers) SoundService.instance.playReceived();
    _scrollToBottom();
  }

  void _openSocket() {
    final token = _api.accessToken;
    if (token == null) return;
    final s = ChatSocket(roomId: widget.room.id, accessToken: token);
    s.connectionState.listen((c) {
      if (mounted) setState(() => _connected = c);
    });
    s.events.listen(_onSocketEvent);
    s.connect();
    _socket = s;
  }

  void _onSocketEvent(Map<String, dynamic> data) {
    final type = data['type'] ?? '';
    // Typing indicator from the consumer (chat_typing).
    if (type == 'chat_typing' || type == 'typing') {
      final id = '${data['sender_id'] ?? ''}';
      final name = '${data['sender_name'] ?? ''}';
      // Ignore our own typing echo.
      if (id.isNotEmpty && id != (_api.accessToken != null ? _myId : '')) {
        setState(() => _typers[id] = DateTime.now());
        _typerNames[id] = name;
      }
      return;
    }
    // Reaction update.
    if (type == 'reaction') {
      final mid = '${data['message_id'] ?? ''}';
      final list = (data['reactions_summary'] ?? data['reactions'] ?? []) as List;
      final idx = _messages.indexWhere((m) => m.id == mid);
      if (idx != -1) {
        final updated = list.map((e) => ReactionSummary.fromJson(e)).toList();
        setState(() => _messages[idx] = _withReactions(_messages[idx], updated));
      }
      return;
    }
    // Otherwise treat as a serialized chat message (the default broadcast).
    if (data.containsKey('id') &&
        (data.containsKey('content') || data.containsKey('message_type'))) {
      final msg = ChatMessage.fromJson(data);
      final exists = _messages.any((m) => m.id == msg.id);
      if (!exists) {
        setState(() => _messages.add(msg));
        if (msg.sender != null) _typers.remove(msg.sender!.id);
        if (!msg.isMine) SoundService.instance.playReceived();
        _scrollToBottom();
      }
    }
  }

  // Best-effort own id for typing-echo suppression (filled from first own msg).
  String _myId = '';

  ChatMessage _withReactions(ChatMessage m, List<ReactionSummary> r) => ChatMessage(
        id: m.id, roomId: m.roomId, sender: m.sender, content: m.content,
        messageType: m.messageType, fileUrl: m.fileUrl, fileName: m.fileName,
        fileSize: m.fileSize, reactions: r, isDeleted: m.isDeleted, isEdited: m.isEdited,
        createdAt: m.createdAt, replyTo: m.replyTo, poll: m.poll, isMine: m.isMine,
      );

  void _pruneTypers() {
    final now = DateTime.now();
    final stale = _typers.entries.where((e) => now.difference(e.value).inSeconds > 4).map((e) => e.key).toList();
    if (stale.isNotEmpty) {
      setState(() {
        for (final k in stale) {
          _typers.remove(k);
        }
      });
    }
  }

  void _onComposerChanged(String _) {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inMilliseconds > 2500) {
      _socket?.sendTyping();
      _lastTypingSent = now;
    }
  }

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _socket?.sendMessage(text, replyToId: _replyingToId);
    SoundService.instance.playSent();
    _composer.clear();
    setState(() {
      _replyingToId = null;
      _replyingToText = '';
    });
    Future.delayed(const Duration(milliseconds: 600), _pollMessages);
  }

  Future<void> _toggleReaction(ChatMessage m, String emoji) async {
    final updated = await _api.toggleReaction(m.id, emoji);
    final idx = _messages.indexWhere((x) => x.id == m.id);
    if (idx != -1 && mounted) {
      setState(() => _messages[idx] = _withReactions(_messages[idx], updated));
    }
  }

  Future<void> _votePoll(ChatMessage m, List<String> optionIds) async {
    final poll = await _api.votePoll(m.poll!.id, optionIds);
    if (poll != null && mounted) {
      final idx = _messages.indexWhere((x) => x.id == m.id);
      if (idx != -1) {
        final old = _messages[idx];
        setState(() => _messages[idx] = ChatMessage(
              id: old.id, roomId: old.roomId, sender: old.sender, content: old.content,
              messageType: old.messageType, fileUrl: old.fileUrl, fileName: old.fileName,
              fileSize: old.fileSize, reactions: old.reactions, isDeleted: old.isDeleted,
              isEdited: old.isEdited, createdAt: old.createdAt, replyTo: old.replyTo,
              poll: poll, isMine: old.isMine,
            ));
      }
    }
  }

  void _showMessageActions(ChatMessage m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: EoColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 14,
                children: ['👍', '❤️', '😂', '🎉', '🙏', '🔥'].map((e) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _toggleReaction(m, e);
                    },
                    child: Text(e, style: const TextStyle(fontSize: 30)),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _replyingToId = m.id;
                  _replyingToText = m.content.isEmpty ? 'Attachment' : m.content;
                });
              },
            ),
            if (m.isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: EoColors.coral),
                title: const Text('Delete', style: TextStyle(color: EoColors.coral)),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await _api.deleteMessage(m.id);
                  if (ok && mounted) {
                    final idx = _messages.indexWhere((x) => x.id == m.id);
                    if (idx != -1) setState(() => _messages.removeAt(idx));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _typingClock?.cancel();
    _socket?.dispose();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            EoAvatar(initials: widget.room.initials, imageUrl: widget.room.avatarUrl, size: 40, online: _connected && widget.room.isDirect),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.room.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: EoTheme.display(17, w: FontWeight.w700)),
                  Text(
                    _connected ? (widget.room.isDirect ? 'Online' : '${widget.room.memberCount} members') : 'Connecting…',
                    style: TextStyle(fontSize: 12, color: _connected ? EoColors.signalTeal : EoColors.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!widget.room.isReadonly)
            IconButton(
              icon: const Icon(Icons.bar_chart_rounded),
              tooltip: 'New poll',
              onPressed: () async {
                final created = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => CreatePollScreen(roomId: widget.room.id)),
                );
                if (created == true) _bootstrap();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _messageList()),
          _typingBar(),
          _composerBar(),
        ],
      ),
    );
  }

  Widget _messageList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: EoColors.deepTeal));
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text('Say hello 👋', style: TextStyle(color: EoColors.inkSoft, fontSize: 16)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        final prev = i > 0 ? _messages[i - 1] : null;
        final showSender = prev == null || prev.sender?.id != m.sender?.id;
        return MessageBubble(
          message: m,
          showSender: showSender,
          onReact: (e) => _toggleReaction(m, e),
          onVote: (ids) => _votePoll(m, ids),
          onLongPress: () => _showMessageActions(m),
        );
      },
    );
  }

  Widget _typingBar() {
    if (_typers.isEmpty) return const SizedBox.shrink();
    final names = _typers.keys.map((id) => _typerNames[id] ?? 'Someone').toList();
    final label = names.length == 1 ? '${names.first} is typing…' : '${names.length} people are typing…';
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
      child: Text(label, style: const TextStyle(color: EoColors.signalTeal, fontSize: 12.5, fontStyle: FontStyle.italic)),
    );
  }

  Widget _composerBar() {
    if (widget.room.isReadonly) {
      return Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        color: EoColors.sandDeep,
        child: const Text('This channel is read-only.', textAlign: TextAlign.center, style: TextStyle(color: EoColors.inkSoft)),
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: EoColors.surface,
          boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingToId != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded, size: 18, color: EoColors.deepTeal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Replying: $_replyingToText',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: EoColors.inkSoft, fontSize: 13)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _replyingToId = null;
                        _replyingToText = '';
                      }),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      onChanged: _onComposerChanged,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Message',
                        fillColor: EoColors.sand,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: EoColors.signalTeal, width: 1.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      height: 48, width: 48,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [EoColors.deepTeal, EoColors.signalTeal]),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: EoColors.onTeal, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}