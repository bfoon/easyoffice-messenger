import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/eo_theme.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final String taskId;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final _api = ApiService.instance;
  TaskItem? _task;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await _api.taskDetail(widget.taskId);
    if (!mounted) return;
    setState(() {
      _task = t;
      _loading = false;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleOnSite() async {
    final t = _task!;
    setState(() => _busy = true);
    final ok = t.isOnSite
        ? await _api.taskClearOnSite(t.id)
        : await _api.taskOnSite(t.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _toast(t.isOnSite ? 'Marked as left site.' : 'Marked on site. Customer and team notified.');
      _load();
    } else {
      _toast('Could not update on-site status.');
    }
  }

  Future<void> _complete() async {
    final comment = await showDialog<String>(
      context: context,
      builder: (_) => const _CompletionDialog(),
    );
    if (comment == null) return; // cancelled
    setState(() => _busy = true);
    final err = await _api.taskComplete(_task!.id, comment);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      _toast('Task completed.');
      _load();
    } else {
      _toast(err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Task')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: EoColors.deepTeal))
          : _task == null
              ? const Center(child: Text('Task not found.', style: TextStyle(color: EoColors.inkSoft)))
              : _content(_task!),
    );
  }

  Widget _content(TaskItem t) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(t.title, style: EoTheme.display(21, w: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pill(t.priority.toUpperCase(), EoColors.deepTeal),
            _pill(_statusLabel(t), const Color(0xFF10B981)),
            if (t.categoryName.isNotEmpty) _pill(t.categoryName, EoColors.signalTeal),
            if (t.isOverdue && !t.isClosed) _pill('OVERDUE', EoColors.coral),
          ],
        ),
        const SizedBox(height: 18),
        if (t.description.isNotEmpty) ...[
          Text('Description', style: EoTheme.display(14, w: FontWeight.w700, color: EoColors.deepTeal)),
          const SizedBox(height: 6),
          Text(t.description, style: const TextStyle(fontSize: 15, height: 1.4, color: EoColors.ink)),
          const SizedBox(height: 18),
        ],
        _infoRow('Assigned by', t.assignedBy?.fullName ?? '—'),
        if (t.dueDate != null) _infoRow('Due', DateFormat('EEE d MMM, HH:mm').format(t.dueDate!.toLocal())),
        _infoRow('Progress', '${t.progressPct}%'),
        if (t.isOnSite) _infoRow('On site since', DateFormat('d MMM, HH:mm').format(t.onSiteAt!.toLocal())),
        const SizedBox(height: 24),

        if (!t.isClosed) ...[
          // On-site button
          OutlinedButton.icon(
            onPressed: _busy ? null : _toggleOnSite,
            icon: Icon(t.isOnSite ? Icons.logout_rounded : Icons.location_on_rounded),
            label: Text(t.isOnSite ? "I've left site" : "I'm on site"),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.isOnSite ? EoColors.inkSoft : const Color(0xFF10B981),
              side: BorderSide(color: t.isOnSite ? EoColors.divider : const Color(0xFF10B981)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),

          // Complete button
          if (t.awaitingCsVerification)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE8915A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, color: Color(0xFFE8915A)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Awaiting customer service verification before closing.',
                        style: TextStyle(fontSize: 13.5, color: EoColors.ink)),
                  ),
                ],
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _busy ? null : _complete,
              icon: const Icon(Icons.check_circle_rounded),
              label: Text(t.isCustomerFacing ? 'Mark done (CS will verify)' : 'Mark task complete'),
              style: ElevatedButton.styleFrom(
                backgroundColor: EoColors.deepTeal,
                foregroundColor: EoColors.onTeal,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
        ] else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: EoColors.sand,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
                const SizedBox(width: 10),
                Text(t.status == 'cancelled' ? 'This task was cancelled.' : 'This task is complete.',
                    style: const TextStyle(fontSize: 14, color: EoColors.ink)),
              ],
            ),
          ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator(color: EoColors.deepTeal)),
        ],
      ],
    );
  }

  String _statusLabel(TaskItem t) {
    return switch (t.status) {
      'todo' => 'To do',
      'in_progress' => 'In progress',
      'review' => t.awaitingCsVerification ? 'Awaiting verify' : 'Review',
      'on_hold' => 'On hold',
      'done' => 'Done',
      'cancelled' => 'Cancelled',
      _ => t.status,
    };
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(label, style: const TextStyle(color: EoColors.inkSoft, fontSize: 14))),
            Expanded(child: Text(value, style: const TextStyle(color: EoColors.ink, fontSize: 14, fontWeight: FontWeight.w500))),
          ],
        ),
      );
}

class _CompletionDialog extends StatefulWidget {
  const _CompletionDialog();

  @override
  State<_CompletionDialog> createState() => _CompletionDialogState();
}

class _CompletionDialogState extends State<_CompletionDialog> {
  final _controller = TextEditingController();
  bool _valid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: EoColors.surface,
      title: const Text('Complete task'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What did you do? This is required.',
              style: TextStyle(fontSize: 13.5, color: EoColors.inkSoft)),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            onChanged: (v) => setState(() => _valid = v.trim().isNotEmpty),
            decoration: InputDecoration(
              hintText: 'Completion note…',
              fillColor: EoColors.sand,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: EoColors.inkSoft)),
        ),
        ElevatedButton(
          onPressed: _valid ? () => Navigator.pop(context, _controller.text.trim()) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: EoColors.deepTeal,
            foregroundColor: EoColors.onTeal,
          ),
          child: const Text('Complete'),
        ),
      ],
    );
  }
}