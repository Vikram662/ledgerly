import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/db/database.dart';
import '../../../core/pdf/pdf_common.dart';
import '../../../core/utils/dates.dart';
import '../data/billing_repository.dart';

/// Unpaid bills statement: every open bill with what is still due, oldest
/// first, as a PDF to keep or share.
Future<Uint8List> buildStatementPdf(
  List<DocumentListItem> bills,
  BusinessProfile profile,
) async {
  final logo = await pdfLogo(profile);
  final pdf = pw.Document(
    title: 'Bills statement',
    theme: await pdfTheme(),
  );
  final now = DateFormat('d MMM yyyy, h:mm a', 'en').format(DateTime.now());
  final dateFormat = DateFormat('d MMM yyyy', 'en');
  String day(String iso) => dateFormat.format(parseIsoDate(iso));
  final sorted = [...bills]
    ..sort((a, b) => a.document.date.compareTo(b.document.date));
  final total = sorted.fold<int>(0, (sum, b) => sum + b.document.totalPaise);
  final received = sorted.fold<int>(0, (sum, b) => sum + b.paidPaise);
  final balance = sorted.fold<int>(0, (sum, b) => sum + b.balancePaise);

  pdf.addPage(
    pw.MultiPage(
      pageFormat: pdfPageFormat,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pdfBusinessHeader(profile, label: 'STATEMENT', logo: logo),
        pw.SizedBox(height: 8),
        pw.Text('Unpaid bills as on $now', style: pdfSmall),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pdfBorder,
          columnWidths: const {
            0: pw.FlexColumnWidth(1.4),
            1: pw.FlexColumnWidth(3),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(2),
            4: pw.FlexColumnWidth(2),
            5: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(children: [
              pdfCell('Bill', bold: true),
              pdfCell('Client', bold: true),
              pdfCell('Date', bold: true),
              pdfCell('Due', bold: true),
              pdfCell('Amount', bold: true, align: pw.TextAlign.right),
              pdfCell('Balance', bold: true, align: pw.TextAlign.right),
            ]),
            for (final b in sorted)
              pw.TableRow(children: [
                pdfCell(b.document.number),
                pdfCell(b.clientName),
                pdfCell(day(b.document.date)),
                pdfCell(b.document.dueDate == null
                    ? '-'
                    : day(b.document.dueDate!)),
                pdfCell(pdfMoney(b.document.totalPaise),
                    align: pw.TextAlign.right),
                pdfCell(pdfMoney(b.balancePaise), align: pw.TextAlign.right),
              ]),
          ],
        ),
        pw.SizedBox(height: 8),
        pdfTotalRow('Billed', pdfMoney(total)),
        pdfTotalRow('Received', pdfMoney(received)),
        pdfTotalRow('Balance due', pdfMoney(balance), bold: true),
      ],
    ),
  );
  return pdf.save();
}
