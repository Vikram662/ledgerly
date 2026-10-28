import 'dart:math' as math;

import '../../../core/db/enums.dart';
import '../../../core/utils/dates.dart';

/// Whole days from [from] to [to] (calendar days, DST safe).
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// [start] plus [count] days or months. A month step keeps the day of the
/// month, or the month's last day (31 Jan + 1 month = 28/29 Feb).
DateTime addPeriods(DateTime start, int count, LoanPeriod period) {
  if (period == LoanPeriod.day) {
    return DateTime(start.year, start.month, start.day + count);
  }
  final first = DateTime(start.year, start.month + count);
  return DateTime(
      first.year, first.month, math.min(start.day, daysInMonth(first)));
}

/// Periods from [from] to [to]: days, or whole months plus the days left
/// as a share of 30 (a month and 15 days = 1.5 months).
double periodsBetween(DateTime from, DateTime to, LoanPeriod period) {
  if (!to.isAfter(from)) return 0;
  if (period == LoanPeriod.day) return daysBetween(from, to).toDouble();
  var months = (to.year - from.year) * 12 + to.month - from.month;
  while (months > 0 && addPeriods(from, months, period).isAfter(to)) {
    months--;
  }
  return months + daysBetween(addPeriods(from, months, period), to) / 30;
}

/// The terms of a loan (a saved loan or the form being filled in).
class LoanTerms {
  const LoanTerms({
    required this.principalPaise,
    required this.start,
    required this.termCount,
    required this.period,
    required this.rateKind,
    required this.rateValue,
  });

  final int principalPaise;
  final DateTime start;
  final int termCount;
  final LoanPeriod period;
  final LoanRateKind rateKind;

  /// Paise per period on the whole principal, or basis points per period.
  final int rateValue;

  DateTime get dueDate => addPeriods(start, termCount, period);

  /// Interest for one period on [outstandingPaise]. A fixed rate is set on
  /// the whole principal, so after part of it is paid back the rate goes
  /// down in step (₹400 a day on ₹1 lakh is ₹200 a day on ₹50,000).
  double perPeriod(int outstandingPaise) => switch (rateKind) {
        LoanRateKind.fixed => principalPaise == 0
            ? 0
            : rateValue * outstandingPaise / principalPaise,
        LoanRateKind.percent => outstandingPaise * rateValue / 10000,
      };

  /// Interest for the agreed term: ₹1 lakh, 5 days, ₹400 a day → ₹2,000.
  int get termInterestPaise => (perPeriod(principalPaise) * termCount).round();

  /// Amount to get back (or pay back) on the due date.
  int get termTotalPaise => principalPaise + termInterestPaise;

  int interestPaise(int outstandingPaise, DateTime from, DateTime to) =>
      (perPeriod(outstandingPaise) * periodsBetween(from, to, period)).round();
}

/// A payment received (given loan) or paid (taken loan).
class LoanPaymentInput {
  const LoanPaymentInput({
    required this.id,
    required this.date,
    required this.amountPaise,
  });

  final String id;
  final DateTime date;
  final int amountPaise;
}

/// How one payment was used: interest first, then principal.
class PaymentSplit {
  const PaymentSplit({
    required this.paymentId,
    required this.date,
    required this.interestPaise,
    required this.principalPaise,
    required this.extraPaise,
  });

  final String paymentId;
  final DateTime date;
  final int interestPaise;
  final int principalPaise;

  /// Paid beyond what was owed.
  final int extraPaise;
}

/// Where a loan stands on a day.
class LoanStatement {
  const LoanStatement({
    required this.dueDate,
    required this.principalLeftPaise,
    required this.interestOwedPaise,
    required this.interestAccruedPaise,
    required this.paidPaise,
    required this.interestPaidPaise,
    required this.extraPaise,
    required this.overdueDays,
    required this.closed,
    required this.splits,
  });

  final DateTime dueDate;
  final int principalLeftPaise;

  /// Interest run up and not paid yet.
  final int interestOwedPaise;

  /// All interest run up so far (paid or not).
  final int interestAccruedPaise;
  final int paidPaise;
  final int interestPaidPaise;
  final int extraPaise;

  /// Days past the due date with money still owed; 0 when not late.
  final int overdueDays;

  /// Closed by hand: interest stopped and the rest was written off.
  final bool closed;
  final List<PaymentSplit> splits;

  /// Still to get back / pay back today. 0 once closed.
  int get balancePaise =>
      closed ? 0 : principalLeftPaise + interestOwedPaise;

  /// Left unpaid when the loan was closed.
  int get writtenOffPaise =>
      closed ? principalLeftPaise + interestOwedPaise : 0;

  bool get settled => principalLeftPaise + interestOwedPaise <= 0;
}

/// Simple interest taken at the end, running on the principal still owed,
/// at the same rate after the due date until paid. Each payment clears
/// interest run up so far, then principal. A closed loan stops at
/// [closedOn].
LoanStatement computeStatement(
  LoanTerms terms,
  List<LoanPaymentInput> payments, {
  required DateTime asOf,
  DateTime? closedOn,
}) {
  final start = dateOnly(terms.start);
  var end = dateOnly(asOf);
  if (closedOn != null && closedOn.isBefore(end)) end = dateOnly(closedOn);
  if (end.isBefore(start)) end = start;

  var principalLeft = terms.principalPaise;
  var interestOwed = 0;
  var accrued = 0;
  var paid = 0;
  var interestPaid = 0;
  var extra = 0;
  var cursor = start;
  final splits = <PaymentSplit>[];
  final sorted = [...payments]..sort((a, b) => a.date.compareTo(b.date));

  void accrueTo(DateTime day) {
    final to = day.isBefore(start) ? start : (day.isAfter(end) ? end : day);
    if (!to.isAfter(cursor)) return;
    final interest = terms.interestPaise(principalLeft, cursor, to);
    interestOwed += interest;
    accrued += interest;
    cursor = to;
  }

  for (final payment in sorted) {
    accrueTo(dateOnly(payment.date));
    var amount = payment.amountPaise;
    paid += amount;
    final toInterest = math.min(amount, interestOwed);
    interestOwed -= toInterest;
    interestPaid += toInterest;
    amount -= toInterest;
    final toPrincipal = math.min(amount, principalLeft);
    principalLeft -= toPrincipal;
    amount -= toPrincipal;
    extra += amount;
    splits.add(PaymentSplit(
      paymentId: payment.id,
      date: dateOnly(payment.date),
      interestPaise: toInterest,
      principalPaise: toPrincipal,
      extraPaise: amount,
    ));
  }
  accrueTo(end);

  final closed = closedOn != null;
  final due = terms.dueDate;
  final owed = principalLeft + interestOwed > 0;
  return LoanStatement(
    dueDate: due,
    principalLeftPaise: principalLeft,
    interestOwedPaise: interestOwed,
    interestAccruedPaise: accrued,
    paidPaise: paid,
    interestPaidPaise: interestPaid,
    extraPaise: extra,
    overdueDays:
        !closed && owed && end.isAfter(due) ? daysBetween(due, end) : 0,
    closed: closed,
    splits: splits,
  );
}

/// What the money of [source] (a taken loan) costs for a deal: its rate on
/// [given]'s principal, from the day it was lent until [end].
int dealCostPaise(LoanTerms given, LoanTerms source, DateTime end) {
  final perPeriod = switch (source.rateKind) {
    LoanRateKind.fixed => source.principalPaise == 0
        ? 0.0
        : source.rateValue * given.principalPaise / source.principalPaise,
    LoanRateKind.percent => given.principalPaise * source.rateValue / 10000,
  };
  return (perPeriod * periodsBetween(given.start, end, source.period)).round();
}
