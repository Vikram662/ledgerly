import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_pad.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/billing_repository.dart';

/// PRD BL-13: payment received from a client, optionally against a bill.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key, this.clientId, this.documentId});

  final String? clientId;
  final String? documentId;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  late String? _clientId = widget.clientId;
  late String? _documentId = widget.documentId;
  String _amount = '';
  PaymentMode _mode = PaymentMode.cash;
  DateTime _date = dateOnly(DateTime.now());
  final _remarks = TextEditingController();
  bool _saving = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final paise = parseRupeesToPaise(_amount);
    if (_clientId == null) {
      showMessage(context, tr('Choose a client'));
      return;
    }
    if (paise == null || paise <= 0) {
      showMessage(context, tr('Enter the amount'));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(billingRepositoryProvider).recordPayment(
            clientId: _clientId!,
            documentId: _documentId,
            amountPaise: paise,
            mode: _mode,
            date: _date,
            remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, tr('✓ {amount} received', {'amount': formatPaise(paise)}));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, tr('Could not save: {e}', {'e': errorText(e)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider).valueOrNull ?? const [];
    final client = clients.where((c) => c.client.id == _clientId).firstOrNull;
    final bills = _clientId == null
        ? const <DocumentListItem>[]
        : (ref.watch(clientDocumentsProvider(_clientId!)).valueOrNull ?? const [])
            .where((b) =>
                b.document.status != DocumentStatus.cancelled &&
                b.document.status != DocumentStatus.draft &&
                (b.balancePaise > 0 || b.document.id == _documentId))
            .toList();
    final selectedBill =
        bills.where((b) => b.document.id == _documentId).firstOrNull;
    if (!_prefilled && selectedBill != null) {
      _prefilled = true;
      _amount = paiseToInputText(selectedBill.balancePaise);
    }
    final paise = parseRupeesToPaise(_amount) ?? 0;
    final fullDue = selectedBill?.balancePaise ?? client?.outstandingPaise;

    Future<void> chooseClient() async {
      final picked = await showPickerSheet<String>(
        context,
        title: tr('Choose client'),
        options: [for (final c in clients) c.client.id],
        label: (id) => clients.firstWhere((c) => c.client.id == id).client.name,
        subtitle: (id) {
          final due =
              clients.firstWhere((c) => c.client.id == id).outstandingPaise;
          return due > 0
              ? tr('Pending {amount}', {'amount': formatPaise(due)})
              : '';
        },
        selected: _clientId,
      );
      if (picked != null) {
        setState(() {
          _clientId = picked;
          _documentId = null;
        });
      }
    }

    Future<void> chooseBill() async {
      const none = '__none__';
      final picked = await showPickerSheet<String>(
        context,
        title: tr('Choose bill'),
        options: [none, for (final b in bills) b.document.id],
        label: (id) {
          if (id == none) return tr('No specific bill');
          final b = bills.firstWhere((b) => b.document.id == id);
          return tr('{number} · due {amount}', {
            'number': b.document.number,
            'amount': formatPaise(b.balancePaise),
          });
        },
        selected: _documentId ?? none,
      );
      if (picked == null) return;
      setState(() {
        _documentId = picked == none ? null : picked;
        final bill = bills.where((b) => b.document.id == _documentId).firstOrNull;
        if (bill != null) _amount = paiseToInputText(bill.balancePaise);
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(tr('Payment received')),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              children: [
                ChoiceCard(
                  leading: client == null
                      ? const IconTile(Icons.person_outline,
                          color: AppColors.track)
                      : InitialsAvatar(client.client.name),
                  title: client?.client.name ?? tr('Choose client'),
                  subtitle: client == null || client.outstandingPaise <= 0
                      ? null
                      : tr('Pending {amount}',
                          {'amount': formatPaise(client.outstandingPaise)}),
                  onTap: chooseClient,
                ),
                if (_clientId != null) ...[
                  const SizedBox(height: 8),
                  ChoiceCard(
                    leading: const IconTile(Icons.receipt_long_outlined),
                    overline: tr('Against bill (optional)'),
                    title: selectedBill == null
                        ? tr('No specific bill')
                        : tr('{number} · due {amount}', {
                            'number': selectedBill.document.number,
                            'amount': formatPaise(selectedBill.balancePaise),
                          }),
                    onTap: chooseBill,
                  ),
                ],
                AmountDisplay(
                  text: _amount,
                  color: AppColors.successText,
                ),
                if (fullDue != null && fullDue > 0 && paise != fullDue)
                  Center(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                      onPressed: () =>
                          setState(() => _amount = paiseToInputText(fullDue)),
                      child: Text(tr('Full due {amount}',
                          {'amount': formatPaise(fullDue)})),
                    ),
                  ),
                const SizedBox(height: 12),
                PaymentModeChips(
                  value: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _remarks,
                  decoration: InputDecoration(
                    hintText: _mode == PaymentMode.cheque
                        ? tr('Cheque no. and bank (optional)')
                        : tr('Note (optional)'),
                    isDense: true,
                    fillColor: AppColors.page,
                    prefixIcon:
                        const Icon(Icons.edit_note, color: AppColors.muted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: TextButton(
                      onPressed: () async {
                        final picked = await pickDate(context,
                            initial: _date, last: DateTime.now());
                        if (picked != null) {
                          setState(() => _date = dateOnly(picked));
                        }
                      },
                      child: Text(
                        _date == dateOnly(DateTime.now())
                            ? tr('Today')
                            : dayFormat.format(_date),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(color: AppColors.surface),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AmountPad(
                      value: _amount,
                      onChanged: (v) => setState(() => _amount = v),
                    ),
                    const SizedBox(height: 4),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : Text(paise > 0
                              ? tr('Save {amount}',
                                  {'amount': formatPaise(paise)})
                              : tr('Save')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
