import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/utils/upi.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/phone_field.dart';
import '../../../core/widgets/pickers.dart';
import '../../lock/app_lock_controller.dart';
import '../data/billing_repository.dart';

/// Shares a polite payment reminder (with a UPI pay link when the business
/// has a UPI ID) through the share sheet, e.g. to WhatsApp.
Future<void> sharePaymentReminder(
  WidgetRef ref, {
  required String name,
  required int amountPaise,
}) async {
  final profile = await ref.read(businessProfileProvider.future);
  final business = profile?.name ?? '';
  final upi = profile?.upiId?.trim();
  var text = tr('Hello {name}, payment of {amount} is pending with {business}. Please pay at the earliest. Thank you.', {'name': name, 'amount': formatPaise(amountPaise), 'business': business});
  if (upi != null && isValidUpiId(upi)) {
    final link = upiPayUri(
      upiId: upi,
      payeeName: business,
      amountPaise: amountPaise,
      note: tr('Payment to {business}', {'business': business}),
    );
    text += '\n\nUPI ID: $upi\nPay now: $link';
  }
  final lock = ref.read(appLockProvider);
  lock.suspendRelock = true;
  try {
    await SharePlus.instance.share(ShareParams(text: text));
  } finally {
    lock.suspendRelock = false;
  }
}

class DocumentTile extends ConsumerWidget {
  const DocumentTile({super.key, required this.item});

  final DocumentListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = item.document;
    final invoice = doc.kind == DocumentKind.invoice;
    final open = doc.status == DocumentStatus.sent ||
        doc.status == DocumentStatus.partiallyPaid;
    final partPaid = invoice && open && item.paidPaise > 0;
    final overdue = invoice &&
        open &&
        doc.dueDate != null &&
        doc.dueDate!.compareTo(isoDate(DateTime.now())) < 0;

    const muted = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.muted,
    );

    return InkWell(
      onTap: () => context.push(Routes.document(doc.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.clientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        [
                          doc.number,
                          if (item.jobTitle != null) item.jobTitle!,
                          DateFormat('d MMM', uiDateLocale)
                              .format(parseIsoDate(doc.date)),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatPaise(doc.totalPaise),
                  style: AppText.tabular
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            if (partPaid && doc.totalPaise > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: item.paidPaise / doc.totalPaise,
                  minHeight: 6,
                  color: AppColors.successFill,
                  backgroundColor: AppColors.divider,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                DocumentPill(document: doc),
                const Spacer(),
                if (overdue)
                  MiniButton(
                    label: tr('Send reminder'),
                    onTap: () => sharePaymentReminder(
                      ref,
                      name: item.clientName,
                      amountPaise: item.balancePaise,
                    ),
                  )
                else if (invoice && open)
                  Text(
                    partPaid
                        ? tr('{paid} of {total}', {
                            'paid': formatPaise(item.paidPaise),
                            'total': formatPaise(doc.totalPaise),
                          })
                        : tr('{amount} received',
                            {'amount': formatPaise(item.paidPaise)}),
                    style: AppText.tabular.merge(muted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Short bill row on a client or job page: "#42 · Shop fit-out", date,
/// amount and status (wireframes ClientDetail, JobDetail).
class CompactDocumentRow extends StatelessWidget {
  const CompactDocumentRow({super.key, required this.document, this.title});

  final BillDocument document;

  /// Shown after the number, e.g. the job title.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final doc = document;
    return InkWell(
      onTap: () => context.push(Routes.document(doc.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [doc.number, if (title != null) title!].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    DateFormat('d MMM', uiDateLocale)
                        .format(parseIsoDate(doc.date)),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatPaise(doc.totalPaise),
                  style: AppText.tabular.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                DocumentPill(document: doc),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Status pill of a bill: overdue days, unpaid with due date, part paid…
class DocumentPill extends StatelessWidget {
  const DocumentPill({super.key, required this.document});

  final BillDocument document;

  @override
  Widget build(BuildContext context) {
    final doc = document;
    final invoice = doc.kind == DocumentKind.invoice;
    final open = doc.status == DocumentStatus.sent ||
        doc.status == DocumentStatus.partiallyPaid;
    final today = dateOnly(DateTime.now());
    final due = doc.dueDate == null ? null : parseIsoDate(doc.dueDate!);
    final lateDays = due == null ? 0 : today.difference(due).inDays;
    final overdue = invoice && open && lateDays > 0;

    final (String text, BadgeTone tone) = switch (doc.status) {
      _ when overdue => (
          trPlural(lateDays, 'Overdue 1 day', 'Overdue {count} days'),
          BadgeTone.danger,
        ),
      DocumentStatus.draft => (tr('Draft'), BadgeTone.neutral),
      DocumentStatus.sent when invoice => (
          due == null
              ? tr('Unpaid')
              : tr('Unpaid · due {date}',
                  {'date': DateFormat('d MMM', uiDateLocale).format(due)}),
          BadgeTone.warning,
        ),
      DocumentStatus.sent => (tr('Sent'), BadgeTone.info),
      DocumentStatus.partiallyPaid => (tr('Part paid'), BadgeTone.info),
      DocumentStatus.paid => (tr('Paid'), BadgeTone.success),
      DocumentStatus.cancelled => (tr('Cancelled'), BadgeTone.neutral),
    };
    return AppBadge(text, tone: tone);
  }
}

/// Field to choose a client, with "+ New client" inline (PRD BL-01).
class ClientPickerField extends ConsumerWidget {
  const ClientPickerField({
    super.key,
    required this.clientId,
    required this.onChanged,
    this.labeled = false,
  });

  final String? clientId;
  final ValueChanged<String> onChanged;

  /// Label above a plain "Choose a client" box (forms with [LabeledField]).
  final bool labeled;

  Future<void> _newClient(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('New client')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Name')),
            ),
            const SizedBox(height: 12),
            PhoneField(
              controller: phone,
              name: name,
              label: tr('Mobile (optional)'),
              validate: false,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Add')),
          ),
        ],
      ),
    );
    final clientName = name.text.trim();
    final clientPhone = normalizeIndianPhone(phone.text);
    name.dispose();
    phone.dispose();
    if (created != true || clientName.isEmpty) return;
    final id = await ref.read(billingRepositoryProvider).saveClient(
          name: clientName,
          phone: clientPhone,
        );
    onChanged(id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider).valueOrNull ?? const [];
    final selected = clients.where((c) => c.client.id == clientId).firstOrNull;
    Future<void> choose() async {
      const newClient = '__new__';
      final picked = await showPickerSheet<String>(
        context,
        title: tr('Choose client'),
        options: [newClient, for (final c in clients) c.client.id],
        label: (id) => id == newClient
            ? tr('+ New client')
            : clients.firstWhere((c) => c.client.id == id).client.name,
        selected: clientId,
      );
      if (picked == null || !context.mounted) return;
      if (picked == newClient) {
        await _newClient(context, ref);
      } else {
        onChanged(picked);
      }
    }

    if (labeled) {
      return LabeledField(
        label: tr('Client'),
        child: TapField(
          value: selected?.client.name,
          placeholder: tr('Choose a client'),
          icon: Icons.expand_more,
          onTap: choose,
        ),
      );
    }
    return PickerField(
      label: tr('Client'),
      icon: Icons.person_outline,
      value: selected?.client.name,
      onTap: choose,
    );
  }
}
