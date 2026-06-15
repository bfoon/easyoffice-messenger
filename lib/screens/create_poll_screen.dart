import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/eo_theme.dart';

class CreatePollScreen extends StatefulWidget {
  const CreatePollScreen({super.key, required this.roomId});
  final String roomId;

  @override
  State<CreatePollScreen> createState() => _CreatePollScreenState();
}

class _CreatePollScreenState extends State<CreatePollScreen> {
  final _api = ApiService.instance;
  final _question = TextEditingController();
  final List<TextEditingController> _options = [TextEditingController(), TextEditingController()];
  bool _allowMultiple = false;
  bool _anonymous = false;
  bool _busy = false;

  void _addOption() {
    if (_options.length >= 8) return;
    setState(() => _options.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_options.length <= 2) return;
    setState(() {
      _options[i].dispose();
      _options.removeAt(i);
    });
  }

  Future<void> _submit() async {
    final q = _question.text.trim();
    final opts = _options.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (q.isEmpty || opts.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a question and at least two options.')),
      );
      return;
    }
    setState(() => _busy = true);
    final ok = await _api.createPoll(widget.roomId, q, opts, allowMultiple: _allowMultiple, anonymous: _anonymous);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create the poll.')));
    }
  }

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New poll')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _question,
            decoration: const InputDecoration(labelText: 'Question'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          Text('Options', style: EoTheme.display(14, w: FontWeight.w700, color: EoColors.inkSoft)),
          const SizedBox(height: 10),
          ..._options.asMap().entries.map((e) {
            final i = e.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: e.value,
                      decoration: InputDecoration(hintText: 'Option ${i + 1}'),
                    ),
                  ),
                  if (_options.length > 2)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: EoColors.coral),
                      onPressed: () => _removeOption(i),
                    ),
                ],
              ),
            );
          }),
          if (_options.length < 8)
            TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add),
              label: const Text('Add option'),
              style: TextButton.styleFrom(foregroundColor: EoColors.deepTeal),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _allowMultiple,
            activeThumbColor: EoColors.signalTeal,
            title: const Text('Allow multiple choices'),
            onChanged: (v) => setState(() => _allowMultiple = v),
          ),
          SwitchListTile(
            value: _anonymous,
            activeThumbColor: EoColors.signalTeal,
            title: const Text('Anonymous voting'),
            onChanged: (v) => setState(() => _anonymous = v),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: EoColors.onTeal))
                : const Text('Create poll'),
          ),
        ],
      ),
    );
  }
}
