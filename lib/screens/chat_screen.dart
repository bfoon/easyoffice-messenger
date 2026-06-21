import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/chat_socket.dart';
import '../services/sound_service.dart';
import '../services/local_db.dart';
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
  bool _uploading = false;

  // typing indicator
  final Map<String, DateTime> _typers = {};
  final Map<String, String> _typerNames = {};
  Timer? _typingClock;
  Timer? _pollTimer;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  String? _replyingToId;
  String _replyingToText = '';
  String _myId = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _typingClock = Timer.periodic(const Duration(seconds: 1), (_) => _pruneTypers());
  }

  Future<void> _bootstrap() async {
    // 1. Show cached messages instantly (no spinner if we have any).
    final cached = await LocalDb.instance.loadMessages(widget.room.id);
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() {
        _messages
          ..clear()
          ..addAll(cached);
        _loading = false;
      });
      _scrollToBottom(animated: false);
    }

    // 2. Fetch fresh from the server, replace, and update the cache.
    final history = await _api.messages(widget.room.id);
    if (!mounted) return;
    if (history.isNotEmpty) {
      setState(() {
        _messages
          ..clear()
          ..addAll(history);
        _loading = false;
      });
      await LocalDb.instance.saveMessages(widget.room.id, history);
      _scrollToBottom(animated: false);
    } else {
      setState(() => _loading = false);
    }

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

    final existingById = {for (final m in _messages) m.id: m};
    final incoming = latest.where((m) => !existingById.containsKey(m.id)).toList();

    var reactionsChanged = false;
    for (final fresh in latest) {
      final current = existingById[fresh.id];
      if (current == null) continue;
      if (!_sameReactions(current.reactions, fresh.reactions)) {
        final idx = _messages.indexWhere((m) => m.id == fresh.id);
        if (idx != -1) {
          _messages[idx] = _withReactions(_messages[idx], fresh.reactions);
          reactionsChanged = true;
        }
      }
    }

    final hasFromOthers = incoming.any((m) => !m.isMine);
    if (incoming.isNotEmpty || reactionsChanged) {
      setState(() => _messages.addAll(incoming));
      await LocalDb.instance.saveMessages(widget.room.id, _messages);
    }
    if (hasFromOthers) SoundService.instance.playReceived();
    if (incoming.isNotEmpty) _scrollToBottom();
  }

  bool _sameReactions(List<ReactionSummary> a, List<ReactionSummary> b) {
    if (a.length != b.length) return false;
    final am = {for (final r in a) r.emoji: r.count};
    final bm = {for (final r in b) r.emoji: r.count};
    if (am.length != bm.length) return false;
    for (final e in am.entries) {
      if (bm[e.key] != e.value) return false;
    }
    return true;
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
    if (type == 'chat_typing' || type == 'typing') {
      final id = '${data['sender_id'] ?? ''}';
      final name = '${data['sender_name'] ?? ''}';
      if (id.isNotEmpty && id != _myId) {
        setState(() => _typers[id] = DateTime.now());
        _typerNames[id] = name;
      }
      return;
    }
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
    if (data.containsKey('id') &&
        (data.containsKey('content') || data.containsKey('message_type'))) {
      final msg = ChatMessage.fromJson(data);
      final exists = _messages.any((m) => m.id == msg.id);
      if (!exists) {
        setState(() => _messages.add(msg));
        if (msg.sender != null) _typers.remove(msg.sender!.id);
        if (!msg.isMine) SoundService.instance.playReceived();
        LocalDb.instance.saveMessages(widget.room.id, _messages);
        _scrollToBottom();
      }
    }
  }

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

  // ── Members ───────────────────────────────────────────────────────────────

  void _showMembers() {
    final members = widget.room.members;
    if (members.isEmpty) {
      _toast('Member list not available.');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: EoColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.group_rounded, color: EoColors.deepTeal),
                  const SizedBox(width: 10),
                  Text('${members.length} members', style: EoTheme.display(16, w: FontWeight.w700)),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: members.length,
                itemBuilder: (_, i) {
                  final u = members[i];
                  return ListTile(
                    leading: EoAvatar(initials: u.initials, imageUrl: u.avatarUrl, size: 42),
                    title: Text(u.fullName),
                    subtitle: Text('@${u.username}', style: const TextStyle(color: EoColors.inkSoft)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Attachments ───────────────────────────────────────────────────────────

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: EoColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: EoColors.deepTeal),
              title: const Text('Photo from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: EoColors.deepTeal),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded, color: EoColors.deepTeal),
              title: const Text('File / document'),
              onTap: () {
                Navigator.pop(context);
                _pickFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 85);
      if (picked != null) await _upload(picked.path);
    } catch (e) {
      _toast('Could not pick image.');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      final path = result?.files.single.path;
      if (path != null) await _upload(path);
    } catch (e) {
      _toast('Could not pick file.');
    }
  }

  Future<void> _upload(String path) async {
    setState(() => _uploading = true);
    final caption = _composer.text.trim();
    final ok = await _api.uploadFile(widget.room.id, path, caption: caption);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (ok) {
      _composer.clear();
      SoundService.instance.playSent();
      _pollMessages();
    } else {
      _toast('Upload failed.');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleReaction(ChatMessage m, String emoji) async {
    final idx = _messages.indexWhere((x) => x.id == m.id);
    if (idx == -1) return;

    final current = List<ReactionSummary>.from(_messages[idx].reactions);
    final existing = current.indexWhere((r) => r.emoji == emoji);
    if (existing != -1) {
      final r = current[existing];
      if (r.mine) {
        final newCount = r.count - 1;
        if (newCount <= 0) {
          current.removeAt(existing);
        } else {
          current[existing] = ReactionSummary(emoji: emoji, count: newCount, mine: false);
        }
      } else {
        current[existing] = ReactionSummary(emoji: emoji, count: r.count + 1, mine: true);
      }
    } else {
      current.add(ReactionSummary(emoji: emoji, count: 1, mine: true));
    }
    setState(() => _messages[idx] = _withReactions(_messages[idx], current));

    final updated = await _api.toggleReaction(m.id, emoji);
    if (!mounted) return;
    final i2 = _messages.indexWhere((x) => x.id == m.id);
    if (i2 != -1 && updated.isNotEmpty) {
      setState(() => _messages[i2] = _withReactions(_messages[i2], updated));
      await LocalDb.instance.saveMessages(widget.room.id, _messages);
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
            if (m.isMine && m.messageType == 'text')
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: EoColors.deepTeal),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  _editMessage(m);
                },
              ),
            // Delete for me — available on any message.
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined, color: EoColors.inkSoft),
              title: const Text('Delete for me'),
              onTap: () async {
                Navigator.pop(context);
                final ok = await _api.hideMessage(m.id);
                if (ok && mounted) {
                  final idx = _messages.indexWhere((x) => x.id == m.id);
                  if (idx != -1) {
                    setState(() => _messages.removeAt(idx));
                    await LocalDb.instance.deleteMessage(m.id);
                  }
                } else {
                  _toast('Could not delete.');
                }
              },
            ),
            // Delete for everyone — only your own messages.
            if (m.isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: EoColors.coral),
                title: const Text('Delete for everyone', style: TextStyle(color: EoColors.coral)),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await _api.deleteMessage(m.id);
                  if (ok && mounted) {
                    final idx = _messages.indexWhere((x) => x.id == m.id);
                    if (idx != -1) {
                      setState(() => _messages.removeAt(idx));
                      await LocalDb.instance.deleteMessage(m.id);
                    }
                  } else {
                    _toast('Could not delete.');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMessage(ChatMessage m) async {
    final controller = TextEditingController(text: m.content);
    final newText = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: EoColors.surface,
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
          decoration: InputDecoration(
            fillColor: EoColors.sand,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: EoColors.inkSoft)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: EoColors.deepTeal,
              foregroundColor: EoColors.onTeal,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newText == null || newText.isEmpty || newText == m.content) return;

    // Optimistic update.
    final idx = _messages.indexWhere((x) => x.id == m.id);
    if (idx != -1) {
      setState(() => _messages[idx] = ChatMessage(
            id: m.id, roomId: m.roomId, sender: m.sender, content: newText,
            messageType: m.messageType, fileUrl: m.fileUrl, fileName: m.fileName,
            fileSize: m.fileSize, reactions: m.reactions, isDeleted: m.isDeleted,
            isEdited: true, createdAt: m.createdAt, replyTo: m.replyTo,
            poll: m.poll, isMine: m.isMine,
          ));
    }

    final ok = await _api.editMessage(m.id, newText);
    if (!mounted) return;
    if (ok) {
      await LocalDb.instance.saveMessages(widget.room.id, _messages);
      _pollMessages();
    } else {
      _toast('Could not edit message.');
      _pollMessages(); // re-sync to revert the optimistic change
    }
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
        title: GestureDetector(
          onTap: _showMembers,
          child: Row(
            children: [
              EoAvatar(initials: widget.room.initials, imageUrl: widget.room.avatarUrl, size: 40, online: _connected && widget.room.isDirect),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.room.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: EoTheme.display(17, w: FontWeight.w700)),
                    Text(
                      _connected ? (widget.room.isDirect ? 'Online' : '${widget.room.memberCount} members • tap to view') : 'Connecting…',
                      style: TextStyle(fontSize: 12, color: _connected ? EoColors.signalTeal : EoColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
          if (_uploading) const LinearProgressIndicator(color: EoColors.signalTeal, minHeight: 2),
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
              padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: EoColors.deepTeal, size: 28),
                    tooltip: 'Attach',
                    onPressed: _uploading ? null : _showAttachSheet,
                  ),
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