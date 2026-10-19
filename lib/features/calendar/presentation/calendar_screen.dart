import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../data/calendar_repository.dart';

DateFormat get _dayHeading => DateFormat('EEE, d MMM', uiDateLocale);
DateFormat get _monthTitle => DateFormat('MMMM yyyy', uiDateLocale);

/// Icon and colour for each kind of event.
(IconData, Color) eventStyle(CalendarEventKind kind) => switch (kind) {
      CalendarEventKind.bill => (Icons.receipt_long, AppColors.blue700),
      CalendarEventKind.quotation => (Icons.request_quote, AppColors.muted),
      CalendarEventKind.paymentIn => (
          Icons.call_received,
          AppColors.successText
        ),
      CalendarEventKind.workerPaid => (Icons.payments, AppColors.dangerText),
      CalendarEventKind.workerOther => (Icons.edit_note, AppColors.warningText),
      CalendarEventKind.pieceWork => (
          Icons.construction,
          AppColors.warningText
        ),
      CalendarEventKind.settlement => (Icons.task_alt, AppColors.dangerText),
      CalendarEventKind.expense => (Icons.shopping_cart, AppColors.dangerText),
      CalendarEventKind.purchase => (Icons.local_shipping, AppColors.muted),
      CalendarEventKind.supplierPaid => (Icons.store, AppColors.dangerText),
      CalendarEventKind.holiday => (Icons.celebration, AppColors.warningText),
      CalendarEventKind.task => (Icons.task_alt, AppColors.primary),
      CalendarEventKind.dueDate => (Icons.event_busy, AppColors.dangerText),
    };

/// Dot colour of an event in the month grid (wireframe legend): money in,
/// money out, bill / quote, holiday. Null: no dot.
Color? _dotColor(CalendarEvent e) {
  if (e.kind == CalendarEventKind.holiday) return AppColors.amber500;
  if (e.flow == MoneyFlow.incoming) return AppColors.successFill;
  if (e.flow == MoneyFlow.outgoing) return AppColors.dangerFill;
  return switch (e.kind) {
    CalendarEventKind.bill ||
    CalendarEventKind.quotation ||
    CalendarEventKind.dueDate =>
      AppColors.primary,
    _ => null,
  };
}

/// Business calendar (wireframe Calendar): month grid with dots, then the
/// chosen day's attendance and entries. View only; tap an entry to open it.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _day = dateOnly(DateTime.now());

  DateTime get _month => DateTime(_day.year, _day.month);

  void _shift(int months) => setState(() {
        final target = DateTime(_day.year, _day.month + months);
        final now = DateTime.now();
        // The 1st, or today when moving back to the current month.
        _day = target.year == now.year && target.month == now.month
            ? dateOnly(now)
            : target;
      });

  @override
  Widget build(BuildContext context) {
    final async = ref
        .watch(calendarMonthProvider((year: _month.year, month: _month.month)));
    final data = async.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Calendar')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: MiniButton(
              label: tr('Today'),
              onTap: () => setState(() => _day = dateOnly(DateTime.now())),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Panel(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _MonthHeader(month: _month, onShift: _shift),
                const SizedBox(height: 10),
                if (data == null)
                  const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _MonthGrid(
                    data: data,
                    selected: _day,
                    onTap: (date) => setState(() => _day = date),
                  ),
                const SizedBox(height: 10),
                const _Legend(),
              ],
            ),
          ),
          if (data != null) ...[
            const SizedBox(height: 12),
            _DayHeading(date: _day, attendance: data.attendance[isoDate(_day)]),
            const SizedBox(height: 8),
            _DayEvents(events: data.on(isoDate(_day))),
          ],
        ],
      ),
    );
  }
}

/// ‹  October 2026  › inside the calendar card.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.onShift});

  final DateTime month;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, String tooltip, int by) => IconButton(
          tooltip: tooltip,
          onPressed: () => onShift(by),
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
            fixedSize: const Size.square(36),
            minimumSize: const Size.square(36),
            backgroundColor: AppColors.page,
            foregroundColor: AppColors.ink,
          ),
        );
    return Row(
      children: [
        arrow(Icons.chevron_left, tr('Previous month'), -1),
        Expanded(
          child: Text(
            _monthTitle.format(month),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
        arrow(Icons.chevron_right, tr('Next month'), 1),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final CalendarMonth data;
  final DateTime selected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final month = data.month;
    final firstWeekday = DateTime(month.year, month.month).weekday; // Mon=1
    final days = daysInMonth(month);

    return Column(
      children: [
        Row(
          children: [
            for (final d in weekdayLetters)
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            mainAxisExtent: 46,
          ),
          children: [
            for (var i = 1; i < firstWeekday; i++) const SizedBox(),
            for (var day = 1; day <= days; day++)
              _DayCell(
                date: DateTime(month.year, month.month, day),
                selected: selected.day == day,
                events: data.on(isoDate(DateTime(month.year, month.month, day))),
                onTap: onTap,
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.selected,
    required this.events,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final holiday = events.any((e) => e.kind == CalendarEventKind.holiday);
    final dots = <Color>{
      for (final e in events)
        if (_dotColor(e) case final color?) color,
    }.take(4).toList();
    final isFuture = date.isAfter(dateOnly(DateTime.now()));
    final background = selected
        ? AppColors.ink
        : holiday
            ? AppColors.warningSurface
            : null;
    final color = selected
        ? Colors.white
        : holiday
            ? AppColors.warningText
            : isFuture
                ? AppColors.faint
                : AppColors.ink;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: background ?? Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onTap(date),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${date.day}',
                style: AppText.tabular.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final dot in dots)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration:
                            BoxDecoration(color: dot, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 6,
      children: [
        LegendDot(color: AppColors.successFill, label: tr('Money in')),
        LegendDot(color: AppColors.dangerFill, label: tr('Money out')),
        LegendDot(color: AppColors.primary, label: tr('Bill / quote')),
        LegendDot(color: AppColors.amber500, label: tr('Holiday')),
      ],
    );
  }
}

/// "Fri, 17 Oct" and that day's attendance; tap to open the attendance.
class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.date, required this.attendance});

  final DateTime date;
  final DayAttendance? attendance;

  @override
  Widget build(BuildContext context) {
    final att = attendance;
    final canMark = !date.isAfter(dateOnly(DateTime.now()));
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.small),
      onTap: canMark ? () => context.go(Routes.attendance(date)) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                _dayHeading.format(date),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              att == null || att.isEmpty
                  ? tr('Not marked')
                  : tr('Present {present} · Half {half} · Absent {absent}', {
                      'present': att.present,
                      'half': att.half,
                      'absent': att.absent,
                    }),
              style: AppText.tabular.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayEvents extends StatelessWidget {
  const _DayEvents({required this.events});

  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          tr('No bills, payments or expenses on this day'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: AppColors.muted),
        ),
      );
    }
    return CardList(children: [for (final e in events) _EventRow(event: e)]);
  }
}

/// One entry: coloured icon tile, title, detail and the signed amount.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = eventStyle(event.kind);
    final amount = event.amountPaise;
    final route = event.route;
    final amountColor = switch (event.flow) {
      MoneyFlow.incoming => AppColors.successText,
      MoneyFlow.outgoing => AppColors.dangerText,
      MoneyFlow.none => AppColors.ink,
    };
    return InkWell(
      onTap: route == null ? null : () => context.push(route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconTile(icon,
                size: 36, color: color.withAlpha(28), iconColor: color),
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
                      maxLines: 2,
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
                formatPaise(amount),
                style: AppText.tabular.copyWith(
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
