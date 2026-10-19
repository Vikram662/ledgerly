import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/tasks_repository.dart';

IconData taskTypeIcon(TaskType type) => switch (type) {
      TaskType.siteVisit => Icons.location_on_outlined,
      TaskType.clientMeeting => Icons.handshake_outlined,
      TaskType.materialProcurement => Icons.local_shipping_outlined,
      TaskType.workerPayment => Icons.payments_outlined,
      TaskType.engineerReview => Icons.engineering_outlined,
      TaskType.other => Icons.task_alt_outlined,
    };

BadgeTone taskTypeTone(TaskType type) => switch (type) {
      TaskType.siteVisit || TaskType.engineerReview => BadgeTone.info,
      TaskType.clientMeeting => BadgeTone.warning,
      TaskType.workerPayment => BadgeTone.success,
      TaskType.materialProcurement || TaskType.other => BadgeTone.neutral,
    };

enum _Filter { upcoming, completed, all }

/// PRD C8: site tasks, visits and reminders, grouped by day.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  _Filter _filter = _Filter.upcoming;

  Future<void> _confirmDelete(String id) async {
    final ok = await confirmDialog(
      context,
      title: tr('Delete task?'),
      message: tr('This will cancel all scheduled reminder alarms.'),
      confirmLabel: tr('Delete'),
      destructive: true,
    );
    if (ok) await ref.read(tasksRepositoryProvider).deleteTask(id);
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);
    final isTab = Routes.isTab(Routes.tasks);
    final calendar = AppIconButton(
      icon: Icons.calendar_month_outlined,
      tooltip: tr('Calendar'),
      onPressed: () => context.push(Routes.calendar),
    );

    return Scaffold(
      appBar: isTab
          ? tabAppBar(tr('Tasks & reminders'), actions: [calendar])
          : AppBar(
              title: Text(tr('Tasks & reminders')),
              actions: [calendar, const SizedBox(width: 8)],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.addTask),
        icon: const Icon(Icons.add_alarm),
        label: Text(tr('New task')),
      ),
      body: tasksAsync.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => Center(
          child: Text(tr('Error loading tasks: {e}', {'e': errorText(e)})),
        ),
        data: (list) {
          final upcoming = list.where((t) => !t.task.isCompleted).toList();
          final filtered = switch (_filter) {
            _Filter.upcoming => upcoming,
            _Filter.completed => list.where((t) => t.task.isCompleted).toList(),
            _Filter.all => list,
          };
          final groups = _group(filtered);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              SegmentedTabs<_Filter>(
                value: _filter,
                options: {
                  _Filter.upcoming:
                      tr('Upcoming · {count}', {'count': upcoming.length}),
                  _Filter.completed: tr('Completed'),
                  _Filter.all: tr('All'),
                },
                onChanged: (f) => setState(() => _filter = f),
              ),
              if (filtered.isEmpty)
                EmptyState(
                  icon: Icons.notifications_none_outlined,
                  title: _filter == _Filter.completed
                      ? tr('No completed tasks')
                      : tr('No tasks scheduled'),
                  message: tr(
                      'Schedule client meetings, site visits, or material follow-ups.'),
                  actionLabel: tr('New task'),
                  onAction: () => context.push(Routes.addTask),
                )
              else
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                    child: Text(
                      group.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: group.overdue
                            ? AppColors.dangerText
                            : AppColors.muted,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: group.overdue
                            ? const Color(0xFFFECDD3)
                            : AppColors.border,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < group.items.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _TaskRow(
                            item: group.items[i],
                            overdue: group.overdue,
                            onToggleCompleted: (done) => ref
                                .read(tasksRepositoryProvider)
                                .toggleCompleted(group.items[i].task.id, done),
                            onToggleAlert: (on) => ref
                                .read(tasksRepositoryProvider)
                                .toggleAlert(group.items[i].task.id, on),
                            onEdit: () => context
                                .push(Routes.editTask(group.items[i].task.id)),
                            onDelete: () =>
                                _confirmDelete(group.items[i].task.id),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
            ],
          );
        },
      ),
    );
  }

  /// Overdue first, then one group per day.
  List<({String label, bool overdue, List<TaskReminderItem> items})> _group(
    List<TaskReminderItem> tasks,
  ) {
    final now = DateTime.now();
    final today = dateOnly(now);
    final sorted = [...tasks]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final overdue = <TaskReminderItem>[];
    final byDay = <DateTime, List<TaskReminderItem>>{};
    for (final t in sorted) {
      if (!t.task.isCompleted && t.dueAt.isBefore(now)) {
        overdue.add(t);
      } else {
        byDay.putIfAbsent(dateOnly(t.dueAt), () => []).add(t);
      }
    }
    String label(DateTime day) {
      final date = DateFormat('EEE d MMM', uiDateLocale).format(day);
      final diff = day.difference(today).inDays;
      if (diff == 0) return '${tr('Today')} · $date';
      if (diff == 1) return '${tr('Tomorrow')} · $date';
      return date;
    }

    return [
      if (overdue.isNotEmpty)
        (label: tr('Overdue'), overdue: true, items: overdue),
      for (final entry in byDay.entries)
        (label: label(entry.key), overdue: false, items: entry.value),
    ];
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.item,
    required this.overdue,
    required this.onToggleCompleted,
    required this.onToggleAlert,
    required this.onEdit,
    required this.onDelete,
  });

  final TaskReminderItem item;
  final bool overdue;
  final ValueChanged<bool> onToggleCompleted;
  final ValueChanged<bool> onToggleAlert;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final task = item.task;
    final due = item.dueAt;
    final done = task.isCompleted;
    final time = DateFormat('h:mm a', uiDateLocale).format(due);
    final when = overdue
        ? '${DateFormat('EEE d MMM', uiDateLocale).format(due)} · $time'
        : time;
    final detail = [
      when,
      if (task.intervalMinutes != null)
        tr('repeat every {intervalMinutes}m',
            {'intervalMinutes': task.intervalMinutes}),
      if (task.personName != null) task.personName!,
    ].join(' · ');
    final phone = task.phone;

    return InkWell(
      onTap: onEdit,
      onLongPress: onDelete,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              checked: done,
              label: tr('Mark done'),
              child: InkResponse(
                onTap: () => onToggleCompleted(!done),
                radius: 24,
                child: SizedBox(
                  width: 48,
                  height: 40,
                  child: Center(
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? AppColors.successFill : AppColors.surface,
                        border: Border.all(
                          color:
                              done ? AppColors.successFill : AppColors.inputBorder,
                          width: 2,
                        ),
                      ),
                      child: done
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? AppColors.muted : AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: overdue ? FontWeight.w700 : FontWeight.w600,
                        color: overdue ? AppColors.dangerText : AppColors.muted,
                      ),
                    ),
                    if (task.notes != null && task.notes!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        task.notes!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        AppBadge(
                          task.taskType.label,
                          icon: taskTypeIcon(task.taskType),
                          tone: taskTypeTone(task.taskType),
                        ),
                        if (item.jobTitle != null) AppBadge(item.jobTitle!),
                        if (phone != null) ...[
                          _MiniButton(
                            label: tr('Call'),
                            onTap: () => launchUrl(Uri.parse('tel:$phone')),
                          ),
                          _MiniButton(
                            label: tr('WhatsApp'),
                            onTap: () => launchUrl(
                              Uri.parse('https://wa.me/$phone?text=Hello'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                task.isAlertActive
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                size: 20,
                color: task.isAlertActive ? AppColors.warningText : AppColors.faint,
              ),
              tooltip: task.isAlertActive
                  ? tr('Turn off alert')
                  : tr('Turn on alert'),
              onPressed: () => onToggleAlert(!task.isAlertActive),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}
