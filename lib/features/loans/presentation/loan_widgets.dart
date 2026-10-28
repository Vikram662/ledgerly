import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/decimal.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../lock/app_lock_controller.dart';
import '../data/loans_repository.dart';

String periodLabel(LoanPeriod period) =>
    period == LoanPeriod.day ? tr('day') : tr('month');

/// "₹400 / day" or "2% / month".
String rateLabel(Loan loan) => rateText(loan.rateKind, loan.rateValue, loan.period);

String rateText(LoanRateKind kind, int value, LoanPeriod period) {
  final amount = kind == LoanRateKind.fixed
      ? formatPaise(value)
      : '${formatScaled(value, 2)}%';
  return '$amount / ${periodLabel(period)}';
}

/// "5 days" or "2 months".
String termLabel(int count, LoanPeriod period) => period == LoanPeriod.day
    ? trPlural(count, '1 day', '{count} days')
    : trPlural(count, '1 month', '{count} months');

/// Closed, overdue, due today or nothing.
Widget? loanStatusBadge(LoanView v) {
  if (!v.open) {
    return v.statement.writtenOffPaise > 0
        ? AppBadge(tr('Closed · written off'))
        : AppBadge(tr('Paid up'), tone: BadgeTone.success);
  }
  final late = v.statement.overdueDays;
  if (late > 0) {
    return AppBadge(
      trPlural(late, '1 day late', '{count} days late'),
      tone: BadgeTone.danger,
    );
  }
  if (v.dueOn(DateTime.now())) {
    return AppBadge(tr('Due today'), tone: BadgeTone.warning);
  }
  return null;
}

/// One loan in a list: person, amount and rate, balance and status.
class LoanTile extends StatelessWidget {
  const LoanTile({super.key, required this.view, this.showParty = true});

  final LoanView view;
  final bool showParty;

  @override
  Widget build(BuildContext context) {
    final loan = view.loan;
    final badge = loanStatusBadge(view);
    final title = showParty
        ? view.party.name
        : (view.given ? tr('Loan given') : tr('Loan taken'));
    return ListTile(
      leading: InitialsAvatar(view.party.name),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text([
        formatPaise(loan.principalPaise),
        rateLabel(loan),
        tr('due {date}', {'date': dayFormat.format(parseIsoDate(loan.dueDate))}),
      ].join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatPaise(view.open
                ? view.statement.balancePaise
                : view.statement.paidPaise),
            style: AppText.tabular.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: view.statement.overdueDays > 0
                  ? AppColors.dangerText
                  : AppColors.ink,
            ),
          ),
          if (badge != null) ...[const SizedBox(height: 2), badge],
        ],
      ),
      onTap: () => context.push(Routes.loan(loan.id)),
    );
  }
}

/// Sends the loan's statement (amount, rate, interest, paid, balance) by
/// WhatsApp or any app.
Future<void> shareLoanStatement(WidgetRef ref, LoanView v) async {
  final profile = await ref.read(businessProfileProvider.future);
  final loan = v.loan;
  final s = v.statement;
  final lines = [
    tr('Loan statement: {name}', {'name': v.party.name}),
    v.given
        ? tr('Given: {amount} on {date}', {
            'amount': formatPaise(loan.principalPaise),
            'date': dayFormat.format(parseIsoDate(loan.startDate)),
          })
        : tr('Taken: {amount} on {date}', {
            'amount': formatPaise(loan.principalPaise),
            'date': dayFormat.format(parseIsoDate(loan.startDate)),
          }),
    tr('Interest: {rate} · Due {date}', {
      'rate': rateLabel(loan),
      'date': dayFormat.format(parseIsoDate(loan.dueDate)),
    }),
    tr('Interest so far: {amount}',
        {'amount': formatPaise(s.interestAccruedPaise)}),
    tr('Paid: {amount}', {'amount': formatPaise(s.paidPaise)}),
    tr('Balance today: {amount}', {'amount': formatPaise(s.balancePaise)}),
    if (profile != null && profile.name.isNotEmpty) '— ${profile.name}',
  ];
  final lock = ref.read(appLockProvider);
  lock.suspendRelock = true;
  try {
    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  } finally {
    lock.suspendRelock = false;
  }
}
