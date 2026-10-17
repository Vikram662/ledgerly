import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/pdf/pdf_common.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../lock/app_lock_controller.dart';
import '../data/khata_repository.dart';
import '../domain/payslip_pdf.dart';

String ledgerTypeLabel(LedgerType type) => switch (type) {
      LedgerType.advance => tr('Advance'),
      LedgerType.payment => tr('Payment'),
      LedgerType.bonus => tr('Bonus'),
      LedgerType.deduction => tr('Deduction'),
      LedgerType.emi => 'EMI',
      LedgerType.reversal => tr('Reversal'),
      LedgerType.carryForward => tr('Carry forward'),
    };

IconData ledgerTypeIcon(LedgerType type) => switch (type) {
      LedgerType.advance => Icons.payments_outlined,
      LedgerType.payment => Icons.north_east,
      LedgerType.bonus => Icons.card_giftcard,
      LedgerType.deduction => Icons.remove_circle_outline,
      LedgerType.emi => Icons.event_repeat,
      LedgerType.reversal => Icons.undo,
      LedgerType.carryForward => Icons.redo,
    };

/// PRD KH-03 worker summary card: open period, balance, days, earned,
/// advance, then Advance and Settle buttons.
class WorkerSummaryCard extends StatelessWidget {
  const WorkerSummaryCard({
    super.key,
    required this.summary,
    this.onAdvance,
    this.onSettle,
  });

  final WorkerSummary summary;
  final VoidCallback? onAdvance;
  final VoidCallback? onSettle;

  @override
  Widget build(BuildContext context) {
    final r = summary.result;
    final balance = summary.balancePaise;
    final counts = summary.counts;
    const label = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.muted,
    );
    final value =
        AppText.tabular.copyWith(fontSize: 16, fontWeight: FontWeight.w800);

    Widget stat(String name, String text, [Color? color]) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: label),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(text, style: value.copyWith(color: color)),
              ),
            ],
          ),
        );

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Since {date}',
                      {'date': dayFormat.format(summary.periodFrom)}),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ),
              TagBadge(
                tr('Open period'),
                color: AppColors.successSurface,
                textColor: AppColors.successText,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            balance >= 0 ? tr('Balance to pay') : tr('Worker owes'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
          Text(
            formatPaise(balance.abs()),
            style: AppText.tabular.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.64,
              color: balance >= 0 ? AppColors.successText : AppColors.dangerText,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              stat(tr('Days'), _days(r.paidDays)),
              const SizedBox(width: 8),
              stat(tr('Earned'), formatPaise(r.earningPaise)),
              const SizedBox(width: 8),
              stat(tr('Advance'), formatPaise(r.advancePaise),
                  AppColors.warningText),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [
              tr('P {present} · ½ {half} · A {absent}', {
                'present': counts.present,
                'half': counts.half,
                'absent': counts.absent,
              }),
              if (counts.off > 0) tr('Off {count}', {'count': counts.off}),
              if (r.piecePaise > 0)
                tr('Piece {amount}', {'amount': formatPaise(r.piecePaise)}),
              if (r.otPaise > 0)
                tr('OT {amount}', {'amount': formatPaise(r.otPaise)}),
              if (r.previousBalancePaise != 0)
                tr('Previous {amount}',
                    {'amount': formatPaise(r.previousBalancePaise)}),
            ].join(' · '),
            style: AppText.tabular.merge(label),
          ),
          if (onAdvance != null || onSettle != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (onAdvance != null)
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.amber500,
                        foregroundColor: AppColors.ink,
                        minimumSize: const Size(0, AppSizes.tapSecondary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                        ),
                      ),
                      onPressed: onAdvance,
                      icon: const Icon(Icons.add),
                      label: Text(tr('Advance')),
                    ),
                  ),
                if (onAdvance != null && onSettle != null)
                  const SizedBox(width: 8),
                if (onSettle != null)
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.ink,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, AppSizes.tapSecondary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                        ),
                      ),
                      onPressed: onSettle,
                      child: FittedBox(
                        child: Text(balance > 0
                            ? tr('Settle {amount}',
                                {'amount': formatPaise(balance)})
                            : tr('Settle')),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _days(double days) =>
      days == days.roundToDouble() ? '${days.toInt()}' : days.toStringAsFixed(1);
}

/// One khata entry. Long press offers Reverse (PRD KH-02).
class LedgerTile extends ConsumerWidget {
  const LedgerTile({super.key, required this.item, this.showWorker = false});

  final LedgerItem item;
  final bool showWorker;

  Future<void> _reverse(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: tr('Reverse this entry?'),
      message:
          tr('{entryType} of {amount} will be cancelled with a reversal entry. The original stays in the record.', {'entryType': ledgerTypeLabel(item.entry.entryType), 'amount': formatPaise(item.entry.amountPaise)}),
      confirmLabel: tr('Reverse'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(khataRepositoryProvider).reverseEntry(item.entry.id);
      if (context.mounted) showMessage(context, tr('Entry reversed'));
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = item.entry;
    final type = entry.entryType;
    final isMoneyOut = type == LedgerType.advance || type == LedgerType.payment;
    final canReverse = !item.reversed &&
        type != LedgerType.reversal &&
        !(type == LedgerType.payment && entry.refId != null);
    final title = showWorker
        ? '${item.workerName} · ${ledgerTypeLabel(type)}'
        : ledgerTypeLabel(type);
    final subtitle = [
      dayTimeFormat.format(item.at),
      if (entry.mode != null) paymentModeLabel(entry.mode!),
      if (entry.remarks != null && entry.remarks!.isNotEmpty) entry.remarks!,
    ].join(' · ');

    return ListTile(
      minVerticalPadding: 12,
      leading: IconTile(
        ledgerTypeIcon(type),
        color: isMoneyOut ? AppColors.amber100 : AppColors.page,
        iconColor: isMoneyOut ? AppColors.warningText : AppColors.inkSoft,
      ),
      title: Text(
        title,
        style: item.reversed
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(item.reversed
          ? tr('Reversed · {details}', {'details': subtitle})
          : subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${isMoneyOut ? '−' : type == LedgerType.bonus ? '+' : ''}'
            '${formatPaise(entry.amountPaise)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: item.reversed
                  ? AppColors.muted
                  : isMoneyOut
                      ? AppColors.warningText
                      : AppColors.slate900,
            ),
          ),
          if (canReverse)
            IconButton(
              tooltip: tr('Reverse'),
              icon: const Icon(Icons.undo),
              onPressed: () => _reverse(context, ref),
            ),
        ],
      ),
    );
  }
}

/// Builds and shares the pay-slip PDF for a settlement (PRD KH-09).
Future<void> sharePayslip(
  BuildContext context,
  WidgetRef ref, {
  required Worker worker,
  required Settlement settlement,
  String? roleName,
}) async {
  final profile = await ref.read(businessProfileProvider.future);
  if (profile == null) return;
  final bytes = await buildPayslipPdf(
    profile: profile,
    worker: worker,
    settlement: settlement,
    roleName: roleName,
  );
  final lock = ref.read(appLockProvider);
  lock.suspendRelock = true;
  try {
    await sharePdf(
      bytes,
      fileName: 'Payslip-${worker.name}-${settlement.periodTo}.pdf',
      text: tr('Pay slip for {name}', {'name': worker.name}),
    );
  } finally {
    lock.suspendRelock = false;
  }
}
