import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pickers.dart';
import '../../../core/pdf/pdf_common.dart';
import '../../lock/app_lock_controller.dart';
import '../data/billing_repository.dart';
import '../domain/statement_pdf.dart';
import 'billing_widgets.dart';

/// Billing tab (PRD E1): Bills | Quotations | Clients | Payments, with one
/// search box over all four.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key, this.tab});

  /// Sub-tab requested by a link (0 bills … 3 payments).
  final int? tab;

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: (widget.tab ?? 0).clamp(0, 3),
  )..addListener(() => setState(() {}));
  String _query = '';

  @override
  void didUpdateWidget(BillingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tab = widget.tab;
    if (tab != null && tab != oldWidget.tab) _tabs.animateTo(tab.clamp(0, 3));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget _fab(bool contractor) {
    final (label, icon, route) = switch (_tabs.index) {
      0 => (
          tr('New bill'),
          Icons.add,
          Routes.newDocument(DocumentKind.invoice)
        ),
      1 => (
          tr('New quotation'),
          Icons.add,
          Routes.newDocument(DocumentKind.quotation)
        ),
      2 => (
          contractor ? tr('New client') : tr('New customer'),
          Icons.person_add_alt,
          Routes.addClient
        ),
      _ => (tr('Payment received'), Icons.payments_outlined, Routes.payment()),
    };
    return FloatingActionButton.extended(
      onPressed: () => context.push(route),
      icon: Icon(icon),
      label: Text(label),
    );
  }

  /// Unpaid bills as one PDF statement.
  Future<void> _shareStatement() async {
    final bills = await ref.read(documentsProvider(DocumentKind.invoice).future);
    final open = bills.where(_isOpen).toList();
    final profile = await ref.read(businessProfileProvider.future);
    if (profile == null || !mounted) return;
    if (open.isEmpty) {
      showMessage(context, tr('No unpaid bills'));
      return;
    }
    final bytes = await buildStatementPdf(open, profile);
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      await sharePdf(bytes, fileName: 'Bills-statement.pdf');
    } finally {
      lock.suspendRelock = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final contractor = ref.watch(userTypeProvider) == UserType.contractor;
    return Scaffold(
      appBar: tabAppBar(
        tr('Billing'),
        actions: [
          AppIconButton(
            icon: Icons.ios_share,
            tooltip: tr('Share statement'),
            onPressed: _shareStatement,
          ),
        ],
      ),
      floatingActionButton: _fab(contractor),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SearchField(
              hint: contractor
                  ? tr('Search client, bill no.')
                  : tr('Search customer, bill no.'),
              onChanged: (q) => setState(() => _query = q.trim().toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.only(right: 20),
              tabs: [
                Tab(text: tr('Bills')),
                Tab(text: tr('Quotations')),
                Tab(text: contractor ? tr('Clients') : tr('Customers')),
                Tab(text: tr('Payments')),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _DocumentsTab(kind: DocumentKind.invoice, query: _query),
                _DocumentsTab(kind: DocumentKind.quotation, query: _query),
                _ClientsTab(query: _query),
                _PaymentsTab(query: _query),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _BillFilter { all, unpaid, overdue, paid }

bool _isOpen(DocumentListItem item) =>
    item.document.status == DocumentStatus.sent ||
    item.document.status == DocumentStatus.partiallyPaid;

bool _isOverdue(DocumentListItem item) {
  final due = item.document.dueDate;
  return _isOpen(item) && due != null && due.compareTo(isoDate(DateTime.now())) < 0;
}

class _DocumentsTab extends ConsumerStatefulWidget {
  const _DocumentsTab({required this.kind, required this.query});

  final DocumentKind kind;
  final String query;

  @override
  ConsumerState<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<_DocumentsTab> {
  _BillFilter _filter = _BillFilter.all;

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final docs = ref.watch(documentsProvider(kind));
    final isInvoice = kind == DocumentKind.invoice;
    return docs.when(
      loading: () => const ListSkeleton(),
      error: (e, _) => Center(child: Text(errorText(e))),
      data: (all) {
        if (all.isEmpty) {
          return EmptyState(
            icon: isInvoice ? Icons.receipt_long : Icons.request_quote,
            title: isInvoice ? tr('No bills yet') : tr('No quotations yet'),
            message: isInvoice
                ? tr('Make a bill and share the PDF on WhatsApp.')
                : tr('Make a quotation; convert it to a bill in one tap.'),
            actionLabel: isInvoice ? tr('New bill') : tr('New quotation'),
            onAction: () => context.push(Routes.newDocument(kind)),
          );
        }
        final q = widget.query;
        final searched = q.isEmpty
            ? all
            : all
                .where((d) =>
                    d.clientName.toLowerCase().contains(q) ||
                    d.document.number.toLowerCase().contains(q))
                .toList();
        final unpaid = searched.where(_isOpen).toList();
        final overdue = searched.where(_isOverdue).toList();
        final paid = searched
            .where((d) => d.document.status == DocumentStatus.paid)
            .toList();
        final shown = !isInvoice
            ? searched
            : switch (_filter) {
                _BillFilter.all => searched,
                _BillFilter.unpaid => unpaid,
                _BillFilter.overdue => overdue,
                _BillFilter.paid => paid,
              };

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
          children: [
            if (isInvoice) ...[
              const _BillSummary(),
              const SizedBox(height: 14),
              ChipRow(
                children: [
                    for (final (filter, label) in [
                      (
                        _BillFilter.all,
                        tr('All · {count}', {'count': searched.length})
                      ),
                      (
                        _BillFilter.unpaid,
                        tr('Unpaid · {count}', {'count': unpaid.length})
                      ),
                      (
                        _BillFilter.overdue,
                        tr('Overdue · {count}', {'count': overdue.length})
                      ),
                      (_BillFilter.paid, tr('Paid')),
                    ])
                      AppChip(
                        label: label,
                        selected: _filter == filter,
                        onTap: () => setState(() => _filter = filter),
                      ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  tr('Nothing here'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.muted),
                ),
              )
            else
              CardList(
                children: [for (final d in shown) DocumentTile(item: d)],
              ),
          ],
        );
      },
    );
  }
}

/// Unpaid total and money received this month (two small cards).
class _BillSummary extends ConsumerWidget {
  const _BillSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outstanding = ref.watch(outstandingProvider).valueOrNull;
    final payments = ref.watch(paymentsProvider(null)).valueOrNull;
    final now = DateTime.now();
    final monthPrefix = isoDate(DateTime(now.year, now.month)).substring(0, 7);
    final received = payments
        ?.where((p) => p.payment.date.startsWith(monthPrefix))
        .fold<int>(0, (sum, p) => sum + p.payment.amountPaise);

    Widget card(String label, String value, Color color) => Expanded(
          child: Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: AppText.tabular.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

    return Row(
      children: [
        card(tr('Unpaid'),
            outstanding == null ? '…' : formatPaise(outstanding), AppColors.ink),
        const SizedBox(width: 8),
        card(tr('Received this month'),
            received == null ? '…' : formatPaise(received),
            AppColors.successText),
      ],
    );
  }
}

class _ClientsTab extends ConsumerWidget {
  const _ClientsTab({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider);
    final contractor = ref.watch(userTypeProvider) == UserType.contractor;
    return clients.when(
      loading: () => const ListSkeleton(),
      error: (e, _) => Center(child: Text(errorText(e))),
      data: (all) {
        if (all.isEmpty) {
          return EmptyState(
            icon: Icons.people_outline,
            title: contractor ? tr('No clients yet') : tr('No customers yet'),
            message: tr('Add the people you work for.'),
            actionLabel: contractor ? tr('New client') : tr('New customer'),
            onAction: () => context.push(Routes.addClient),
          );
        }
        final list = query.isEmpty
            ? all
            : all
                .where((c) =>
                    c.client.name.toLowerCase().contains(query) ||
                    (c.client.phone ?? '').contains(query))
                .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
          children: [
            CardList(
              children: [
                for (final c in list)
                  InkWell(
                    onTap: () => context.push(Routes.client(c.client.id)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          InitialsAvatar(c.client.name),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.client.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700),
                                ),
                                if (c.client.phone != null)
                                  Text(
                                    formatIndianPhone(c.client.phone!),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (c.outstandingPaise > 0)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatPaise(c.outstandingPaise),
                                  style: AppText.tabular.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.warningText,
                                  ),
                                ),
                                Text(
                                  tr('pending'),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(paymentsProvider(null));
    return payments.when(
      loading: () => const ListSkeleton(),
      error: (e, _) => Center(child: Text(errorText(e))),
      data: (all) {
        if (all.isEmpty) {
          return EmptyState(
            icon: Icons.payments_outlined,
            title: tr('No payments yet'),
            message: tr('Money received from clients shows here.'),
          );
        }
        final list = query.isEmpty
            ? all
            : all
                .where((p) =>
                    p.clientName.toLowerCase().contains(query) ||
                    (p.documentNumber ?? '').toLowerCase().contains(query))
                .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
          children: [
            CardList(children: [for (final p in list) PaymentTile(item: p)]),
          ],
        );
      },
    );
  }
}

class PaymentTile extends StatelessWidget {
  const PaymentTile({super.key, required this.item});

  final PaymentItem item;

  @override
  Widget build(BuildContext context) {
    final p = item.payment;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const IconTile(Icons.south_west,
              color: AppColors.successSurface,
              iconColor: AppColors.successText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Text(
                  [
                    dayFormat.format(parseIsoDate(p.date)),
                    paymentModeLabel(p.mode),
                    if (item.documentNumber != null) item.documentNumber!,
                    if (p.remarks != null && p.remarks!.isNotEmpty) p.remarks!,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '+${formatPaise(p.amountPaise)}',
            style: AppText.tabular.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.successText,
            ),
          ),
        ],
      ),
    );
  }
}
