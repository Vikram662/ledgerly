import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/pdf/pdf_common.dart';
import '../data/attendance_repository.dart';

/// Letters printed in the register. "H" instead of "½" so it prints with
/// the built-in font too.
String _mark(AttendanceStatus? status) => switch (status) {
      null => '',
      AttendanceStatus.present => 'P',
      AttendanceStatus.half => 'H',
      AttendanceStatus.absent => 'A',
      AttendanceStatus.leavePaid => 'PL',
      AttendanceStatus.leaveUnpaid => 'UL',
      AttendanceStatus.off => 'O',
    };

PdfColor? _fill(AttendanceStatus? status) => switch (status) {
      AttendanceStatus.present => PdfColor.fromInt(0xFFECFDF5),
      AttendanceStatus.half => PdfColor.fromInt(0xFFFFFBEB),
      AttendanceStatus.absent => PdfColor.fromInt(0xFFFFF1F2),
      AttendanceStatus.off => PdfColor.fromInt(0xFFEEF0F2),
      _ => null,
    };

/// Month attendance register (all workers × all days) as a PDF to share.
Future<Uint8List> buildAttendanceRegisterPdf(
  MonthRegister register,
  BusinessProfile profile,
) async {
  final logo = await pdfLogo(profile);
  final month = DateFormat('MMMM yyyy', 'en').format(register.month);
  final pdf = pw.Document(
    title: 'Attendance register $month',
    theme: await pdfTheme(),
  );
  const small = pw.TextStyle(fontSize: 7);
  final smallBold = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);
  final days = register.days;

  pw.Widget cell(String text, {pw.TextStyle? style, PdfColor? color}) =>
      pw.Container(
        color: color,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Text(text, style: style ?? small),
      );

  String total(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';

  pdf.addPage(
    pw.MultiPage(
      pageFormat: pdfPageFormat.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pdfBusinessHeader(profile, label: 'ATTENDANCE REGISTER', logo: logo),
        pw.SizedBox(height: 8),
        pw.Text(month, style: pdfBold),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pdfBorder,
          columnWidths: {
            0: const pw.FixedColumnWidth(90),
            for (var d = 1; d <= days; d++) d: const pw.FlexColumnWidth(1),
            days + 1: const pw.FixedColumnWidth(18),
            days + 2: const pw.FixedColumnWidth(18),
            days + 3: const pw.FixedColumnWidth(18),
            days + 4: const pw.FixedColumnWidth(26),
          },
          children: [
            pw.TableRow(children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text('Worker', style: smallBold),
              ),
              for (var d = 1; d <= days; d++) cell('$d', style: smallBold),
              cell('P', style: smallBold),
              cell('H', style: smallBold),
              cell('A', style: smallBold),
              cell('Days', style: smallBold),
            ]),
            for (final w in register.workers)
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(w.name, style: small, maxLines: 2),
                ),
                for (var d = 1; d <= days; d++)
                  cell(
                    _mark(register.marks[w.id]?[d]),
                    color: _fill(register.marks[w.id]?[d]),
                  ),
                cell('${register.count(w.id, AttendanceStatus.present)}'),
                cell('${register.count(w.id, AttendanceStatus.half)}'),
                cell('${register.count(w.id, AttendanceStatus.absent)}'),
                cell(total(register.paidDays(w.id)), style: smallBold),
              ]),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'P present · H half day · A absent · PL paid leave · '
          'UL unpaid leave · O weekly off. '
          'Days = present + half/2 + paid leave.',
          style: pdfSmall,
        ),
      ],
    ),
  );
  return pdf.save();
}
