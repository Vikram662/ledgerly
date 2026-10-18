import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/amount_pad.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pickers.dart';
import '../data/expenses_repository.dart';

/// PRD EX-02: suppliers with their due balance.
class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Suppliers'))),
      bottomNavigationBar: BottomActionBar(
        label: tr('Add supplier'),
        onPressed: () => context.push(Routes.addSupplier),
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Total to pay suppliers'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                    Text(
                      formatPaise(totalDue),
                      style: AppText.tabular.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.56,
                        color: totalDue > 0
                            ? AppColors.warningText
                            : AppColors.ink,
                      ),
                    ),
                    Text(
                      tr('Material bought on credit (udhaar)'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
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
                      subtitle: _lastEntryText(s) == null
                          ? null
                          : Text(_lastEntryText(s)!),
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
                                  ? AppColors.warningText
                                  : AppColors.ink,
                            ),
                          ),
                          Text(
                            s.duePaise == 0
                                ? tr('Settled')
                                : s.duePaise > 0
                                    ? tr('due')
                                    : tr('advance'),
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

/// "Last purchase 15 Oct" or "Paid 05 Oct", whichever entry is newer.
String? _lastEntryText(SupplierBalance s) {
  final purchase = s.lastPurchaseDate;
  final payment = s.lastPaymentDate;
  if (purchase == null && payment == null) return null;
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
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: tr('Mobile number (optional)'),
                prefixIcon: const PhoneCountryCode(),
              ),
              validator: (v) => (v == null ||
                      v.trim().isEmpty ||
                      normalizeIndianPhone(v) != null)
                  ? null
                  : tr('Enter a valid 10-digit mobile number'),
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

/// Supplier khata: balance, purchases and payments.
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

    final phone = balance.supplier.phone;
    const grey = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.muted,
    );
    Widget figure(String label, int paise, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: grey),
              Text(
                formatPaise(paise),
                style: AppText.tabular.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              InitialsAvatar(balance.supplier.name, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      balance.supplier.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.22,
                      ),
                    ),
                    if (phone != null)
                      Text(formatIndianPhone(phone),
                          style: grey.copyWith(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Panel(
            child: Row(
              children: [
                figure(tr('Purchased'), balance.purchasedPaise, AppColors.ink),
                figure(tr('Paid'), balance.paidPaise, AppColors.successText),
                figure(
                  due >= 0 ? tr('Due') : tr('Advance'),
                  due.abs(),
                  due > 0 ? AppColors.warningText : AppColors.ink,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionLabel(tr('Entries')),
          if (entries.isEmpty)
            Text(tr('No entries yet.'),
                style: TextStyle(color: AppColors.muted))
          else
            CardList(
              children: [
                for (final e in entries)
                  ListTile(
                    leading: IconTile(
                      e.entryType == SupplierEntryType.purchase
                          ? Icons.shopping_cart_outlined
                          : Icons.currency_rupee,
                    ),
                    title: Text(e.entryType == SupplierEntryType.purchase
                        ? (e.billNo == null
                            ? tr('Purchase')
                            : tr('Purchase · Bill {billNo}',
                                {'billNo': e.billNo}))
                        : tr('Payment')),
                    subtitle: Text([
                      dayFormat.format(parseIsoDate(e.date)),
                      if (e.mode != null) paymentModeLabel(e.mode!),
                      if (e.remarks != null && e.remarks!.isNotEmpty)
                        e.remarks!,
                    ].join(' · ')),
                    trailing: Text(
                      '${e.entryType == SupplierEntryType.purchase ? '+' : '−'}'
                      '${formatPaise(e.amountPaise)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
                        await ref
                            .read(expensesRepositoryProvider)
                            .deleteSupplierEntry(e.id);
                      }
                    },
                  ),
              ],
            ),
          const SizedBox(height: 32),
        ],
      ),
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
    return Scaffold(
      appBar: AppBar(title: Text(supplier?.name ?? tr('Supplier'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          SegmentedButton<SupplierEntryType>(
            segments: [
              ButtonSegment(
                value: SupplierEntryType.purchase,
                label: Text(tr('Purchase (udhaar)')),
              ),
              ButtonSegment(
                value: SupplierEntryType.payment,
                label: Text(tr('Payment')),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          AmountDisplay(text: _amount),
          AmountPad(
            value: _amount,
            onChanged: (v) => setState(() => _amount = v),
          ),
          if (isPayment)
            PaymentModeChips(
              value: _mode,
              onChanged: (m) => setState(() => _mode = m),
            )
          else
            TextField(
              controller: _billNo,
              decoration: InputDecoration(
                  labelText: tr('Supplier bill no. (optional)')),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(
              labelText: tr('Note (optional)'),
              hintText: tr('e.g. 20 bags cement'),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(dayFormat.format(_date)),
            trailing: Text(tr('Change')),
            onTap: () async {
              final picked =
                  await pickDate(context, initial: _date, last: DateTime.now());
              if (picked != null) setState(() => _date = dateOnly(picked));
            },
          ),
        ],
      ),
      bottomNavigationBar:
          BottomActionBar(label: tr('Save'), busy: _saving, onPressed: _save),
    );
  }
}
