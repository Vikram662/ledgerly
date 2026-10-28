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
import '../../../core/widgets/phone_field.dart';
import '../data/loans_repository.dart';
import 'loan_widgets.dart';

/// New or edited person (borrower or the one money is taken from). A new
/// person's id is returned to the screen that opened the form.
class LoanPartyFormScreen extends ConsumerStatefulWidget {
  const LoanPartyFormScreen({super.key, this.partyId});

  final String? partyId;

  @override
  ConsumerState<LoanPartyFormScreen> createState() =>
      _LoanPartyFormScreenState();
}

class _LoanPartyFormScreenState extends ConsumerState<LoanPartyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final id = await ref.read(loansRepositoryProvider).saveParty(
          id: widget.partyId,
          name: _name.text.trim(),
          phone: normalizeIndianPhone(_phone.text),
          address: _text(_address),
          note: _text(_note),
        );
    if (!mounted) return;
    showMessage(context, tr('Saved'));
    context.pop(id);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.partyId != null && !_loaded) {
      final parties = ref.watch(loanPartiesProvider).valueOrNull;
      if (parties == null) return const SkeletonPage();
      final p = parties.where((p) => p.id == widget.partyId).firstOrNull;
      if (p != null) {
        _name.text = p.name;
        _phone.text = p.phone == null ? '' : formatIndianPhone(p.phone!);
        _address.text = p.address ?? '';
        _note.text = p.note ?? '';
      }
      _loaded = true;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.partyId == null ? tr('Add person') : tr('Edit person')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Name')),
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: InputDecoration(labelText: tr('Note (optional)')),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          BottomActionBar(label: tr('Save'), busy: _saving, onPressed: _save),
    );
  }
}

/// A person's loans: what they owe, what is owed to them, and every loan.
class LoanPartyDetailScreen extends ConsumerWidget {
  const LoanPartyDetailScreen({super.key, required this.partyId});

  final String partyId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: tr('Delete this person?'),
      message: tr('Only a person with no loans can be deleted.'),
      confirmLabel: tr('Delete'),
      destructive: true,
    );
    if (!ok) return;
    final deleted = await ref.read(loansRepositoryProvider).deleteParty(partyId);
    if (!context.mounted) return;
    if (deleted) {
      context.pop();
    } else {
      showMessage(context, tr('Delete their loans first.'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parties = ref.watch(loanPartiesProvider);
    final party =
        parties.valueOrNull?.where((p) => p.id == partyId).firstOrNull;
    if (party == null) {
      return Scaffold(
        appBar: AppBar(),
        body: parties.isLoading ? const ListSkeleton() : const NotFoundBody(),
      );
    }
    final loans = (ref.watch(loanViewsProvider).valueOrNull ?? const [])
        .where((v) => v.party.id == partyId)
        .toList();
    final open = loans.where((v) => v.open);
    final toGet = open
        .where((v) => v.given)
        .fold(0, (s, v) => s + v.statement.balancePaise);
    final toPay = open
        .where((v) => !v.given)
        .fold(0, (s, v) => s + v.statement.balancePaise);
    final phone = party.phone;
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
            tooltip: tr('Edit person'),
            onPressed: () => context.push(Routes.editLoanParty(partyId)),
          ),
          if (loans.isEmpty)
            IconButton(
              tooltip: tr('Delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref),
            ),
          const SizedBox(width: 12),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ActionButtons(actions: [
            (
              label: tr('Loan given'),
              onTap: () => context.push(
                  Routes.newLoan(LoanDirection.given, partyId: partyId)),
            ),
            (
              label: tr('Loan taken'),
              onTap: () => context.push(
                  Routes.newLoan(LoanDirection.taken, partyId: partyId)),
            ),
          ]),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            party.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (phone != null || party.address != null)
            Text(
              [
                if (phone != null) formatIndianPhone(phone),
                if (party.address != null) party.address!,
              ].join(' · '),
              style: grey,
            ),
          if (party.note != null) Text(party.note!, style: grey),
          const SizedBox(height: 14),
          Panel(
            child: Row(
              children: [
                Expanded(
                  child: FigureColumn(
                    label: tr('To get from them'),
                    value: formatPaise(toGet),
                    color: AppColors.successText,
                  ),
                ),
                Expanded(
                  child: FigureColumn(
                    label: tr('To pay them'),
                    value: formatPaise(toPay),
                    color: AppColors.dangerText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionLabel(tr('Loans')),
          if (loans.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(tr('No loans yet.'),
                  textAlign: TextAlign.center, style: grey),
            )
          else
            CardList(
              children: [
                for (final v in loans) LoanTile(view: v, showParty: false),
              ],
            ),
        ],
      ),
    );
  }
}
