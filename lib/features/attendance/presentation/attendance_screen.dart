import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/common.dart';
import 'daily_attendance_screen.dart';
import 'month_register_view.dart';

/// Attendance tab: "Mark today" to mark, "Month register" for every
/// worker's calendar.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, this.date, this.showMonth = false});

  /// Day to open in "Today" view (from links like worker detail).
  final DateTime? date;
  final bool showMonth;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late bool _month = widget.showMonth;

  @override
  void didUpdateWidget(AttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showMonth != oldWidget.showMonth) _month = widget.showMonth;
    if (widget.date != null && widget.date != oldWidget.date) _month = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: tabAppBar(tr('Attendance')),
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
                ? const MonthRegisterView()
                : DailyAttendanceView(initialDate: widget.date),
          ),
        ],
      ),
    );
  }
}
