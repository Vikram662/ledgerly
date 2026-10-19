import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/attendance_repository.dart';
import 'attendance_widgets.dart';

const _nameWidth = 104.0;
const _cellWidth = 30.0;
const _rowHeight = 42.0;
const _totalWidth = 44.0;

/// All workers × all days of a month. Each cell shows P / ½ / A / Off / L;
/// tap a cell to change it (PRD AT-04).
/// The month is kept by the parent so its header can share that month's PDF.
class MonthRegisterView extends ConsumerStatefulWidget {
  const MonthRegisterView({
    super.key,
    required this.month,
    required this.onMonthChanged,
  });

  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  ConsumerState<MonthRegisterView> createState() => _MonthRegisterViewState();
}

class _MonthRegisterViewState extends ConsumerState<MonthRegisterView> {
  final _horizontal = ScrollController();

  DateTime get _month => widget.month;

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  void initState() {
    super.initState();
    // Start scrolled near today in the current month.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_horizontal.hasClients || !_isCurrentMonth) return;
      final target = (DateTime.now().day - 6) * _cellWidth;
      _horizontal.jumpTo(
        target.clamp(0, _horizontal.position.maxScrollExtent).toDouble(),
      );
    });
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  void _shift(int months) =>
      widget.onMonthChanged(DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final register = ref.watch(
      monthRegisterProvider((year: _month.year, month: _month.month)),
    );
    final weeklyOff = ref.watch(appSettingsProvider).valueOrNull?.weeklyOffDay;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: MonthSwitcher(
            month: _month,
            onShift: _shift,
            canGoNext: !_isCurrentMonth,
          ),
        ),
        Expanded(
          child: register.when(
            loading: () => const ListSkeleton(),
            error: (e, _) => Center(child: Text(errorText(e))),
            data: (r) => r.workers.isEmpty
                ? EmptyState(
                    icon: Icons.groups,
                    title: tr('No workers this month'),
                    message: tr('Add workers to see the attendance register.'),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Panel(
                      padding: EdgeInsets.zero,
                      child: SingleChildScrollView(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _NameColumn(workers: r.workers, month: r.month),
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _horizontal,
                                scrollDirection: Axis.horizontal,
                                child:
                                    _Grid(register: r, weeklyOff: weeklyOff),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        const _Legend(),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final s in const [
              AttendanceStatus.present,
              AttendanceStatus.half,
              AttendanceStatus.absent,
              AttendanceStatus.off,
              AttendanceStatus.leavePaid,
            ])
              LegendDot(
                color: markColors(s).$1,
                label: statusStyle(s).label,
                square: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _NameColumn extends StatelessWidget {
  const _NameColumn({required this.workers, required this.month});

  final List<Worker> workers;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _nameWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _rowHeight,
            child: Padding(
              padding: EdgeInsets.only(left: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr('Worker'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ),
          ),
          for (final w in workers)
            // Tap a name → that worker's month calendar.
            InkWell(
              onTap: () => showWorkerAttendanceSheet(context, w, month),
              child: Container(
                height: _rowHeight,
                padding: const EdgeInsets.only(left: 12, right: 6),
                alignment: Alignment.centerLeft,
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.divider),
                    right: BorderSide(color: AppColors.divider),
                  ),
                ),
                child: Text(
                  w.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: w.isActive ? AppColors.ink : AppColors.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({required this.register, required this.weeklyOff});

  final MonthRegister register;
  final int? weeklyOff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = register.month;
    final today = DateTime.now();
    final todayDay = month.year == today.year && month.month == today.month
        ? today.day
        : null;
    final weekLetters = weekdayLetters;

    Widget header(String top, String bottom,
            {bool highlight = false, double width = _cellWidth}) =>
        Container(
          width: width,
          height: _rowHeight,
          color: highlight ? AppColors.primarySurface : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(top,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              Text(bottom,
                  style:
                      const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted)),
            ],
          ),
        );

    Widget total(String text, {bool bold = false}) => SizedBox(
          width: _totalWidth,
          height: _rowHeight,
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var d = 1; d <= register.days; d++)
              header(
                '$d',
                weekLetters[DateTime(month.year, month.month, d).weekday - 1],
                highlight: d == todayDay,
              ),
            header('P', tr('days'), width: _totalWidth),
            header('½', tr('days'), width: _totalWidth),
            header('A', tr('days'), width: _totalWidth),
            header(tr('Paid'), tr('days'), width: _totalWidth),
          ],
        ),
        for (final w in register.workers)
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                for (var d = 1; d <= register.days; d++)
                  _Cell(
                    worker: w,
                    date: DateTime(month.year, month.month, d),
                    status: register.marks[w.id]?[d],
                    isWeeklyOff: DateTime(month.year, month.month, d).weekday ==
                        weeklyOff,
                    isToday: d == todayDay,
                  ),
                total('${register.count(w.id, AttendanceStatus.present)}'),
                total('${register.count(w.id, AttendanceStatus.half)}'),
                total('${register.count(w.id, AttendanceStatus.absent)}'),
                total(_days(register.paidDays(w.id)), bold: true),
              ],
            ),
          ),
      ],
    );
  }

  static String _days(double d) =>
      d == d.roundToDouble() ? '${d.toInt()}' : d.toStringAsFixed(1);
}

class _Cell extends ConsumerWidget {
  const _Cell({
    required this.worker,
    required this.date,
    required this.status,
    required this.isWeeklyOff,
    required this.isToday,
  });

  final Worker worker;
  final DateTime date;
  final AttendanceStatus? status;
  final bool isWeeklyOff;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final future = date.isAfter(DateTime(today.year, today.month, today.day));
    final beforeJoin = date.isBefore(parseIsoDate(worker.joinDate));
    final enabled = !future && !beforeJoin;

    return InkWell(
      onTap: enabled
          ? () => showStatusSheet(
                context,
                ref,
                workerId: worker.id,
                date: date,
                current: status,
              )
          : null,
      child: Container(
        width: _cellWidth,
        height: _rowHeight,
        color: isToday ? AppColors.primarySurface : null,
        alignment: Alignment.center,
        child: status != null
            ? _Mark(status: status!, size: 26)
            : Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isWeeklyOff && enabled ? AppColors.divider : null,
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Text(
                  enabled ? '·' : '',
                  style: const TextStyle(color: AppColors.faint, fontSize: 16),
                ),
              ),
      ),
    );
  }
}

/// Coloured letter badge: P / ½ / A / Off / PL / UL.
class _Mark extends StatelessWidget {
  const _Mark({required this.status, required this.size});

  final AttendanceStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = statusStyle(status);
    final (bg, fg) = markColors(status);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        style.short,
        style: TextStyle(
          fontSize: style.short.length > 1 ? 9 : 11,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

/// Soft background and text colour of a register cell.
(Color, Color) markColors(AttendanceStatus status) => switch (status) {
      AttendanceStatus.present =>
        (AppColors.successSurface, AppColors.successText),
      AttendanceStatus.half => (AppColors.warningSurface, AppColors.warningText),
      AttendanceStatus.absent => (AppColors.dangerSurface, AppColors.dangerText),
      AttendanceStatus.leavePaid =>
        (AppColors.primarySurface, AppColors.primary),
      AttendanceStatus.leaveUnpaid ||
      AttendanceStatus.off =>
        (AppColors.divider, AppColors.muted),
    };
