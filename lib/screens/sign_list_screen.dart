// lib/screens/sign_list_screen.dart
//
// Lists signature requests where the current user is a signer.
// Tap one to open the signing screen.

import 'package:flutter/material.dart';

import '../models/files_models.dart';
import '../services/api_service.dart';
import '../theme/eo_theme.dart';
import 'sign_detail_screen.dart';

class SignListScreen extends StatefulWidget {
  const SignListScreen({super.key});

  @override
  State<SignListScreen> createState() => _SignListScreenState();
}

class _SignListScreenState extends State<SignListScreen> {
  final _api = ApiService.instance;
  List<SignRequest> _requests = [];
  bool _loading = true;
  bool _openOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final reqs = await _api.signRequests(openOnly: _openOnly);
    if (!mounted) return;
    setState(() {
      _requests = reqs;
      _loading = false;
    });
  }

  Future<void> _openRequest(SignRequest r) async {
    final signed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SignDetailScreen(requestId: r.requestId)),
    );
    if (signed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('To Sign'),
        actions: [
          PopupMenuButton<bool>(
            initialValue: _openOnly,
            onSelected: (v) {
              setState(() => _openOnly = v);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: true, child: Text('Pending only')),
              PopupMenuItem(value: false, child: Text('All requests')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: EoColors.deepTeal))
          : _requests.isEmpty
              ? Center(
                  child: Text(
                    _openOnly ? 'Nothing to sign right now.' : 'No signature requests.',
                    style: const TextStyle(color: EoColors.inkSoft),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _requests.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = _requests[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFef4444).withValues(alpha: 0.12),
                          child: const Icon(Icons.draw, color: Color(0xFFef4444)),
                        ),
                        title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            if (r.documentName.isNotEmpty) r.documentName,
                            'from ${r.createdBy}',
                            _statusLabel(r),
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: EoColors.inkSoft, fontSize: 12.5),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: EoColors.inkSoft),
                        onTap: () => _openRequest(r),
                      );
                    },
                  ),
                ),
    );
  }

  String _statusLabel(SignRequest r) {
    switch (r.signerStatus) {
      case 'signed':
        return 'Signed';
      case 'declined':
        return 'Declined';
      case 'viewed':
        return 'Viewed';
      default:
        return 'Pending';
    }
  }
}
