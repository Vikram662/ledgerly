import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../attendance/presentation/attendance_widgets.dart';
import '../../khata/data/khata_repository.dart';
import '../../khata/presentation/khata_widgets.dart';
import '../../lock/lock_screens.dart';
import '../data/workers_repository.dart';

/// PRD E2 Worker Detail: summary card, actions, calendar, entries.
class WorkerDetailScreen extends ConsumerWidget {
  const WorkerDetailScreen({super.key, required this.workerId});

  final String workerId;

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    WorkerListItem item,
  ) async {
    final active = item.worker.isActive;
    final ok = await confirmDialog(
      context,
      title: active ? tr('Mark as left?') : tr('Make active again?'),
      message: active
          ? tr('{name} will move to inactive workers. All records and the pending balance stay.', {'name': item.worker.name})
          : tr('{name} will show in attendance again.', {'name': item.worker.name}),
      confirmLabel: active ? tr('Mark as left') : tr('Make active'),
    );
    if (!ok) return;
    await ref.read(workersRepositoryProvider).setActive(workerId, !active);
  }

  Future<void> _reverseSettlement(
    BuildContext context,
    WidgetRef ref,
    String settlementId,
  ) async {
    final ok = await confirmDialog(
      context,
      title: tr('Reverse settlement?'),
      message: tr('The period will be unlocked so it can be corrected. Money already paid stays recorded as a payment.'),
      confirmLabel: tr('Reverse'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    if (!await confirmIdentity(context, reason: tr('Confirm to reverse'))) return;
    try {
      await ref.read(khataRepositoryProvider).reverseSettlement(settlementId);
      if (context.mounted) showMessage(context, tr('Settlement reversed'));
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(workerProvider(workerId));
    final item = itemAsync.valueOrNull;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: itemAsync.isLoading
            ? const ListSkeleton()
            : const NotFoundBody(),
      );
    }
    final worker = item.worker;
    final summary = ref.watch(workerSummaryProvider(workerId));
    final ledger = ref.watch(workerLedgerProvider(workerId)).valueOrNull ?? const [];
    final pieces = ref.watch(workerPieceWorkProvider(workerId)).valueOrNull ?? const [];
    final settlements =
        ref.watch(workerSettlementsProvider(workerId)).valueOrNull ?? const [];
    final latestLocked = settlements
        .where((s) => s.status == SettlementStatus.locked)
        .firstOrNull;

    final since = DateFormat('MMM yyyy', uiDateLocale)
        .format(parseIsoDate(worker.joinDate));
    final phone = worker.phone;

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (phone != null) ...[
            AppIconButton(
              icon: Icons.call_outlined,
              tooltip: tr('Call worker'),
              onPressed: () => launchUrl(Uri.parse('tel:$phone')),
            ),
            const SizedBox(width: 8),
          ],
          AppIconButton(
            icon: Icons.edit_outlined,
            tooltip: tr('Edit'),
            onPressed: () => context.push(Routes.editWorker(workerId)),
          ),
          PopupMenuButton<String>(
            tooltip: tr('More options'),
            onSelected: (value) {
              switch (value) {
                case 'wage':
                  context.push(Routes.changeWage(workerId));
                case 'active':
                  _toggleActive(context, ref, item);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'wage', child: Text(tr('Change wage'))),
              PopupMenuItem(
                value: 'active',
                child: Text(
                    worker.isActive ? tr('Mark as left') : tr('Make active')),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.track,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  twoInitials(worker.name),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worker.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.22,
                      ),
                    ),
                    Text(
                      [
                        if (item.roleName != null) item.roleName!,
                        wageLabel(item.wage),
                        tr('since {date}', {'date': since}),
                      ].join(' · '),
                      style: AppText.tabular.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                    if (phone != null)
                      Text(
                        formatIndianPhone(phone),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                    if (!worker.isActive)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: AppBadge(
                          tr('Inactive (left)'),
                          tone: BadgeTone.danger,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          summary.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) =>
                Text(tr('Could not calculate: {e}', {'e': errorText(e)})),
            data: (s) => WorkerSummaryCard(
              summary: s,
              onAdvance: () => context.push(Routes.ledgerEntry(
                  workerId: workerId, type: LedgerType.advance)),
              onSettle: () => context.push(Routes.settle(workerId)),
            ),
          ),
          const SizedBox(height: 14),
          ChipRow(
            children: [
                for (final (label, onTap) in [
                  (
                    tr('+ Piece work'),
                    () => context.push(Routes.pieceWork(workerId))
                  ),
                  (
                    tr('+ Bonus'),
                    () => context.push(Routes.ledgerEntry(
                        workerId: workerId, type: LedgerType.bonus))
                  ),
                  (
                    tr('− Deduction'),
                    () => context.push(Routes.ledgerEntry(
                        workerId: workerId, type: LedgerType.deduction))
                  ),
                  (
                    tr('Change wage'),
                    () => context.push(Routes.changeWage(workerId))
                  ),
                ])
                  AppChip(label: label, onTap: onTap),
            ],
          ),
          SectionLabel(tr('Attendance')),
          AttendanceCalendar(worker: worker),
          SectionLabel(tr('Khata entries')),
          if (ledger.isEmpty)
            Text(tr('No entries yet.'),
                style: TextStyle(color: AppColors.muted))
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final entry in ledger.take(20)) LedgerTile(item: entry),
                ],
              ),
            ),
          if (pieces.isNotEmpty) ...[
            SectionLabel(tr('Piece work')),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final p in pieces.take(20))
                    ListTile(
                      title: Text(p.work.description),
                      subtitle: Text(
                        '${dayFormat.format(parseIsoDate(p.work.date))} · '
                        '${formatMilli(p.work.qtyMilli)} ${p.unitCode ?? ''} × '
                        '${formatPaise(p.work.ratePaise)}'
                        '${p.work.settlementId != null ? ' · Settled' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(formatPaise(p.work.amountPaise),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (p.work.settlementId == null)
                            IconButton(
                              tooltip: tr('Delete'),
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final ok = await confirmDialog(
                                  context,
                                  title: tr('Delete this piece work?'),
                                  message: p.work.description,
                                  confirmLabel: tr('Delete'),
                                  destructive: true,
                                );
                                if (ok) {
                                  await ref
                                      .read(khataRepositoryProvider)
                                      .deletePieceWork(p.work.id);
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (settlements.isNotEmpty) ...[
            SectionLabel(tr('Settlements')),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final s in settlements)
                    ListTile(
                      title: Text(
                        '${dayFormat.format(parseIsoDate(s.periodFrom))} – '
                        '${dayFormat.format(parseIsoDate(s.periodTo))}',
                        style: s.status == SettlementStatus.reversed
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough)
                            : null,
                      ),
                      subtitle: Text(
                        tr('Paid {amount} · Carry forward {amount2}', {
                              'amount': formatPaise(s.paidPaise),
                              'amount2': formatPaise(s.carryForwardPaise),
                            }) +
                            (s.status == SettlementStatus.reversed
                                ? tr(' · Reversed')
                                : ''),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (s.status == SettlementStatus.locked)
                            IconButton(
                              tooltip: tr('Share pay slip'),
                              icon: const Icon(Icons.share),
                              onPressed: () => sharePayslip(
                                context,
                                ref,
                                worker: worker,
                                settlement: s,
                                roleName: item.roleName,
                              ),
                            ),
                          if (s.id == latestLocked?.id)
                            IconButton(
                              tooltip: tr('Reverse settlement'),
                              icon: const Icon(Icons.undo),
                              onPressed: () =>
                                  _reverseSettlement(context, ref, s.id),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
