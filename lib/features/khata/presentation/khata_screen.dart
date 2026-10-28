import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pickers.dart';
import '../../workers/data/workers_repository.dart';
import '../data/khata_repository.dart';
import 'khata_widgets.dart';

/// Khata tab (PRD E1): open balance per worker, and recent entries.
class KhataScreen extends StatefulWidget {
  const KhataScreen({super.key, this.tab});

  /// Sub-tab requested by a link (0 balances, 1 entries).
  final int? tab;

  @override
  State<KhataScreen> createState() => _KhataScreenState();
}

class _KhataScreenState extends State<KhataScreen> {
  late int _tab = (widget.tab ?? 0).clamp(0, 1);

  /// Month shown in Entries. Balances are per open period, not per month.
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final months = [
      for (var i = 0; i < 24; i++) DateTime(now.year, now.month - i),
    ];
    final picked = await showPickerSheet<DateTime>(
      context,
      title: tr('Month'),
      options: months,
      label: (m) => monthFormat.format(m),
      selected: _month,
    );
    if (picked != null) setState(() => _month = picked);
  }

  @override
  void didUpdateWidget(KhataScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tab = widget.tab;
    if (tab != null && tab != oldWidget.tab) _tab = tab.clamp(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: tabAppBar(
        tr('Khata'),
        actions: [
          if (_tab == 1) _MonthPill(month: _month, onTap: _pickMonth),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.amber500,
        foregroundColor: AppColors.ink,
        onPressed: () =>
            context.push(Routes.ledgerEntry(type: LedgerType.advance)),
        icon: const Icon(Icons.add),
        label: Text(tr('Advance')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          const _KhataHero(),
          const SizedBox(height: 14),
          SegmentedTabs<int>(
            value: _tab,
            options: {0: tr('Balances'), 1: tr('Entries')},
            onChanged: (tab) => setState(() => _tab = tab),
          ),
          const SizedBox(height: 14),
          if (_tab == 0) const _Balances() else _Entries(month: _month),
        ],
      ),
    );
  }
}

/// Dark card: net pending to workers, earned, advance / paid, to recover.
class _KhataHero extends ConsumerWidget {
  const _KhataHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(allWorkerBalancesProvider).valueOrNull;
    final type = ref.watch(userTypeProvider);
    final shop = type == UserType.shop;
    final personal = type.personalLike;
    int sum(int Function(WorkerBalance b) pick) =>
        balances?.fold<int>(0, (s, b) => s + pick(b)) ?? 0;
    final net = sum((b) => b.balancePaise);
    final earned = sum((b) => b.summary.result.earningPaise);
    final advance = sum((b) => b.summary.result.advancePaise);
    final recover = sum((b) => b.balancePaise < 0 ? -b.balancePaise : 0);

    Widget stat(String label, int value, [Color color = Colors.white]) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inputBorder,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  balances == null ? '…' : formatPaise(value),
                  style: AppText.tabular.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );

    return HeroPanel(
      label: personal
          ? tr('Net pending to people')
          : (shop ? tr('Net pending to staff') : tr('Net pending to workers')),
      value: balances == null ? '…' : formatPaise(net),
      footer: Row(
        children: [
          stat(tr('Earned'), earned),
          const SizedBox(width: 8),
          stat(tr('Advance / paid'), advance, AppColors.amberLogo),
          const SizedBox(width: 8),
          stat(tr('To recover'), recover),
        ],
      ),
    );
  }
}

class _Balances extends ConsumerWidget {
  const _Balances();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkersProvider).valueOrNull ?? const [];
    final inactive = ref.watch(inactiveWorkersProvider).valueOrNull ?? const [];
    final workers = [...active, ...inactive];
    if (workers.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_wallet,
        title: tr('No workers yet'),
        message: tr('Add workers to keep their khata.'),
        actionLabel: tr('Add worker'),
        onAction: () => context.push(Routes.addWorker),
      );
    }
    return CardList(
      children: [for (final w in workers) _BalanceTile(item: w)],
    );
  }
}

class _BalanceTile extends ConsumerWidget {
  const _BalanceTile({required this.item});

  final WorkerListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary =
        ref.watch(workerSummaryProvider(item.worker.id)).valueOrNull;
    final balance = summary?.balancePaise;
    final left = !item.worker.isActive;
    return InkWell(
      onTap: () => context.push(Routes.worker(item.worker.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            InitialsAvatar(item.worker.name, photo: item.worker.photoPath),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: item.worker.name,
                      children: [
                        if (left)
                          TextSpan(
                            text: ' · ${tr('Left')}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    summary == null
                        ? '…'
                        : tr('Earned {earned} · Adv {advance}', {
                            'earned': formatPaise(summary.result.earningPaise),
                            'advance': formatPaise(summary.result.advancePaise),
                          }),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.tabular.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (balance != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatPaise(balance.abs()),
                    style: AppText.tabular.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: balance > 0
                          ? AppColors.successText
                          : balance < 0
                              ? AppColors.dangerText
                              : AppColors.ink,
                    ),
                  ),
                  Text(
                    balance > 0
                        ? tr('to pay')
                        : balance < 0
                            ? tr('owes you')
                            : tr('clear'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// "October 2026 ▾" button in the header.
class _MonthPill extends StatelessWidget {
  const _MonthPill({required this.month, required this.onTap});

  final DateTime month;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.only(left: 14, right: 10),
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(monthFormat.format(month)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }
}

class _Entries extends ConsumerWidget {
  const _Entries({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(
      monthLedgerProvider((year: month.year, month: month.month)),
    );
    return entries.when(
      loading: () => const ListSkeleton(),
      error: (e, _) => Center(child: Text(errorText(e))),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.receipt,
              title: tr('No entries this month'),
              message: tr('Advances, bonuses and payments show here.'),
              actionLabel: tr('Add advance'),
              onAction: () =>
                  context.push(Routes.ledgerEntry(type: LedgerType.advance)),
            )
          : CardList(
              children: [
                for (final item in list)
                  LedgerTile(item: item, showWorker: true),
              ],
            ),
    );
  }
}
