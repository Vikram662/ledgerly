import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/amount_pad.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/phone_field.dart';
import '../../../core/widgets/pickers.dart';
import '../data/expenses_repository.dart';

/// PRD EX-02 (wireframe Suppliers): suppliers with their due balance.
class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Suppliers'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.addSupplier),
        icon: const Icon(Icons.add),
        label: Text(tr('Add supplier')),
      ),
      body: suppliers.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => Center(child: Text(errorText(e))),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.store,
              title: tr('No suppliers yet'),
              message: tr('Add the shops you buy material from on credit.'),
              actionLabel: tr('Add supplier'),
              onAction: () => context.push(Routes.addSupplier),
            );
          }
          final totalDue = list.fold(
            0,
            (sum, s) => s.duePaise > 0 ? sum + s.duePaise : sum,
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              HeroPanel(
                label: tr('Total to pay suppliers'),
                value: formatPaise(totalDue),
                note: tr('Material bought on credit (udhaar)'),
              ),
              const SizedBox(height: 12),
              CardList(
                children: [
                  for (final s in list)
                    ListTile(
                      leading: InitialsAvatar(s.supplier.name),
                      title: Text(
                        s.supplier.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(_lastEntryText(s)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatPaise(s.duePaise.abs()),
                            style: AppText.tabular.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: s.duePaise > 0
                                  ? AppColors.dangerText
                                  : s.duePaise < 0
                                      ? AppColors.successText
                                      : AppColors.ink,
                            ),
                          ),
                          if (s.duePaise != 0)
                            Text(
                              s.duePaise > 0 ? tr('due') : tr('advance'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                        ],
                      ),
                      onTap: () => context.push(Routes.supplier(s.supplier.id)),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "Last purchase 15 Oct", "Paid 05 Oct" (whichever is newer) or "Settled".
String _lastEntryText(SupplierBalance s) {
  final purchase = s.lastPurchaseDate;
  final payment = s.lastPaymentDate;
  if (s.duePaise == 0 && (purchase != null || payment != null)) {
    return tr('Settled');
  }
  if (purchase == null && payment == null) return tr('No entries yet.');
  // ISO dates compare correctly as strings.
  final paidLast =
      payment != null && (purchase == null || payment.compareTo(purchase) > 0);
  final date = dayFormat.format(parseIsoDate(paidLast ? payment : purchase!));
  return paidLast
      ? tr('Paid {date}', {'date': date})
      : tr('Last purchase {date}', {'date': date});
}

class SupplierFormScreen extends ConsumerStatefulWidget {
  const SupplierFormScreen({super.key, this.supplierId});

  final String? supplierId;

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final address = _address.text.trim();
    await ref.read(expensesRepositoryProvider).saveSupplier(
          id: widget.supplierId,
          name: _name.text.trim(),
          phone: normalizeIndianPhone(_phone.text),
          address: address.isEmpty ? null : address,
        );
    if (!mounted) return;
    showMessage(context, tr('Supplier saved'));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.supplierId != null && !_loaded) {
      final s = ref.watch(supplierProvider(widget.supplierId!)).valueOrNull;
      if (s == null) {
        return const SkeletonPage();
      }
      _loaded = true;
      _name.text = s.supplier.name;
      _phone.text =
          s.supplier.phone == null ? '' : formatIndianPhone(s.supplier.phone!);
      _address.text = s.supplier.address ?? '';
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplierId == null
            ? tr('New supplier')
            : tr('Edit supplier')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration:
                  InputDecoration(labelText: tr('Shop / supplier name')),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? tr('Enter name') : null,
            ),
            const SizedBox(height: 12),
            PhoneField(
              controller: _phone,
              name: _name,
              label: tr('Mobile number (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              maxLines: 2,
              decoration: InputDecoration(labelText: tr('Address (optional)')),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          BottomActionBar(label: tr('Save'), busy: _saving, onPressed: _save),
    );
  }
}

/// Supplier khata (wireframe SupplierDetail): totals, entries, and buttons
/// for a purchase on credit or a payment.
class SupplierDetailScreen extends ConsumerWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supplierProvider(supplierId));
    final balance = async.valueOrNull;
    if (balance == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading ? const ListSkeleton() : const NotFoundBody(),
      );
    }
    final entries =
        ref.watch(supplierEntriesProvider(supplierId)).valueOrNull ?? const [];
    final due = balance.duePaise;
    final supplier = balance.supplier;
    final phone = supplier.phone;
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
              tooltip: tr('Call supplier'),
              onPressed: () => launchUrl(Uri.parse('tel:$phone')),
            ),
            const SizedBox(width: 8),
          ],
          AppIconButton(
            icon: Icons.edit_outlined,
            tooltip: tr('Edit supplier'),
            onPressed: () => context.push(Routes.editSupplier(supplierId)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push(Routes.supplierEntry(
                      supplierId, SupplierEntryType.purchase)),
                  child: Text(tr('+ Purchase (udhaar)')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.successFill),
                  onPressed: () => context.push(Routes.supplierEntry(
                      supplierId, SupplierEntryType.payment)),
                  child: Text(tr('+ Payment')),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            supplier.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (phone != null || supplier.address != null)
            Text(
              [
                if (phone != null) formatIndianPhone(phone),
                if (supplier.address != null) supplier.address!,
              ].join(' · '),
              style: grey,
            ),
          const SizedBox(height: 14),
          Panel(
            child: Row(
              children: [
                Expanded(
                  child: FigureColumn(
                    label: tr('Purchased'),
                    value: formatPaise(balance.purchasedPaise),
                  ),
                ),
                Expanded(
                  child: FigureColumn(
                    label: tr('Paid'),
                    value: formatPaise(balance.paidPaise),
                    color: AppColors.successText,
                  ),
                ),
                Expanded(
                  child: FigureColumn(
                    label: due >= 0 ? tr('Due') : tr('Advance'),
                    value: formatPaise(due.abs()),
                    color: due > 0 ? AppColors.dangerText : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionLabel(tr('Entries')),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(tr('No entries yet.'),
                  textAlign: TextAlign.center, style: grey),
            )
          else
            CardList(
              children: [
                for (final e in entries) _SupplierEntryRow(entry: e),
              ],
            ),
        ],
      ),
    );
  }
}

/// P (purchase, red) or ₹ (payment, green) row; long-press to delete.
class _SupplierEntryRow extends ConsumerWidget {
  const _SupplierEntryRow({required this.entry});

  final SupplierEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    final purchase = e.entryType == SupplierEntryType.purchase;
    final color = purchase ? AppColors.dangerText : AppColors.successText;
    return ListTile(
      leading: LetterTag(
        purchase ? 'P' : '₹',
        color: purchase ? AppColors.dangerSurface : AppColors.successSurface,
        textColor: color,
      ),
      title: Text(
        purchase
            ? (e.billNo == null
                ? tr('Purchase')
                : tr('Purchase · Bill {billNo}', {'billNo': e.billNo}))
            : [tr('Payment'), if (e.mode != null) paymentModeLabel(e.mode!)]
                .join(' · '),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text([
        if (e.remarks != null && e.remarks!.isNotEmpty) e.remarks!,
        dayFormat.format(parseIsoDate(e.date)),
      ].join(' · ')),
      trailing: Text(
        formatPaise(e.amountPaise),
        style: AppText.tabular.copyWith(
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
      onLongPress: () async {
        final ok = await confirmDialog(
          context,
          title: tr('Delete this entry?'),
          message: formatPaise(e.amountPaise),
          confirmLabel: tr('Delete'),
          destructive: true,
        );
        if (ok) {
          await ref.read(expensesRepositoryProvider).deleteSupplierEntry(e.id);
        }
      },
    );
  }
}

/// Purchase on credit (udhaar) or payment to a supplier.
class SupplierEntryScreen extends ConsumerStatefulWidget {
  const SupplierEntryScreen({
    super.key,
    required this.supplierId,
    required this.type,
  });

  final String supplierId;
  final SupplierEntryType type;

  @override
  ConsumerState<SupplierEntryScreen> createState() =>
      _SupplierEntryScreenState();
}

class _SupplierEntryScreenState extends ConsumerState<SupplierEntryScreen> {
  late SupplierEntryType _type = widget.type;
  String _amount = '';
  PaymentMode _mode = PaymentMode.cash;
  DateTime _date = dateOnly(DateTime.now());
  final _billNo = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _billNo.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final paise = parseRupeesToPaise(_amount);
    if (paise == null || paise <= 0) {
      showMessage(context, tr('Enter the amount'));
      return;
    }
    setState(() => _saving = true);
    final isPayment = _type == SupplierEntryType.payment;
    await ref.read(expensesRepositoryProvider).addSupplierEntry(
          supplierId: widget.supplierId,
          type: _type,
          amountPaise: paise,
          date: _date,
          mode: isPayment ? _mode : null,
          billNo: !isPayment && _billNo.text.trim().isNotEmpty
              ? _billNo.text.trim()
              : null,
          remarks: _note.text.trim().isEmpty ? null : _note.text.trim(),
        );
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    showMessage(
        context, isPayment ? tr('✓ Payment saved') : tr('✓ Purchase saved'));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final supplier =
        ref.watch(supplierProvider(widget.supplierId)).valueOrNull?.supplier;
    final isPayment = _type == SupplierEntryType.payment;
    final paise = parseRupeesToPaise(_amount) ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(supplier?.name ?? tr('Supplier'))),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              children: [
                ChipRow(
                  children: [
                    for (final (type, label) in [
                      (SupplierEntryType.purchase, tr('Purchase (udhaar)')),
                      (SupplierEntryType.payment, tr('Payment')),
                    ])
                      AppChip(
                        label: label,
                        selected: _type == type,
                        onTap: () => setState(() => _type = type),
                      ),
                  ],
                ),
                AmountDisplay(text: _amount, label: tr('Amount')),
                if (isPayment) ...[
                  SectionLabel(tr('Paid by')),
                  PaymentModeChips(
                    value: _mode,
                    onChanged: (m) => setState(() => _mode = m),
                  ),
                ] else
                  TextField(
                    controller: _billNo,
                    decoration: InputDecoration(
                        hintText: tr('Supplier bill no. (optional)')),
                  ),
                const SizedBox(height: 12),
                NoteDateField(
                  controller: _note,
                  hint: tr('e.g. 20 bags cement'),
                  dateLabel: dayButtonLabel(_date),
                  onPickDate: () async {
                    final picked = await pickDate(context,
                        initial: _date, last: DateTime.now());
                    if (picked != null) setState(() => _date = dateOnly(picked));
                  },
                ),
              ],
            ),
          ),
          AmountPadFooter(
            value: _amount,
            onChanged: (v) => setState(() => _amount = v),
            saving: _saving,
            onSave: _save,
            saveLabel: paise > 0
                ? tr('Save {amount}', {'amount': formatPaise(paise)})
                : tr('Save'),
          ),
        ],
      ),
    );
  }
}
