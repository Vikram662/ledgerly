import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/pdf/pdf_common.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../lock/app_lock_controller.dart';
import '../data/attendance_repository.dart';
import '../domain/attendance_register_pdf.dart';
import 'daily_attendance_screen.dart';
import 'month_register_view.dart';

/// Attendance tab: "Mark today" to mark, "Month register" for every
/// worker's calendar. The header button picks a day, or shares the
/// register PDF on the month view.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key, this.date, this.showMonth = false});

  /// Day to open in "Today" view (from links like worker detail).
  final DateTime? date;
  final bool showMonth;

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  late bool _month = widget.showMonth;

  /// Day chosen from the header calendar button; overrides [widget.date].
  DateTime? _picked;

  DateTime _registerMonth =
      DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void didUpdateWidget(AttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showMonth != oldWidget.showMonth) _month = widget.showMonth;
    if (widget.date != null && widget.date != oldWidget.date) {
      _month = false;
      _picked = null;
    }
  }

  Future<void> _chooseDate() async {
    final picked = await pickDate(
      context,
      initial: _picked ?? widget.date ?? DateTime.now(),
      last: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _picked = dateOnly(picked);
      _month = false;
    });
  }

  Future<void> _shareRegister() async {
    final month = _registerMonth;
    final register = await ref.read(
      monthRegisterProvider((year: month.year, month: month.month)).future,
    );
    final profile = await ref.read(businessProfileProvider.future);
    if (profile == null || !mounted) return;
    if (register.workers.isEmpty) {
      showMessage(context, tr('No workers this month'));
      return;
    }
    final bytes = await buildAttendanceRegisterPdf(register, profile);
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      await sharePdf(
        bytes,
        fileName: 'Attendance-${month.year}-${month.month}.pdf',
      );
    } finally {
      lock.suspendRelock = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: tabAppBar(
        tr('Attendance'),
        actions: [
          if (_month)
            AppIconButton(
              icon: Icons.picture_as_pdf_outlined,
              tooltip: tr('Share register PDF'),
              onPressed: _shareRegister,
            )
          else
            AppIconButton(
              icon: Icons.calendar_month_outlined,
              tooltip: tr('Choose date'),
              onPressed: _chooseDate,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: SegmentedTabs<bool>(
              value: _month,
              options: {
                false: tr('Mark today'),
                true: tr('Month register'),
              },
              onChanged: (value) => setState(() => _month = value),
            ),
          ),
          Expanded(
            child: _month
                ? MonthRegisterView(
                    month: _registerMonth,
                    onMonthChanged: (month) =>
                        setState(() => _registerMonth = month),
                  )
                : DailyAttendanceView(initialDate: _picked ?? widget.date),
          ),
        ],
      ),
    );
  }
}
