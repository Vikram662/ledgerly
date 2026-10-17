import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/backup/backup_providers.dart';
import '../../../core/backup/clock_check.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../backup/presentation/backup_screen.dart';
import '../../calendar/data/calendar_repository.dart';
import '../../expenses/data/expenses_repository.dart';
import '../../reports/presentation/dues_screen.dart';
import '../../tasks/data/tasks_repository.dart';

/// Home (wireframe 01, PRD E2 / DB-01..DB-03): greeting, backup state,
/// Lena / Dena, quick actions, today's attendance, tasks, recent activity.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backup = ref.watch(backupStateProvider).valueOrNull;
    final personal = ref.watch(userTypeProvider) == UserType.personal;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const _Header(),
            const SizedBox(height: 16),
            const _BackupProgressCard(),
            if (backup != null) _BackupStrip(state: backup),
            personal ? const _SpendingCard() : const _DuesCard(),
            const SizedBox(height: 16),
            const _QuickActions(),
            if (!personal) ...[
              const SizedBox(height: 16),
              const _TodayCard(),
            ],
            const SizedBox(height: 16),
            const _TasksSection(),
            const _RecentActivity(),
          ],
        ),
      ),
    );
  }
}

/// Business tile (opens More), greeting and name, bell for tasks.
class _Header extends ConsumerWidget {
  const _Header();

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return tr('Good morning');
    if (hour < 17) return tr('Good afternoon');
    return tr('Good evening');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(businessProfileProvider).valueOrNull?.name ?? '';
    return Row(
      children: [
        Semantics(
          button: true,
          label: tr('Open menu'),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push(Routes.more),
            child: BrandTile(name: name, size: 44),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.18,
                ),
              ),
            ],
          ),
        ),
        AppIconButton(
          icon: Icons.notifications_none,
          tooltip: tr('Tasks & Reminders'),
          onPressed: () => openRoute(context, Routes.tasks),
        ),
      ],
    );
  }
}

/// One-line backup state under the header (PRD DB-01, D1, D3.1): green when
/// backed up, amber while pending, red when missing or failing.
class _BackupStrip extends ConsumerWidget {
  const _BackupStrip({required this.state});

  final BackupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skew = state.clockSkew;
    final last = state.lastBackupAt;
    final (Color bg, Color fg, Color dot, String text) = switch (state.health) {
      BackupHealth.synced when skew != null => (
          AppColors.warningSurface,
          AppColors.warningText,
          AppColors.amber500,
          tr('Phone time is {skew} compared to Google. Turn on automatic date & time in phone settings.',
              {'skew': describeClockSkew(skew)}),
        ),
      BackupHealth.synced => (
          AppColors.successSurface,
          AppColors.successText,
          AppColors.successFill,
          last == null
              ? tr('Backed up to Google Drive')
              : tr('Backed up to Google Drive · {time}',
                  {'time': DateFormat('h:mm a', uiDateLocale).format(last)}),
        ),
      BackupHealth.pending => (
          AppColors.warningSurface,
          AppColors.warningText,
          AppColors.amber500,
          state.pendingTooLong
              ? tr('Backup pending for over a day. Connect to the internet.')
              : tr('Backup pending'),
        ),
      BackupHealth.failed => (
          AppColors.dangerSurface,
          AppColors.dangerText,
          AppColors.dangerFill,
          state.blocked
              ? tr('Backup stopped: this data was restored on another phone.')
              : '${tr('No backup in the last 24 hours.')} ${state.lastError ?? ''}'
                  .trim(),
        ),
      BackupHealth.notSetUp => (
          AppColors.dangerSurface,
          AppColors.dangerText,
          AppColors.dangerFill,
          tr('Backup not set up. Your data is only on this phone.'),
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: () => _showBackupSheet(context, ref, dot),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Status, Backup now and backup settings.
void _showBackupSheet(BuildContext context, WidgetRef ref, Color color) {
  // Actions use the Home screen's context and ref, which outlive the sheet.
  showModalBottomSheet<void>(
    context: context,
    builder: (_) => Consumer(
      builder: (sheetContext, sheetRef, _) {
        final state = sheetRef.watch(backupStateProvider).valueOrNull;
        final running = sheetRef.watch(backupRunningProvider);
        final last = state?.lastBackupAt;
        final label = switch (state?.health) {
          BackupHealth.synced => tr('Backed up'),
          BackupHealth.pending => tr('Backup pending'),
          BackupHealth.failed => tr('Backup problem'),
          _ => tr('Backup not set up'),
        };
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.circle, size: 12, color: color),
                    const SizedBox(width: 8),
                    Text(label,
                        style: Theme.of(sheetContext).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  last == null
                      ? tr('No backup yet')
                      : tr('Last backup: {date}',
                          {'date': dayTimeFormat.format(last)}),
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: running
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop();
                          runManualBackup(context, ref);
                        },
                  icon: const Icon(Icons.backup),
                  label: Text(running ? tr('Backing up…') : tr('Backup now')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    context.push(Routes.backup);
                  },
                  icon: const Icon(Icons.settings_backup_restore),
                  label: Text(tr('Backup settings & restore')),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Live % while a backup runs in the app.
class _BackupProgressCard extends ConsumerWidget {
  const _BackupProgressCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(backupProgressProvider);
    if (progress == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.cloud_upload, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: PercentProgress(
                value: progress.fraction,
                label: progress.step,
                detail: progress.detail,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card with a small grey title, a link and two figures side by side.
class _TwoFigureCard extends StatelessWidget {
  const _TwoFigureCard({
    required this.title,
    required this.link,
    required this.onLink,
    required this.left,
    required this.right,
  });

  final String title;
  final String link;
  final VoidCallback onLink;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ),
              InkWell(
                onTap: onLink,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    link,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: left),
                const VerticalDivider(width: 24),
                Expanded(child: right),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One figure: small label, big amount, optional note or badge.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.note,
    this.badge,
    this.onTap,
  });

  final String label;
  final String value;
  final String? note;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppText.amount),
          ),
          const SizedBox(height: 4),
          if (badge != null)
            StatusChip(label: badge!, color: AppColors.dangerText)
          else
            Text(
              note ?? ' ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
        ],
      ),
    );
  }
}

/// Lena / Dena for contractors and shops.
class _DuesCard extends ConsumerWidget {
  const _DuesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(duesReportProvider).valueOrNull;
    final overdue = report?.overdueTotal ?? 0;
    final shop = ref.watch(userTypeProvider) == UserType.shop;
    return _TwoFigureCard(
      title: tr('Lena / Dena'),
      link: tr('Report'),
      onLink: () => context.push(Routes.dues()),
      left: _Figure(
        label: tr('To receive'),
        value: report == null ? '…' : formatPaise(report.lenaTotal),
        badge: overdue > 0
            ? tr('{amount} overdue', {'amount': formatPaise(overdue)})
            : null,
        onTap: () => context.push(Routes.dues(0)),
      ),
      right: _Figure(
        label: tr('To pay'),
        value: report == null ? '…' : formatPaise(report.denaTotal),
        note: shop ? tr('Staff + suppliers') : tr('Workers + suppliers'),
        onTap: () => context.push(Routes.dues(1)),
      ),
    );
  }
}

/// This month's and last month's spending for personal users.
class _SpendingCard extends ConsumerWidget {
  const _SpendingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month - 1);
    String total(ExpenseMonth month) {
      final items = ref.watch(monthExpensesProvider(month)).valueOrNull;
      if (items == null) return '…';
      return formatPaise(
          items.fold<int>(0, (sum, item) => sum + item.expense.amountPaise));
    }

    return _TwoFigureCard(
      title: tr('Spending'),
      link: tr('Expenses'),
      onLink: () => openRoute(context, Routes.expenses),
      left: _Figure(
        label: tr('Spent this month'),
        value: total((year: now.year, month: now.month)),
        note: monthFormat.format(now),
      ),
      right: _Figure(
        label: tr('Spent last month'),
        value: total((year: last.year, month: last.month)),
        note: monthFormat.format(last),
      ),
    );
  }
}

/// Four big square shortcuts; the main one is blue, Advance amber.
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = switch (ref.watch(userTypeProvider)) {
      UserType.personal => [
          _QuickAction(
            icon: Icons.receipt_outlined,
            label: tr('Expense'),
            style: _QuickStyle.primary,
            onTap: () => context.push(Routes.addExpense),
          ),
          _QuickAction(
            icon: Icons.alarm_add_outlined,
            label: tr('Reminder'),
            onTap: () => context.push(Routes.addTask),
          ),
          _QuickAction(
            icon: Icons.calendar_month_outlined,
            label: tr('Calendar'),
            onTap: () => context.push(Routes.calendar),
          ),
          _QuickAction(
            icon: Icons.cloud_upload_outlined,
            label: tr('Backup'),
            onTap: () => context.push(Routes.backup),
          ),
        ],
      _ => [
          _QuickAction(
            icon: Icons.receipt_long_outlined,
            label: tr('New bill'),
            style: _QuickStyle.primary,
            onTap: () =>
                context.push(Routes.newDocument(DocumentKind.invoice)),
          ),
          _QuickAction(
            icon: Icons.payments_outlined,
            label: tr('Advance'),
            style: _QuickStyle.amber,
            onTap: () =>
                context.push(Routes.ledgerEntry(type: LedgerType.advance)),
          ),
          _QuickAction(
            icon: Icons.fact_check_outlined,
            label: tr('Attendance'),
            onTap: () => openRoute(context, Routes.attendance()),
          ),
          _QuickAction(
            icon: Icons.shopping_bag_outlined,
            label: tr('Expense'),
            onTap: () => context.push(Routes.addExpense),
          ),
        ],
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: actions[i]),
        ],
      ],
    );
  }
}

enum _QuickStyle { plain, primary, amber }

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.style = _QuickStyle.plain,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final _QuickStyle style;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color border) = switch (style) {
      _QuickStyle.primary => (AppColors.primary, Colors.white, AppColors.primary),
      _QuickStyle.amber => (AppColors.amber500, AppColors.ink, AppColors.amber500),
      _QuickStyle.plain => (AppColors.surface, AppColors.ink, AppColors.border),
    };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: Icon(icon, size: 24, color: fg),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today's attendance: marked / total, a stacked bar and counts (DB-03).
class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final rows =
        ref.watch(attendanceDayProvider(isoDate(today))).valueOrNull ?? const [];
    final shop = ref.watch(userTypeProvider) == UserType.shop;
    int count(AttendanceStatus status) =>
        rows.where((r) => r.attendance?.status == status).length;
    final present = count(AttendanceStatus.present);
    final half = count(AttendanceStatus.half);
    final absent = count(AttendanceStatus.absent);
    final total = rows.length;
    final marked = rows.where((r) => r.attendance != null).length;
    final left = total - marked;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr("Today's attendance"),
                        style: AppText.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      total == 0
                          ? (shop
                              ? tr('No staff added yet')
                              : tr('No workers added yet'))
                          : tr('{marked} of {total} marked · {date}', {
                              'marked': marked,
                              'total': total,
                              'date': DateFormat('EEE, d MMM', uiDateLocale)
                                  .format(today),
                            }),
                      style: AppText.tabular.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  textStyle:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                onPressed: () => openRoute(
                    context, total == 0 ? Routes.addWorker : Routes.attendance()),
                child: Text(total == 0 ? tr('Add') : tr('Mark')),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    if (present > 0)
                      Expanded(
                          flex: present,
                          child: const ColoredBox(color: AppColors.successFill)),
                    if (half > 0)
                      Expanded(
                          flex: half,
                          child: const ColoredBox(color: AppColors.amber500)),
                    if (absent > 0)
                      Expanded(
                          flex: absent,
                          child: const ColoredBox(color: AppColors.dangerFill)),
                    if (total - present - half - absent > 0)
                      Expanded(
                        flex: total - present - half - absent,
                        child: const ColoredBox(color: AppColors.divider),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _Legend(AppColors.successFill,
                    tr('{count} Present', {'count': present})),
                _Legend(AppColors.amber500, tr('{count} Half', {'count': half})),
                _Legend(AppColors.dangerFill,
                    tr('{count} Absent', {'count': absent})),
                if (left > 0)
                  Text(
                    tr('{count} left', {'count': left}),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.text);

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: AppText.tabular
              .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Section title with a "View all" style link on the right.
class _SectionHead extends StatelessWidget {
  const _SectionHead(this.title, {this.link, this.onLink});

  final String title;
  final String? link;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: AppText.titleMedium),
          ),
          if (link != null)
            InkWell(
              onTap: onLink,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  link!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The next pending tasks (Module C8), overdue in red.
class _TasksSection extends ConsumerWidget {
  const _TasksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(pendingTasksProvider).valueOrNull;
    if (tasks == null) return const SizedBox.shrink();
    final contractor = ref.watch(userTypeProvider) == UserType.contractor;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final time = DateFormat('h:mm a', uiDateLocale);

    String when(DateTime due) {
      final day = DateTime(due.year, due.month, due.day);
      final days = day.difference(today).inDays;
      if (due.isBefore(now)) {
        final late = today.difference(day).inDays;
        return late <= 0
            ? tr('Overdue · {time}', {'time': time.format(due)})
            : trPlural(late, 'Overdue by 1 day', 'Overdue by {count} days');
      }
      if (days == 0) return tr('Today · {time}', {'time': time.format(due)});
      if (days == 1) return tr('Tomorrow · {time}', {'time': time.format(due)});
      return '${DateFormat('EEE d MMM', uiDateLocale).format(due)} · ${time.format(due)}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHead(
            contractor ? tr('Tasks & site visits') : tr('Tasks & reminders'),
            link: tr('View all'),
            onLink: () => openRoute(context, Routes.tasks),
          ),
          if (tasks.isEmpty)
            Panel(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('No pending tasks. Stay on track!'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push(Routes.addTask),
                    child: Text(tr('+ Add')),
                  ),
                ],
              ),
            )
          else
            CardList(
              children: [
                for (final task in tasks.take(3))
                  _TaskRow(
                    due: task.dueAt,
                    title: task.title,
                    when: when(task.dueAt),
                    overdue: task.dueAt.isBefore(now),
                    onTap: () => openRoute(context, Routes.tasks),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.due,
    required this.title,
    required this.when,
    required this.overdue,
    required this.onTap,
  });

  final DateTime due;
  final String title;
  final String when;
  final bool overdue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = overdue ? AppColors.dangerText : AppColors.ink;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            DateTile(date: due, danger: overdue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    when,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: overdue ? FontWeight.w700 : FontWeight.w600,
                      color: overdue ? accent : AppColors.muted,
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

/// The latest money and khata entries of this month (from the calendar).
class _RecentActivity extends ConsumerWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final month =
        ref.watch(calendarMonthProvider((year: now.year, month: now.month)));
    final events = [
      for (final entry in (month.valueOrNull?.events ?? const <String, List<CalendarEvent>>{}).entries)
        for (final e in entry.value)
          if (e.kind != CalendarEventKind.holiday) e,
    ]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.sortKey.compareTo(a.sortKey);
      });
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHead(tr('Recent activity'),
            link: tr('Calendar'), onLink: () => context.push(Routes.calendar)),
        CardList(
          children: [
            for (final e in events.take(4)) ActivityRow(event: e),
          ],
        ),
      ],
    );
  }
}

/// One calendar event as a list row: icon tile, title, detail, amount.
class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final amount = event.amountPaise;
    final (sign, color) = switch (event.flow) {
      MoneyFlow.incoming => ('+', AppColors.successText),
      MoneyFlow.outgoing => ('−', AppColors.ink),
      MoneyFlow.none => ('', AppColors.ink),
    };
    final route = event.route;
    return InkWell(
      onTap: route == null ? null : () => openRoute(context, route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.track,
                shape: BoxShape.circle,
              ),
              child: Icon(eventIcon(event.kind),
                  size: 20, color: AppColors.inkSoft),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  if (event.subtitle != null && event.subtitle!.isNotEmpty)
                    Text(
                      event.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (amount != null) ...[
              const SizedBox(width: 8),
              Text(
                '$sign${formatPaise(amount)}',
                style: AppText.tabular.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

IconData eventIcon(CalendarEventKind kind) => switch (kind) {
      CalendarEventKind.bill => Icons.receipt_long_outlined,
      CalendarEventKind.quotation => Icons.request_quote_outlined,
      CalendarEventKind.paymentIn => Icons.south_west,
      CalendarEventKind.workerPaid => Icons.payments_outlined,
      CalendarEventKind.workerOther => Icons.account_balance_wallet_outlined,
      CalendarEventKind.pieceWork => Icons.straighten,
      CalendarEventKind.settlement => Icons.task_alt,
      CalendarEventKind.expense => Icons.shopping_bag_outlined,
      CalendarEventKind.purchase => Icons.local_shipping_outlined,
      CalendarEventKind.supplierPaid => Icons.north_east,
      CalendarEventKind.holiday => Icons.celebration_outlined,
    };
