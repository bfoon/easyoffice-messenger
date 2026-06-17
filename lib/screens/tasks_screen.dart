import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/eo_theme.dart';
import 'task_detail_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _api = ApiService.instance;
  int _tab = 0; // 0 Open, 1 Recently closed
  List<TaskItem> _open = [];
  List<TaskItem> _closed = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final open = await _api.myTasks();
    final closed = await _api.myRecentClosedTasks();
    if (!mounted) return;
    setState(() {
      _open = open;
      _closed = closed;
      _loading = false;
    });
  }

  List<TaskItem> get _current => _tab == 0 ? _open : _closed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Tasks')),
      body: RefreshIndicator(
        color: EoColors.deepTeal,
        onRefresh: _load,
        child: Column(
          children: [
            _tabs(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    final labels = ['Open (${_open.length})', 'Recently closed'];
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = _tab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: Container(
                margin: EdgeInsets.only(right: i == 0 ? 8 : 0),
                alignment: Alignment.center,
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
            ),
          );
        }),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: EoColors.deepTeal));
    }
    final tasks = _current;
    if (tasks.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Icon(_tab == 0 ? Icons.task_alt_rounded : Icons.history_rounded,
              size: 64, color: EoColors.sandDeep),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _tab == 0 ? 'No open tasks. Nice work!' : 'Nothing closed recently.',
              style: const TextStyle(color: EoColors.inkSoft, fontSize: 15),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (_, i) => _taskTile(tasks[i]),
    );
  }

  Widget _taskTile(TaskItem t) {
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: t.id)),
        );
        _load();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _priorityDot(t.priority),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: EoTheme.display(15.5,
                          w: FontWeight.w600,
                          color: t.isClosed ? EoColors.inkSoft : EoColors.ink)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _statusChip(t),
                      if (t.dueDate != null && !t.isClosed) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.schedule_rounded,
                            size: 13, color: t.isOverdue ? EoColors.coral : EoColors.inkSoft),
                        const SizedBox(width: 3),
                        Text(_relative(t.dueDate!),
                            style: TextStyle(
                                fontSize: 12,
                                color: t.isOverdue ? EoColors.coral : EoColors.inkSoft,
                                fontWeight: t.isOverdue ? FontWeight.w700 : FontWeight.w400)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (t.isOnSite && !t.isClosed)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.location_on_rounded, size: 18, color: Color(0xFF10B981)),
              ),
            const Icon(Icons.chevron_right_rounded, color: EoColors.inkSoft),
          ],
        ),
      ),
    );
  }

  Widget _priorityDot(String priority) {
    final color = switch (priority) {
      'critical' => EoColors.coral,
      'urgent' => EoColors.coral,
      'high' => const Color(0xFFE8915A),
      'medium' => EoColors.signalTeal,
      _ => EoColors.inkSoft,
    };
    return Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }

  Widget _statusChip(TaskItem t) {
    final (label, color) = switch (t.status) {
      'todo' => ('To do', EoColors.inkSoft),
      'in_progress' => ('In progress', EoColors.signalTeal),
      'review' => (t.awaitingCsVerification ? 'Awaiting verify' : 'Review', const Color(0xFFE8915A)),
      'on_hold' => ('On hold', EoColors.inkSoft),
      'done' => ('Done', const Color(0xFF10B981)),
      'cancelled' => ('Cancelled', EoColors.inkSoft),
      _ => (t.status, EoColors.inkSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
    );
  }

  static String _relative(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = local.difference(now);
    if (diff.inDays.abs() < 1 && local.day == now.day) return DateFormat('HH:mm').format(local);
    if (diff.inDays < 0) return '${diff.inDays.abs()}d ago';
    return DateFormat('d MMM').format(local);
  }
}