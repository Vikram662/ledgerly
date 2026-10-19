import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/pdf/pdf_common.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/presentation/billing_widgets.dart';
import '../../expenses/data/expenses_repository.dart';
import '../../khata/data/khata_repository.dart';
import '../../lock/app_lock_controller.dart';
import '../domain/dues_pdf.dart';
import '../domain/dues_report.dart';

/// Combined Lena / Dena report from clients, bills and worker balances.
final duesReportProvider = Provider<AsyncValue<DuesReport>>((ref) {
  final clients = ref.watch(clientsProvider);
  final invoices = ref.watch(documentsProvider(DocumentKind.invoice));
  final workers = ref.watch(allWorkerBalancesProvider);
  final suppliers = ref.watch(suppliersProvider);
  for (final value in [clients, invoices, workers, suppliers]) {
    if (value.hasError) {
      return AsyncValue.error(
          value.error!, value.stackTrace ?? StackTrace.current);
    }
  }
  if (!clients.hasValue ||
      !invoices.hasValue ||
      !workers.hasValue ||
      !suppliers.hasValue) {
    return const AsyncValue.loading();
  }
  return AsyncValue.data(buildDuesReport(
    clients: clients.requireValue,
    invoices: invoices.requireValue,
    workers: workers.requireValue,
    suppliers: suppliers.requireValue,
  ));
});

/// Lena / Dena (wireframe Dues): two total tabs, then the parties of the
/// chosen side. Lena is green, Dena red, overdue red.
class DuesScreen extends ConsumerStatefulWidget {
  const DuesScreen({super.key, this.initialTab = 0});

  /// 0 = Lena, 1 = Dena.
  final int initialTab;

  @override
  ConsumerState<DuesScreen> createState() => _DuesScreenState();
}

class _DuesScreenState extends ConsumerState<DuesScreen> {
  late bool _receive = widget.initialTab == 0;

  Future<void> _sharePdf(DuesReport report) async {
    final profile = await ref.read(businessProfileProvider.future);
    if (profile == null) return;
    final bytes = await buildDuesPdf(report, profile);
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      await sharePdf(bytes, fileName: 'Lena-Dena-report.pdf');
    } finally {
      lock.suspendRelock = false;
    }
  }

  Future<void> _remind(DueItem item) => sharePaymentReminder(
        ref,
        name: item.name,
        amountPaise: item.amountPaise,
      );

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(duesReportProvider);
    final shop = ref.watch(userTypeProvider) == UserType.shop;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Lena / Dena')),
        actions: [
          AppIconButton(
            icon: Icons.ios_share,
            tooltip: tr('Share PDF'),
            onPressed:
                report.hasValue ? () => _sharePdf(report.requireValue) : null,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: report.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => Center(child: Text(errorText(e))),
        data: (r) {
          final items = _receive ? r.lena : r.dena;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TotalTab(
                    label: tr('Lena (to receive)'),
                    paise: r.lenaTotal,
                    color: AppColors.successText,
                    note: r.overdueTotal > 0
                        ? tr('{amount} overdue',
                            {'amount': formatPaise(r.overdueTotal)})
                        : null,
                    noteColor: AppColors.dangerText,
                    selected: _receive,
                    onTap: () => setState(() => _receive = true),
                  ),
                  const SizedBox(width: AppSizes.gap),
                  _TotalTab(
                    label: tr('Dena (to pay)'),
                    paise: r.denaTotal,
                    color: AppColors.dangerText,
                    note: shop
                        ? tr('Staff + suppliers')
                        : tr('Workers + suppliers'),
                    noteColor: AppColors.muted,
                    selected: !_receive,
                    onTap: () => setState(() => _receive = false),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                EmptyState(
                  icon: _receive ? Icons.call_received : Icons.call_made,
                  title:
                      _receive ? tr('Nothing to receive') : tr('Nothing to pay'),
                  message: _receive
                      ? tr('No client or worker owes you money right now.')
                      : tr('All workers and suppliers are paid up.'),
                )
              else ...[
                CardList(
                  children: [
                    for (final item in items)
                      _DueRow(
                        item: item,
                        receive: _receive,
                        onRemind: _receive && item.party == DueParty.client
                            ? () => _remind(item)
                            : null,
                      ),
                  ],
                ),
                if (_receive) ...[
                  const SizedBox(height: 12),
                  Text(
                    tr('Reminder opens WhatsApp with a ready message.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Lena or Dena total as a selectable tab (wireframe Dues `.tab`).
class _TotalTab extends StatelessWidget {
  const _TotalTab({
    required this.label,
    required this.paise,
    required this.color,
    required this.note,
    required this.noteColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int paise;
  final Color color;
  final String? note;
  final Color noteColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
      side: BorderSide(
        color: selected ? AppColors.ink : AppColors.border,
        width: selected ? 2 : 1,
      ),
    );
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: AppColors.surface,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                  Text(
                    formatPaise(paise),
                    style: AppText.tabular.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Text(
                    note ?? ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.tabular.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: noteColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One party: name, tags (party, overdue) and the amount, with "Send
/// reminder" for clients who owe money.
class _DueRow extends StatelessWidget {
  const _DueRow({
    required this.item,
    required this.receive,
    required this.onRemind,
  });

  final DueItem item;
  final bool receive;
  final VoidCallback? onRemind;

  @override
  Widget build(BuildContext context) {
    final party = dueParty(item.party).label;
    final tag = switch (item.party) {
      DueParty.worker when receive => tr('{party} · advance', {'party': party}),
      DueParty.client when !receive =>
        tr('{party} · advance received', {'party': party}),
      _ => party,
    };
    final amount = Text(
      formatPaise(item.amountPaise),
      style: AppText.tabular.copyWith(fontSize: 15, fontWeight: FontWeight.w800),
    );
    return InkWell(
      onTap: () => context.push(switch (item.party) {
        DueParty.client => Routes.client(item.id),
        DueParty.worker => Routes.worker(item.id),
        DueParty.supplier => Routes.supplier(item.id),
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      AppBadge(tag),
                      if (item.overduePaise > 0)
                        AppBadge(
                          tr('Overdue {amount}',
                              {'amount': formatPaise(item.overduePaise)}),
                          tone: BadgeTone.danger,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (onRemind == null)
              amount
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  amount,
                  const SizedBox(height: 6),
                  MiniButton(label: tr('Send reminder'), onTap: onRemind),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

({String label, IconData icon}) dueParty(DueParty party) => switch (party) {
      DueParty.client => (label: tr('Client'), icon: Icons.person_outline),
      DueParty.worker => (label: tr('Worker'), icon: Icons.engineering),
      DueParty.supplier => (label: tr('Supplier'), icon: Icons.store),
    };
