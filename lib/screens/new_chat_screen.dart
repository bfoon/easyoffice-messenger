import 'dart:async';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/eo_theme.dart';
import '../widgets/eo_avatar.dart';
import 'chat_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _api = ApiService.instance;
  final _search = TextEditingController();
  Timer? _debounce;
  List<UserMini> _results = [];
  bool _loading = false;

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q.trim()));
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    final users = await _api.searchUsers(q);
    if (!mounted) return;
    setState(() {
      _results = users;
      _loading = false;
    });
  }

  Future<void> _open(UserMini user) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: EoColors.deepTeal)),
    );
    final room = await _api.directRoom(user.id);
    if (!mounted) return;
    Navigator.pop(context); // dismiss spinner
    if (room != null) {
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
      );
      if (mounted) Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that conversation.')),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New conversation')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: 'Search staff by name',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(color: EoColors.signalTeal, minHeight: 2),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _search.text.trim().length < 2 ? 'Type at least 2 letters to search.' : 'No matches.',
                      style: const TextStyle(color: EoColors.inkSoft),
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                    itemBuilder: (_, i) {
                      final u = _results[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: EoAvatar(initials: u.initials, imageUrl: u.avatarUrl, size: 46),
                        title: Text(u.fullName, style: EoTheme.display(15.5, w: FontWeight.w600)),
                        subtitle: Text('@${u.username}', style: const TextStyle(color: EoColors.inkSoft)),
                        onTap: () => _open(u),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
