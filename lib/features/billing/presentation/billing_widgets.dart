import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/billing_repository.dart';

/// Status pill with icon + label (PRD BL-15, I-D3).
StatusChip documentStatusChip(DocumentStatus status, DocumentKind kind) {
  final (label, color, icon) = switch (status) {
    DocumentStatus.draft => (tr('Draft'), AppColors.muted, Icons.edit_note),
    DocumentStatus.sent => (
        kind == DocumentKind.invoice ? tr('Unpaid') : tr('Sent'),
        AppColors.warningText,
        Icons.send,
      ),
    DocumentStatus.partiallyPaid => (
        tr('Part paid'),
        AppColors.blue700,
        Icons.timelapse
      ),
    DocumentStatus.paid => (
        tr('Paid'),
        AppColors.successText,
        Icons.check_circle
      ),
    DocumentStatus.cancelled => (
        tr('Cancelled'),
        AppColors.dangerText,
        Icons.block
      ),
  };
  return StatusChip(label: label, color: color, icon: icon);
}

class DocumentTile extends StatelessWidget {
  const DocumentTile({super.key, required this.item});

  final DocumentListItem item;

  @override
  Widget build(BuildContext context) {
    final doc = item.document;
    final invoice = doc.kind == DocumentKind.invoice;
    final open = doc.status == DocumentStatus.sent ||
        doc.status == DocumentStatus.partiallyPaid;
    final partPaid = invoice && open && item.paidPaise > 0;

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
                        '${doc.number} · ${DateFormat('d MMM', uiDateLocale).format(parseIsoDate(doc.date))}',
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
                DocumentPill(document: doc, paidPaise: item.paidPaise),
                const Spacer(),
                if (invoice && open)
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

/// Status pill of a bill: overdue days, unpaid with due date, part paid…
class DocumentPill extends StatelessWidget {
  const DocumentPill({
    super.key,
    required this.document,
    required this.paidPaise,
  });

  final BillDocument document;
  final int paidPaise;

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

    final (String text, Color bg, Color fg) = switch (doc.status) {
      _ when overdue => (
          trPlural(lateDays, 'Overdue 1 day', 'Overdue {count} days'),
          AppColors.dangerSurface,
          AppColors.dangerText,
        ),
      DocumentStatus.draft => (tr('Draft'), AppColors.page, AppColors.muted),
      DocumentStatus.sent when invoice => (
          due == null
              ? tr('Unpaid')
              : tr('Unpaid · due {date}',
                  {'date': DateFormat('d MMM', uiDateLocale).format(due)}),
          AppColors.warningSurface,
          AppColors.warningText,
        ),
      DocumentStatus.sent => (
          tr('Sent'),
          AppColors.primaryTint,
          AppColors.primary
        ),
      DocumentStatus.partiallyPaid => (
          tr('Part paid'),
          AppColors.primaryTint,
          AppColors.primary
        ),
      DocumentStatus.paid => (
          tr('Paid'),
          AppColors.successSurface,
          AppColors.successText
        ),
      DocumentStatus.cancelled => (
          tr('Cancelled'),
          AppColors.page,
          AppColors.muted
        ),
    };
    return TagBadge(text, color: bg, textColor: fg);
  }
}

/// Field to choose a client, with "+ New client" inline (PRD BL-01).
class ClientPickerField extends ConsumerWidget {
  const ClientPickerField({
    super.key,
    required this.clientId,
    required this.onChanged,
  });

  final String? clientId;
  final ValueChanged<String> onChanged;

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
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: tr('Mobile (optional)'),
                prefixIcon: const PhoneCountryCode(),
              ),
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
    return PickerField(
      label: tr('Client'),
      icon: Icons.person_outline,
      value: selected?.client.name,
      onTap: () async {
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
      },
    );
  }
}
