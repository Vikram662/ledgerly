import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/pdf/pdf_common.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/utils/photos.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../lock/app_lock_controller.dart';
import '../data/billing_repository.dart';
import '../domain/document_pdf.dart';
import 'billing_screen.dart';
import 'billing_widgets.dart';
import 'line_editor_screen.dart';

class DocumentDetailScreen extends ConsumerWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    DocumentDetail detail,
  ) async {
    final profile = await ref.read(businessProfileProvider.future);
    if (profile == null) return;
    final bytes = await buildDocumentPdf(detail, profile);
    final doc = detail.document;
    final isInvoice = doc.kind == DocumentKind.invoice;
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      await sharePdf(
        bytes,
        fileName: '${doc.number}.pdf',
        text: tr(isInvoice ? 'Bill {number} from {business}: {amount}' : 'Quotation {number} from {business}: {amount}', {
              'number': doc.number,
              'business': profile.name,
              'amount': formatPaise(doc.totalPaise),
            }) +
            (isInvoice && detail.balancePaise > 0 && detail.paidPaise > 0
                ? tr(' (due {amount})', {'amount': formatPaise(detail.balancePaise)})
                : ''),
      );
    } finally {
      lock.suspendRelock = false;
    }
    await ref.read(billingRepositoryProvider).markSentIfDraft(doc.id);
  }

  Future<void> _convert(BuildContext context, WidgetRef ref) async {
    final id =
        await ref.read(billingRepositoryProvider).convertToInvoice(documentId);
    if (context.mounted) context.pushReplacement(Routes.document(id));
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: tr('Cancel this document?'),
      message: tr('It stays in the list as Cancelled and is not counted in pending amounts.'),
      confirmLabel: tr('Cancel document'),
      destructive: true,
    );
    if (ok) {
      await ref
          .read(billingRepositoryProvider)
          .setStatus(documentId, DocumentStatus.cancelled);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(documentDetailProvider(documentId));
    final detail = async.valueOrNull;
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const ListSkeleton()
            : const NotFoundBody(),
      );
    }
    final doc = detail.document;
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final isInvoice = doc.kind == DocumentKind.invoice;
    final cancelled = doc.status == DocumentStatus.cancelled;
    final payments = isInvoice
        ? (ref.watch(paymentsProvider(doc.clientId)).valueOrNull ?? const [])
            .where((p) => p.payment.documentId == doc.id)
            .toList()
        : const <PaymentItem>[];

    final total = doc.totalPaise;
    final kindLine = [
      isInvoice ? tr('Bill (non-tax)') : tr('Quotation'),
      if (doc.revision > 1) tr('Rev {revision}', {'revision': doc.revision}),
      DateFormat('d MMM', uiDateLocale).format(parseIsoDate(doc.date)),
      if (doc.dueDate != null)
        tr('due {date}', {
          'date': DateFormat('d MMM', uiDateLocale)
              .format(parseIsoDate(doc.dueDate!)),
        }),
    ].join(' · ');
    const grey = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.muted,
    );
    final showBalance = isInvoice && !cancelled;

    return Scaffold(
      appBar: AppBar(
        title: Text(isInvoice
            ? tr('Bill {number}', {'number': doc.number})
            : tr('Quotation {number}', {'number': doc.number})),
        actions: [
          if (!cancelled)
            AppIconButton(
              icon: Icons.edit_outlined,
              tooltip: tr('Edit'),
              onPressed: () => context.push(Routes.editDocument(doc.id)),
            ),
          PopupMenuButton<String>(
            tooltip: tr('More options'),
            onSelected: (v) {
              if (v == 'cancel') _cancel(context, ref);
              if (v == 'client') context.push(Routes.client(doc.clientId));
              if (v == 'remind') {
                sharePaymentReminder(
                  ref,
                  name: detail.client.name,
                  amountPaise: detail.balancePaise,
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'client', child: Text(tr('Open client'))),
              if (isInvoice && !cancelled && detail.balancePaise > 0)
                PopupMenuItem(
                    value: 'remind', child: Text(tr('Send reminder'))),
              if (!cancelled)
                PopupMenuItem(
                    value: 'cancel', child: Text(tr('Cancel document'))),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    DocumentPill(document: doc),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(kindLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: grey),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(showBalance ? tr('Balance due') : tr('Total'), style: grey),
                Text(
                  formatPaise(showBalance ? detail.balancePaise : total),
                  style: AppText.tabular.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.64,
                    color: showBalance && detail.balancePaise <= 0
                        ? AppColors.successText
                        : AppColors.ink,
                  ),
                ),
                if (showBalance) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total <= 0
                          ? 0
                          : (detail.paidPaise / total).clamp(0, 1).toDouble(),
                      minHeight: 8,
                      color: AppColors.successFill,
                      backgroundColor: AppColors.divider,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr('Received {amount}',
                              {'amount': formatPaise(detail.paidPaise)}),
                          style: AppText.tabular.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.successText,
                          ),
                        ),
                      ),
                      Text(
                        tr('Total {amount}', {'amount': formatPaise(total)}),
                        style: AppText.tabular.merge(grey),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: const BorderSide(color: AppColors.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: () => context.push(Routes.client(doc.clientId)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    InitialsAvatar(detail.client.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.client.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          if (detail.client.address != null ||
                              detail.client.phone != null)
                            Text(
                              [
                                if (detail.client.phone != null)
                                  formatIndianPhone(detail.client.phone!),
                                if (detail.client.address != null)
                                  detail.client.address!,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: grey,
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.faint),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SectionLabel(tr('Lines')),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final l in detail.lines) ...[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.line.name,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                l.line.lineType == LineType.lumpSum
                                    ? tr('Lump-sum')
                                    : [
                                        if (l.measurement.isNotEmpty)
                                          tr('From measurement'),
                                        '${formatMilli(l.line.qtyMilli)} ${l.unitCode ?? ''} × '
                                            '${formatPaise(l.line.ratePaise)}',
                                        if (l.measurement.isEmpty)
                                          lineTypeLabel(l.line.lineType),
                                      ].join(' · '),
                                style: AppText.tabular.merge(grey),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatPaise(l.line.amountPaise),
                          style: AppText.tabular.copyWith(
                              fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],
                Container(
                  color: AppColors.page.withValues(alpha: 0.5),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(
                    children: [
                      AmountRow(label: tr('Subtotal'), paise: doc.subtotalPaise),
                      if (doc.discountPaise != 0)
                        AmountRow(
                            label: tr('Discount'),
                            paise: doc.discountPaise,
                            prefix: '− '),
                      if (doc.roundOffPaise != 0)
                        AmountRow(
                            label: tr('Round off'), paise: doc.roundOffPaise),
                      AmountRow(label: tr('Total'), paise: total, bold: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!isInvoice && detail.convertedInvoiceId != null) ...[
            const SizedBox(height: 12),
            CardList(
              children: [
                SettingRow(
                  icon: Icons.link,
                  label: tr('Converted to a bill'),
                  onTap: () =>
                      context.push(Routes.document(detail.convertedInvoiceId!)),
                ),
              ],
            ),
          ],
          if (payments.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionLabel(tr('Payments')),
            CardList(children: [for (final p in payments) PaymentTile(item: p)]),
          ],
          if (doc.notes != null && doc.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionLabel(tr('Notes')),
            Panel(child: Text(doc.notes!)),
          ],
          if (profile?.logoPath != null) ...[
            const SizedBox(height: 16),
            Center(
              child: PhotoThumb(
                key: ValueKey(profile!.logoPath),
                name: profile.logoPath!,
                size: 32,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: cancelled
          ? null
          : _DetailActions(
              share: () => _share(context, ref, detail),
              primaryLabel: isInvoice
                  ? (detail.balancePaise > 0 ? tr('Payment received') : null)
                  : (detail.convertedInvoiceId == null
                      ? tr('Convert to bill')
                      : tr('Make another bill')),
              primary: isInvoice
                  ? () => context.push(Routes.payment(
                        clientId: doc.clientId,
                        documentId: doc.id,
                      ))
                  : () => _convert(context, ref),
            ),
    );
  }
}

/// Footer: Share PDF (outlined) and the main action; Share alone if none.
class _DetailActions extends StatelessWidget {
  const _DetailActions({
    required this.share,
    required this.primaryLabel,
    required this.primary,
  });

  final VoidCallback share;
  final String? primaryLabel;
  final VoidCallback primary;

  @override
  Widget build(BuildContext context) {
    if (primaryLabel == null) {
      return BottomActionBar(label: tr('Share PDF'), onPressed: share);
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSizes.tapPrimary),
                  ),
                  onPressed: share,
                  icon: const Icon(Icons.share_outlined),
                  label: Text(tr('Share PDF')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: primary,
                  child: FittedBox(child: Text(primaryLabel!)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
