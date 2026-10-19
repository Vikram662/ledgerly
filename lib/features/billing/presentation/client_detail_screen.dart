import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../jobs/data/jobs_repository.dart';
import '../../jobs/presentation/jobs_screens.dart';
import '../data/billing_repository.dart';
import 'billing_screen.dart';
import 'billing_widgets.dart';

enum _Records { bills, payments, jobs }

/// Client ledger (PRD BL-01, wireframe ClientDetail): billed, received,
/// pending, quick actions, then bills / payments / jobs.
class ClientDetailScreen extends ConsumerStatefulWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends ConsumerState<ClientDetailScreen> {
  var _records = _Records.bills;

  @override
  Widget build(BuildContext context) {
    final clientId = widget.clientId;
    final async = ref.watch(clientProvider(clientId));
    final balance = async.valueOrNull;
    if (balance == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading ? const ListSkeleton() : const NotFoundBody(),
      );
    }
    final client = balance.client;
    final bills =
        ref.watch(clientDocumentsProvider(clientId)).valueOrNull ?? const [];
    final payments =
        ref.watch(paymentsProvider(clientId)).valueOrNull ?? const [];
    final jobs = (ref.watch(jobsProvider).valueOrNull ?? const <JobListItem>[])
        .where((j) => j.job.clientId == clientId)
        .toList();
    final pending = balance.outstandingPaise;
    final phone = client.phone;

    const empty = TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted);
    Widget list(List<Widget> rows, String none) => rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(none, textAlign: TextAlign.center, style: empty),
          )
        : CardList(children: rows);

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (phone != null) ...[
            AppIconButton(
              icon: Icons.call_outlined,
              tooltip: tr('Call client'),
              onPressed: () => launchUrl(Uri.parse('tel:$phone')),
            ),
            const SizedBox(width: 8),
          ],
          AppIconButton(
            icon: Icons.edit_outlined,
            tooltip: tr('Edit'),
            onPressed: () => context.push(Routes.editClient(clientId)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              InitialsAvatar(client.name, size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.22,
                      ),
                    ),
                    if (phone != null || client.address != null)
                      Text(
                        [
                          if (phone != null) '+91 ${formatIndianPhone(phone)}',
                          if (client.address != null) client.address!,
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Panel(
            child: Row(
              children: [
                Expanded(
                  child: FigureColumn(
                    label: tr('Billed'),
                    value: formatPaise(balance.billedPaise),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FigureColumn(
                    label: tr('Received'),
                    value: formatPaise(balance.receivedPaise),
                    color: AppColors.successText,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FigureColumn(
                    label: pending >= 0 ? tr('Pending') : tr('Advance'),
                    value: formatPaise(pending.abs()),
                    color: pending > 0
                        ? AppColors.dangerText
                        : AppColors.successText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ActionButtons(actions: [
            (
              label: tr('+ New bill'),
              onTap: () => context.push(
                  Routes.newDocument(DocumentKind.invoice, clientId: clientId)),
            ),
            (
              label: tr('+ Payment'),
              onTap: () => context.push(Routes.payment(clientId: clientId)),
            ),
            (
              label: tr('+ Job'),
              onTap: () => context.push(Routes.addJob(clientId: clientId)),
            ),
          ]),
          const SizedBox(height: 14),
          UnderlineTabs<_Records>(
            value: _records,
            options: {
              _Records.bills: tr('Bills · {count}', {'count': bills.length}),
              _Records.payments:
                  tr('Payments · {count}', {'count': payments.length}),
              _Records.jobs: tr('Jobs · {count}', {'count': jobs.length}),
            },
            onChanged: (r) => setState(() => _records = r),
          ),
          const SizedBox(height: 14),
          switch (_records) {
            _Records.bills => list([
                for (final b in bills)
                  CompactDocumentRow(document: b.document, title: b.jobTitle),
              ], tr('No bills yet.')),
            _Records.payments => list([
                for (final p in payments) PaymentTile(item: p),
              ], tr('No payments yet.')),
            _Records.jobs => list([
                for (final j in jobs)
                  ListTile(
                    title: Text(
                      j.job.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    subtitle: j.job.siteAddress == null
                        ? null
                        : Text(j.job.siteAddress!),
                    trailing: JobStatusBadge(j.job.status),
                    onTap: () => context.push(Routes.job(j.job.id)),
                  ),
              ], tr('No jobs yet.')),
          },
        ],
      ),
    );
  }
}
