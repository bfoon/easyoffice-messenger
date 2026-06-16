import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../theme/eo_theme.dart';
import '../widgets/eo_avatar.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final _api = ApiService.instance;
  List<ChatRoom> _rooms = [];
  bool _loading = true;
  String _query = '';
  int _tab = 0; // 0 All, 1 Direct, 2 Groups
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Live-refresh unread counts while the list is open.
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _silentRefresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rooms = await _api.rooms();
    if (!mounted) return;
    setState(() {
      _rooms = rooms;
      _loading = false;
    });
  }

  Future<void> _silentRefresh() async {
    final rooms = await _api.rooms();
    if (!mounted) return;
    setState(() => _rooms = rooms);
  }

  int get _totalUnread => _rooms.fold(0, (sum, r) => sum + r.unread);

  List<ChatRoom> get _filtered {
    var list = _rooms;
    // Tab filter.
    if (_tab == 1) {
      list = list.where((r) => r.isDirect).toList();
    } else if (_tab == 2) {
      list = list.where((r) => !r.isDirect).toList();
    }
    // Search filter.
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((r) => r.title.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Messages'),
            if (_totalUnread > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: EoColors.coral,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$_totalUnread',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: EoAvatar(initials: me?.initials ?? '?', imageUrl: me?.avatarUrl ?? '', size: 36),
            onSelected: (v) {
              if (v == 'logout') context.read<AppState>().logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(me?.fullName ?? '', style: EoTheme.display(14, w: FontWeight.w600)),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: EoColors.deepTeal,
        foregroundColor: EoColors.onTeal,
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const NewChatScreen()),
          );
          if (created == true) _load();
        },
        child: const Icon(Icons.edit_rounded),
      ),
      body: RefreshIndicator(
        color: EoColors.deepTeal,
        onRefresh: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search conversations',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            _filterTabs(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _filterTabs() {
    const labels = ['All', 'Direct', 'Groups'];
    return Container(
      height: 42,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final selected = _tab == i;
          return GestureDetector(
            onTap: () => setState(() => _tab = i),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: selected ? EoColors.deepTeal : EoColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? EoColors.deepTeal : EoColors.divider),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  color: selected ? EoColors.onTeal : EoColors.inkSoft,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: EoColors.deepTeal));
    }
    final rooms = _filtered;
    if (rooms.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.forum_outlined, size: 64, color: EoColors.sandDeep),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _query.isEmpty ? 'No conversations here yet.' : 'Nothing matches “$_query”.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: EoColors.inkSoft, fontSize: 15),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      itemCount: rooms.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 84),
      itemBuilder: (_, i) => _roomTile(rooms[i]),
    );
  }

  Widget _roomTile(ChatRoom room) {
    final preview = room.lastMessage?.preview ?? 'No messages yet';
    final when = room.updatedAt != null ? _relative(room.updatedAt!) : '';
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
        );
        _load();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            EoAvatar(initials: room.initials, imageUrl: room.avatarUrl, size: 52),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(room.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: EoTheme.display(16, w: room.unread > 0 ? FontWeight.w700 : FontWeight.w600)),
                      ),
                      Text(when, style: const TextStyle(color: EoColors.inkSoft, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(preview,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: room.unread > 0 ? EoColors.ink : EoColors.inkSoft,
                              fontSize: 14,
                              fontWeight: room.unread > 0 ? FontWeight.w500 : FontWeight.w400,
                            )),
                      ),
                      if (room.unread > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: EoColors.coral,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('${room.unread}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _relative(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    final diff = now.difference(local);
    if (diff.inDays == 0 && now.day == local.day) return DateFormat('HH:mm').format(local);
    if (diff.inDays < 7) return DateFormat('EEE').format(local);
    return DateFormat('dd/MM').format(local);
  }
}