// lib/screens/files_screen.dart
//
// Browse files the user can access. Tap a file to open it (url_launcher).
// Images and PDFs open in the device viewer; everything else downloads.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/files_models.dart';
import '../services/api_service.dart';
import '../theme/eo_theme.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final _api = ApiService.instance;
  final _searchCtl = TextEditingController();

  List<RemoteFile> _files = [];
  bool _loading = true;
  String _category = ''; // '', document, image, spreadsheet, presentation, pdf

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final files = await _api.files(q: _searchCtl.text.trim(), category: _category);
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  Future<void> _open(RemoteFile f) async {
    if (f.url.isEmpty) {
      _toast('File not available.');
      return;
    }
    final uri = Uri.parse(f.url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _toast('Could not open file.');
    } catch (_) {
      _toast('Could not open file.');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Files')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchCtl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search files',
                prefixIcon: const Icon(Icons.search),
                fillColor: EoColors.sand,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('All', ''),
                _chip('PDF', 'pdf'),
                _chip('Docs', 'document'),
                _chip('Images', 'image'),
                _chip('Sheets', 'spreadsheet'),
                _chip('Slides', 'presentation'),
              ],
            ),
          ),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    final selected = _category == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _category = value);
          _load();
        },
        selectedColor: EoColors.deepTeal,
        labelStyle: TextStyle(color: selected ? EoColors.onTeal : EoColors.ink),
      ),
    );
  }

  Widget _list() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: EoColors.deepTeal));
    }
    if (_files.isEmpty) {
      return const Center(
        child: Text('No files found.', style: TextStyle(color: EoColors.inkSoft)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _files.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final f = _files[i];
          return ListTile(
            leading: _fileIcon(f),
            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                if (f.sizeDisplay.isNotEmpty) f.sizeDisplay,
                if (f.folderName.isNotEmpty) f.folderName,
                if (f.uploadedBy.isNotEmpty) f.uploadedBy,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: EoColors.inkSoft, fontSize: 12.5),
            ),
            trailing: const Icon(Icons.open_in_new, size: 18, color: EoColors.inkSoft),
            onTap: () => _open(f),
          );
        },
      ),
    );
  }

  Widget _fileIcon(RemoteFile f) {
    IconData icon;
    Color color;
    if (f.isPdf) {
      icon = Icons.picture_as_pdf;
      color = const Color(0xFFef4444);
    } else if (f.isImage) {
      icon = Icons.image;
      color = const Color(0xFF7c3aed);
    } else if (f.typeCategory == 'spreadsheet') {
      icon = Icons.table_chart;
      color = const Color(0xFF16a34a);
    } else if (f.typeCategory == 'presentation') {
      icon = Icons.slideshow;
      color = const Color(0xFFea580c);
    } else if (f.typeCategory == 'document') {
      icon = Icons.description;
      color = const Color(0xFF2563eb);
    } else {
      icon = Icons.insert_drive_file;
      color = EoColors.inkSoft;
    }
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(icon, color: color),
    );
  }
}
