import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/amount_pad.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/loans_repository.dart';
import '../domain/loan_calculator.dart';
import 'loan_widgets.dart';

/// One loan: what is owed today, the agreed terms, the deal's profit and
/// every payment (split into interest and principal).
class LoanDetailScreen extends ConsumerWidget {
  const LoanDetailScreen({super.key, required this.loanId});

  final String loanId;

  Future<void> _close(BuildContext context, WidgetRef ref, LoanView v) async {
    final left = v.statement.balancePaise;
    final ok = await confirmDialog(
      context,
      title: tr('Close this loan?'),
      message: left > 0
          ? tr('Interest stops today. {amount} still owed will be written off.',
              {'amount': formatPaise(left)})
          : tr('Interest stops today.'),
      confirmLabel: tr('Close loan'),
      destructive: left > 0,
    );
    if (ok) {
      await ref.read(loansRepositoryProvider).closeLoan(v.loan.id, DateTime.now());
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, LoanView v) async {
    final ok = await confirmDialog(
      context,
      title: tr('Delete this loan?'),
      message: tr('The loan and its {count} payments are deleted.',
          {'count': v.payments.length}),
      confirmLabel: tr('Delete'),
      destructive: true,
    );
    if (!ok) return;
    await ref.read(loansRepositoryProvider).deleteLoan(v.loan.id);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(loanViewProvider(loanId));
    final v = async.valueOrNull;
    if (v == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading ? const ListSkeleton() : const NotFoundBody(),
      );
    }
    final loan = v.loan;
    final s = v.statement;
    final phone = v.party.phone;
    final badge = loanStatusBadge(v);
    const grey = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.muted,
    );

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (phone != null) ...[
            AppIconButton(
              icon: Icons.call_outlined,
              tooltip: tr('Call'),
              onPressed: () => launchUrl(Uri.parse('tel:$phone')),
            ),
            const SizedBox(width: 8),
          ],
          AppIconButton(
            icon: Icons.share_outlined,
            tooltip: tr('Share statement'),
            onPressed: () => shareLoanStatement(ref, v),
          ),
          PopupMenuButton<String>(
            onSelected: (action) => switch (action) {
              'edit' => context.push(Routes.editLoan(loan.id)),
              'close' => _close(context, ref, v),
              'reopen' => ref.read(loansRepositoryProvider).reopenLoan(loan.id),
              _ => _delete(context, ref, v),
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'edit', child: Text(tr('Edit loan'))),
              if (v.open)
                PopupMenuItem(value: 'close', child: Text(tr('Close loan')))
              else
                PopupMenuItem(value: 'reopen', child: Text(tr('Reopen loan'))),
              PopupMenuItem(
                value: 'delete',
                child: Text(tr('Delete'),
                    style: const TextStyle(color: AppColors.dangerText)),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: v.open
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        v.given ? AppColors.successFill : AppColors.primary,
                  ),
                  onPressed: () => context.push(Routes.loanPayment(loan.id)),
                  child: Text(v.given
                      ? tr('+ Payment received')
                      : tr('+ Payment made')),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          InkWell(
            onTap: () => context.push(Routes.loanParty(v.party.id)),
            child: Text(
              v.party.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppBadge(
                v.given ? tr('Given') : tr('Taken'),
                tone: v.given ? BadgeTone.info : BadgeTone.pro,
              ),
              if (badge != null) badge,
              if (phone != null) Text(formatIndianPhone(phone), style: grey),
            ],
          ),
          const SizedBox(height: 14),
          Panel(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FigureColumn(
                        label: v.given ? tr('To get today') : tr('To pay today'),
                        value: formatPaise(s.balancePaise),
                        color: s.overdueDays > 0
                            ? AppColors.dangerText
                            : AppColors.ink,
                      ),
                    ),
                    Expanded(
                      child: FigureColumn(
                        label: tr('Interest so far'),
                        value: formatPaise(s.interestAccruedPaise),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FigureColumn(
                        label: tr('Principal left'),
                        value: formatPaise(s.closed ? 0 : s.principalLeftPaise),
                      ),
                    ),
                    Expanded(
                      child: FigureColumn(
                        label: v.given ? tr('Received') : tr('Paid'),
                        value: formatPaise(s.paidPaise),
                        color: AppColors.successText,
                      ),
                    ),
                  ],
                ),
                if (s.writtenOffPaise > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    tr('{amount} written off when closed',
                        {'amount': formatPaise(s.writtenOffPaise)}),
                    style: grey.copyWith(color: AppColors.dangerText),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionLabel(tr('Terms')),
          CardList(
            children: [
              _TermRow(
                label: v.given ? tr('Given') : tr('Taken'),
                value:
                    '${formatPaise(loan.principalPaise)} · ${dayFormat.format(parseIsoDate(loan.startDate))}',
              ),
              _TermRow(
                label: tr('Interest'),
                value:
                    '${rateLabel(loan)} · ${termLabel(loan.termCount, loan.period)}',
              ),
              _TermRow(
                label: tr('Due on'),
                value: dayFormat.format(parseIsoDate(loan.dueDate)),
              ),
              _TermRow(
                label: v.given ? tr('To get back on due date') : tr('To pay back on due date'),
                value: formatPaise(v.terms.termTotalPaise),
              ),
              if (loan.note != null && loan.note!.isNotEmpty)
                _TermRow(label: tr('Note'), value: loan.note!),
            ],
          ),
          if (v.source != null && v.dealCostPaise != null) ...[
            const SizedBox(height: 12),
            SectionLabel(tr('Deal profit')),
            _DealPanel(view: v),
          ],
          const SizedBox(height: 12),
          SectionLabel(tr('Payments')),
          if (v.payments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(tr('No payments yet.'),
                  textAlign: TextAlign.center, style: grey),
            )
          else
            CardList(
              children: [
                for (final p in v.payments)
                  _PaymentRow(
                    payment: p,
                    split: s.splits
                        .where((x) => x.paymentId == p.id)
                        .firstOrNull,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TermRow extends StatelessWidget {
  const _TermRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: AppColors.muted)),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: AppText.tabular.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// Interest earned − what the source money cost = this deal's profit.
class _DealPanel extends StatelessWidget {
  const _DealPanel({required this.view});

  final LoanView view;

  @override
  Widget build(BuildContext context) {
    final source = view.source!;
    final profit = view.dealProfitPaise!;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Money from {name} at {rate}', {
              'name': source.party.name,
              'rate': rateLabel(source.loan),
            }),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FigureColumn(
                  label: tr('Interest earned'),
                  value: formatPaise(view.statement.interestAccruedPaise),
                  color: AppColors.successText,
                ),
              ),
              Expanded(
                child: FigureColumn(
                  label: tr('Money cost'),
                  value: formatPaise(view.dealCostPaise!),
                  color: AppColors.dangerText,
                ),
              ),
              Expanded(
                child: FigureColumn(
                  label: tr('Profit'),
                  value: formatPaise(profit),
                  color: profit >= 0 ? AppColors.successText : AppColors.dangerText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ₹ row: amount, how much went to interest and to principal; long-press
/// to delete.
class _PaymentRow extends ConsumerWidget {
  const _PaymentRow({required this.payment, this.split});

  final LoanPayment payment;
  final PaymentSplit? split;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = payment;
    final parts = [
      if (split != null && split!.interestPaise > 0)
        tr('Interest {amount}', {'amount': formatPaise(split!.interestPaise)}),
      if (split != null && split!.principalPaise > 0)
        tr('Principal {amount}', {'amount': formatPaise(split!.principalPaise)}),
      if (split != null && split!.extraPaise > 0)
        tr('Extra {amount}', {'amount': formatPaise(split!.extraPaise)}),
    ];
    return ListTile(
      leading: const LetterTag(
        '₹',
        color: AppColors.successSurface,
        textColor: AppColors.successText,
      ),
      title: Text(
        [dayFormat.format(parseIsoDate(p.date)), paymentModeLabel(p.mode)]
            .join(' · '),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text([
        ...parts,
        if (p.note != null && p.note!.isNotEmpty) p.note!,
      ].join(' · ')),
      trailing: Text(
        formatPaise(p.amountPaise),
        style: AppText.tabular.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.successText,
        ),
      ),
      onLongPress: () async {
        final ok = await confirmDialog(
          context,
          title: tr('Delete this entry?'),
          message: formatPaise(p.amountPaise),
          confirmLabel: tr('Delete'),
          destructive: true,
        );
        if (ok) await ref.read(loansRepositoryProvider).deletePayment(p.id);
      },
    );
  }
}

/// Money received on a given loan, or paid on a taken loan. Chips fill in
/// the full amount owed or just the interest.
class LoanPaymentScreen extends ConsumerStatefulWidget {
  const LoanPaymentScreen({super.key, required this.loanId});

  final String loanId;

  @override
  ConsumerState<LoanPaymentScreen> createState() => _LoanPaymentScreenState();
}

class _LoanPaymentScreenState extends ConsumerState<LoanPaymentScreen> {
  String _amount = '';
  PaymentMode _mode = PaymentMode.cash;
  DateTime _date = dateOnly(DateTime.now());
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final paise = parseRupeesToPaise(_amount);
    if (paise == null || paise <= 0) {
      showMessage(context, tr('Enter the amount'));
      return;
    }
    setState(() => _saving = true);
    await ref.read(loansRepositoryProvider).addPayment(
          loanId: widget.loanId,
          date: _date,
          amountPaise: paise,
          mode: _mode,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        );
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    showMessage(context, tr('✓ Payment saved'));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(loanViewProvider(widget.loanId)).valueOrNull;
    final paise = parseRupeesToPaise(_amount) ?? 0;
    // What is owed on the chosen date, for the quick-fill chips.
    final owed = v == null
        ? null
        : computeStatement(
            v.terms,
            [
              for (final p in v.payments)
                LoanPaymentInput(
                  id: p.id,
                  date: parseIsoDate(p.date),
                  amountPaise: p.amountPaise,
                ),
            ],
            asOf: _date,
          );
    return Scaffold(
      appBar: AppBar(title: Text(v?.party.name ?? tr('Payment'))),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              children: [
                if (owed != null && owed.balancePaise > 0)
                  ChipRow(
                    children: [
                      AppChip(
                        label: tr('Full {amount}',
                            {'amount': formatPaise(owed.balancePaise)}),
                        selected: paise == owed.balancePaise,
                        onTap: () => setState(() =>
                            _amount = paiseToInputText(owed.balancePaise)),
                      ),
                      if (owed.interestOwedPaise > 0)
                        AppChip(
                          label: tr('Interest only {amount}',
                              {'amount': formatPaise(owed.interestOwedPaise)}),
                          selected: paise == owed.interestOwedPaise,
                          onTap: () => setState(() => _amount =
                              paiseToInputText(owed.interestOwedPaise)),
                        ),
                    ],
                  ),
                AmountDisplay(
                  text: _amount,
                  label: v?.given == false ? tr('Amount paid') : tr('Amount received'),
                ),
                SectionLabel(tr('Mode')),
                PaymentModeChips(
                  value: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
                const SizedBox(height: 12),
                NoteDateField(
                  controller: _note,
                  dateLabel: dayButtonLabel(_date),
                  onPickDate: () async {
                    final picked = await pickDate(context,
                        initial: _date, last: DateTime.now());
                    if (picked != null) setState(() => _date = dateOnly(picked));
                  },
                ),
              ],
            ),
          ),
          AmountPadFooter(
            value: _amount,
            onChanged: (value) => setState(() => _amount = value),
            saving: _saving,
            onSave: _save,
            saveLabel: paise > 0
                ? tr('Save {amount}', {'amount': formatPaise(paise)})
                : tr('Save'),
          ),
        ],
      ),
    );
  }
}
