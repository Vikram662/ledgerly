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
import '../data/billing_repository.dart';
import 'billing_screen.dart';
import 'billing_widgets.dart';

/// Client ledger: billed, received, outstanding (PRD BL-01).
class ClientDetailScreen extends ConsumerWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clientProvider(clientId));
    final balance = async.valueOrNull;
    if (balance == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const ListSkeleton()
            : const NotFoundBody(),
      );
    }
    final client = balance.client;
    final bills = ref.watch(clientDocumentsProvider(clientId)).valueOrNull ?? const [];
    final payments = ref.watch(paymentsProvider(clientId)).valueOrNull ?? const [];
    final jobs = (ref.watch(jobsProvider).valueOrNull ?? const <JobListItem>[])
        .where((j) => j.job.clientId == clientId)
        .toList();

    final pending = balance.outstandingPaise;
    final phone = client.phone;
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
            icon: Icons.edit_outlined,
            tooltip: tr('Edit'),
            onPressed: () => context.push(Routes.editClient(clientId)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              InitialsAvatar(client.name, size: 56),
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
                          if (phone != null) formatIndianPhone(phone),
                          if (client.address != null) client.address!,
                        ].join(' · '),
                        style: grey.copyWith(fontSize: 13),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pending >= 0 ? tr('Pending') : tr('Advance with you'),
                    style: grey),
                Text(
                  formatPaise(pending.abs()),
                  style: AppText.tabular.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.64,
                    color: pending > 0
                        ? AppColors.warningText
                        : AppColors.successText,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Billed'), style: grey),
                          Text(
                            formatPaise(balance.billedPaise),
                            style: AppText.tabular.copyWith(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Received'), style: grey),
                          Text(
                            formatPaise(balance.receivedPaise),
                            style: AppText.tabular.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.successText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, AppSizes.tapSecondary),
                        ),
                        onPressed: () => context.push(Routes.newDocument(
                            DocumentKind.invoice,
                            clientId: clientId)),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: Text(tr('New bill')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, AppSizes.tapSecondary),
                        ),
                        onPressed: () =>
                            context.push(Routes.payment(clientId: clientId)),
                        icon: const Icon(Icons.south_west),
                        label: Text(tr('Payment')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SectionTitle(
            tr('Jobs / sites'),
            trailing: TextButton.icon(
              onPressed: () => context.push(Routes.addJob(clientId: clientId)),
              icon: const Icon(Icons.add),
              label: Text(tr('New job')),
            ),
          ),
          if (jobs.isEmpty)
            Text(tr('No jobs yet.'), style: TextStyle(color: AppColors.slate600))
          else
            CardList(
              children: [
                  for (final j in jobs)
                    ListTile(
                      title: Text(j.job.title),
                      subtitle: Text(jobStatusLabel(j.job.status)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.job(j.job.id)),
                    ),
              ],
            ),
          SectionTitle(tr('Bills')),
          if (bills.isEmpty)
            Text(tr('No bills yet.'), style: TextStyle(color: AppColors.slate600))
          else
            CardList(children: [for (final b in bills) DocumentTile(item: b)]),
          SectionTitle(tr('Payments')),
          if (payments.isEmpty)
            Text(tr('No payments yet.'),
                style: TextStyle(color: AppColors.slate600))
          else
            CardList(children: [for (final p in payments) PaymentTile(item: p)]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
