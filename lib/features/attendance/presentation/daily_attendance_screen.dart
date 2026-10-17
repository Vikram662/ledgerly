import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pickers.dart';
import '../../subscription/presentation/subscription_screen.dart';
import '../data/attendance_repository.dart';
import 'attendance_widgets.dart';

/// PRD AT-01 / AT-02: one list, P / ½ / A per worker, OT stepper,
/// "Mark all present" and "Copy yesterday".
/// Body only; shown inside the Attendance tab (attendance_screen.dart).
class DailyAttendanceView extends ConsumerStatefulWidget {
  const DailyAttendanceView({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  ConsumerState<DailyAttendanceView> createState() =>
      _DailyAttendanceViewState();
}

class _DailyAttendanceViewState extends ConsumerState<DailyAttendanceView> {
  late DateTime _date = dateOnly(widget.initialDate ?? DateTime.now());

  @override
  void didUpdateWidget(DailyAttendanceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final date = widget.initialDate;
    if (date != null && date != oldWidget.initialDate) {
      setState(() => _date = dateOnly(date));
    }
  }

  bool get _isToday => _date == dateOnly(DateTime.now());

  void _shift(int days) {
    final next = DateTime(_date.year, _date.month, _date.day + days);
    if (next.isAfter(dateOnly(DateTime.now()))) return;
    setState(() => _date = next);
  }

  Future<void> _markAll(AttendanceStatus status) async {
    if (!await requirePro(context, ref)) return;
    final count = await ref
        .read(attendanceRepositoryProvider)
        .markAllUnmarked(_date, status);
    if (mounted) {
      showMessage(
        context,
        count == 0
            ? tr('Everyone is already marked')
            : tr('Marked {count} workers', {'count': count}),
      );
    }
  }

  Future<void> _copyYesterday() async {
    if (!await requirePro(context, ref)) return;
    final count = await ref.read(attendanceRepositoryProvider).copyDay(
          from: DateTime(_date.year, _date.month, _date.day - 1),
          to: _date,
        );
    if (mounted) {
      showMessage(
        context,
        count == 0
            ? tr('Nothing to copy')
            : tr('Copied {count} from previous day', {'count': count}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(attendanceDayProvider(isoDate(_date)));
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final isWeeklyOff = settings?.weeklyOffDay == _date.weekday;
    final allStatus =
        isWeeklyOff ? AttendanceStatus.off : AttendanceStatus.present;

    final dayPicker = _DayPicker(
      date: _date,
      isToday: _isToday,
      weeklyOff: isWeeklyOff,
      onShift: _shift,
      onPick: (picked) => setState(() => _date = dateOnly(picked)),
    );

    return rows.when(
      loading: () => const ListSkeleton(),
      error: (e, _) => Center(child: Text(errorText(e))),
      data: (list) {
        int count(AttendanceStatus s) =>
            list.where((r) => r.attendance?.status == s).length;
        final marked = list.where((r) => r.attendance != null).length;
        final left = list.length - marked;
        if (list.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              dayPicker,
              EmptyState(
                icon: Icons.groups,
                title: tr('No workers on this day'),
                message: tr('Add workers first, or pick a later date.'),
              ),
            ],
          );
        }
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  dayPicker,
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _CountCard(count(AttendanceStatus.present),
                          tr('Present'), AppColors.successText),
                      const SizedBox(width: 8),
                      _CountCard(count(AttendanceStatus.half), tr('Half day'),
                          AppColors.warningText),
                      const SizedBox(width: 8),
                      _CountCard(count(AttendanceStatus.absent), tr('Absent'),
                          AppColors.dangerText),
                      const SizedBox(width: 8),
                      _CountCard(left, tr('Not marked'), AppColors.ink),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: SmallOutlinedButton(
                          icon: Icons.done_all,
                          label: isWeeklyOff
                              ? tr('Mark all Off')
                              : tr('Mark all present'),
                          onTap: () => _markAll(allStatus),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SmallOutlinedButton(
                          icon: Icons.content_copy,
                          label: tr('Copy yesterday'),
                          onTap: _copyYesterday,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  CardList(
                    children: [
                      for (final row in list)
                        _AttendanceRowTile(row: row, date: _date),
                    ],
                  ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('{marked} of {count} marked',
                                {'marked': marked, 'count': list.length}),
                            style: AppText.tabular.copyWith(
                                fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            tr('Saves automatically'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                        ),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      onPressed: left == 0 ? null : () => _markAll(allStatus),
                      child: Text(isWeeklyOff
                          ? tr('Mark rest Off')
                          : tr('Mark rest present')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// White card: previous day, the date (tap to pick), next day.
class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.date,
    required this.isToday,
    required this.weeklyOff,
    required this.onShift,
    required this.onPick,
  });

  final DateTime date;
  final bool isToday;
  final bool weeklyOff;
  final ValueChanged<int> onShift;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final title = isToday
        ? tr('Today')
        : date == yesterday
            ? tr('Yesterday')
            : DateFormat('d MMM yyyy', uiDateLocale).format(date);
    final sub = DateFormat('EEEE, d MMM', uiDateLocale).format(date);
    return Panel(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          IconButton(
            tooltip: tr('Previous day'),
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onShift(-1),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.small),
              onTap: () async {
                final picked = await pickDate(
                  context,
                  initial: date,
                  last: DateTime.now(),
                );
                if (picked != null) onPick(picked);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      weeklyOff ? '$sub · ${tr('Weekly off')}' : sub,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: tr('Next day'),
            icon: const Icon(Icons.chevron_right),
            onPressed: isToday ? null : () => onShift(1),
          ),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard(this.count, this.label, this.color);

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Column(
          children: [
            Text(
              '$count',
              style: AppText.tabular.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceRowTile extends ConsumerWidget {
  const _AttendanceRowTile({required this.row, required this.date});

  final AttendanceRow row;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = row.attendance?.status;
    final ot = row.attendance?.otMilliHours ?? 0;
    final working =
        current == AttendanceStatus.present || current == AttendanceStatus.half;
    // Leave and weekly off are set from the long-press sheet.
    final other = current != null &&
        current != AttendanceStatus.present &&
        current != AttendanceStatus.half &&
        current != AttendanceStatus.absent;

    Future<void> mark(AttendanceStatus status) => markAttendance(
          context,
          ref,
          workerId: row.worker.id,
          date: date,
          status: status,
        );

    Future<void> setOt(int milliHours) => markAttendance(
          context,
          ref,
          workerId: row.worker.id,
          date: date,
          status: current,
          otMilliHours: milliHours < 0 ? 0 : milliHours,
        );

    final Widget subtitle;
    if (current == null) {
      subtitle = Text(
        tr('Not marked'),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.warningText,
        ),
      );
    } else {
      subtitle = Text(
        other ? statusStyle(current).label : (row.roleName ?? ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: other ? statusStyle(current).color : AppColors.muted,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              InitialsAvatar(row.worker.name),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onLongPress: () => showStatusSheet(
                    context,
                    ref,
                    workerId: row.worker.id,
                    date: date,
                    current: current,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.worker.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      subtitle,
                    ],
                  ),
                ),
              ),
              for (final status in const [
                AttendanceStatus.present,
                AttendanceStatus.half,
                AttendanceStatus.absent,
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: _StatusButton(
                    status: status,
                    selected: current == status,
                    onTap: () => mark(status),
                  ),
                ),
            ],
          ),
          if (working)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: AppColors.page,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Row(
                children: [
                  Text(
                    tr('Overtime'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  StepButton(
                    icon: Icons.remove,
                    tooltip: tr('Less OT'),
                    onTap: ot <= 0 ? null : () => setOt(ot - 500),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      tr('{hours} h', {'hours': formatMilli(ot)}),
                      textAlign: TextAlign.center,
                      style: AppText.tabular.copyWith(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  StepButton(
                    icon: Icons.add,
                    tooltip: tr('More OT'),
                    onTap: () => setOt(ot + 500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 44px P / ½ / A key; filled green, amber or red when chosen.
class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final AttendanceStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = statusStyle(status);
    final (Color fill, Color text) = switch (status) {
      AttendanceStatus.present => (AppColors.successFill, Colors.white),
      AttendanceStatus.half => (AppColors.amber500, AppColors.ink),
      _ => (AppColors.dangerFill, Colors.white),
    };
    return Semantics(
      selected: selected,
      label: style.label,
      button: true,
      excludeSemantics: true,
      child: Material(
        color: selected ? fill : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          side: BorderSide(color: selected ? fill : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Text(
                style.short,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: selected ? text : AppColors.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
