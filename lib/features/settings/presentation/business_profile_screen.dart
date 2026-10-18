import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/utils/phone.dart';
import '../../../core/utils/photos.dart';
import '../../../core/utils/upi.dart';
import '../../../core/widgets/common.dart';
import '../../lock/app_lock_controller.dart';
import '../../subscription/subscription_controller.dart';

/// Name, phone, address, UPI and number prefixes shown on PDFs (PRD BL-11).
class BusinessProfileScreen extends ConsumerStatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  ConsumerState<BusinessProfileScreen> createState() =>
      _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _upi = TextEditingController();
  final _invoicePrefix = TextEditingController();
  final _quotationPrefix = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _address,
      _upi,
      _invoicePrefix,
      _quotationPrefix
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final current = ref.read(businessProfileProvider).valueOrNull;
    final access = ref.read(subscriptionControllerProvider).valueOrNull;
    final requiresSubscription = current?.userType.isFree != true;
    final paid = requiresSubscription &&
        (access?.kind == AccessKind.active ||
            access?.kind == AccessKind.offlineGrace ||
            access?.kind == AccessKind.loading);
    if (paid &&
        current != null &&
        normalizeIndianPhone(_phone.text) != current.phone) {
      showMessage(context, tr('Paid account phone cannot be changed here'));
      return;
    }
    setState(() => _saving = true);
    String? opt(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    await ref.read(settingsRepositoryProvider).saveProfile(
          name: _name.text.trim(),
          phone: normalizeIndianPhone(_phone.text),
          address: opt(_address),
          upiId: opt(_upi),
          invoicePrefix: _invoicePrefix.text.trim().toUpperCase(),
          quotationPrefix: _quotationPrefix.text.trim().toUpperCase(),
        );
    if (!mounted) return;
    showMessage(context, tr('Saved'));
    context.pop();
  }

  Future<void> _changeLogo(String? oldLogo) async {
    // Choosing from the gallery leaves the app; don't lock it meanwhile.
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    final String? name;
    try {
      name = await pickLogo();
    } finally {
      lock.suspendRelock = false;
    }
    if (name == null) return;
    await ref.read(settingsRepositoryProvider).saveLogo(name);
    await deletePhoto(oldLogo);
    if (mounted) showMessage(context, tr('Logo saved'));
  }

  Future<void> _removeLogo(String logo) async {
    await ref.read(settingsRepositoryProvider).saveLogo(null);
    await deletePhoto(logo);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final access = ref.watch(subscriptionControllerProvider).valueOrNull;
    final requiresSubscription = profile?.userType.isFree != true;
    final paid = requiresSubscription &&
        (access?.kind == AccessKind.active ||
            access?.kind == AccessKind.offlineGrace ||
            access?.kind == AccessKind.loading);
    if (profile == null) {
      return const SkeletonPage();
    }
    if (!_loaded) {
      _loaded = true;
      _name.text = profile.name;
      _phone.text =
          profile.phone == null ? '' : formatIndianPhone(profile.phone!);
      _address.text = profile.address ?? '';
      _upi.text = profile.upiId ?? '';
      _invoicePrefix.text = profile.invoicePrefix;
      _quotationPrefix.text = profile.quotationPrefix;
    }
    String? requiredField(String? v) =>
        (v == null || v.trim().isEmpty) ? tr('Required') : null;
    String? prefix(String? v) =>
        (v == null || !RegExp(r'^[A-Za-z0-9]{1,6}$').hasMatch(v.trim()))
            ? tr('1–6 letters or digits')
            : null;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Business profile'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Panel(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  profile.logoPath == null
                      ? Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius:
                                BorderRadius.circular(AppRadius.input),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(Icons.add_photo_alternate_outlined,
                              color: AppColors.muted),
                        )
                      : PhotoThumb(
                          key: ValueKey(profile.logoPath),
                          name: profile.logoPath!,
                          size: 72,
                          fit: BoxFit.contain,
                        ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Logo'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        Text(
                          tr('Printed on bills, quotations and pay slips'),
                          style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                        Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () => _changeLogo(profile.logoPath),
                              child: Text(profile.logoPath == null
                                  ? tr('Choose logo')
                                  : tr('Change')),
                            ),
                            if (profile.logoPath != null)
                              TextButton(
                                onPressed: () => _removeLogo(profile.logoPath!),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.dangerText,
                                ),
                                child: Text(tr('Remove')),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: tr('Business name'),
              child: TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                validator: requiredField,
              ),
            ),
            LabeledField(
              label: tr('Mobile number'),
              child: TextFormField(
                controller: _phone,
                readOnly: paid,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: tr('10-digit number'),
                  prefixIcon: const PhoneCountryCode(),
                  helperText: paid
                      ? tr('Paid account phone cannot be changed here')
                      : null,
                ),
                validator: (v) => (v == null ||
                        v.trim().isEmpty ||
                        normalizeIndianPhone(v) != null)
                    ? null
                    : tr('Enter a valid 10-digit mobile number'),
              ),
            ),
            LabeledField(
              label: tr('Address'),
              optional: true,
              child: TextFormField(
                controller: _address,
                maxLines: 2,
                decoration: InputDecoration(hintText: tr('Shown on the bill')),
              ),
            ),
            LabeledField(
              label: tr('UPI ID (printed on bills)'),
              optional: true,
              child: TextFormField(
                controller: _upi,
                decoration: const InputDecoration(hintText: 'name@bank'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty || isValidUpiId(v))
                        ? null
                        : tr('Enter a UPI ID like name@okaxis'),
              ),
            ),
            const SizedBox(height: 6),
            SectionLabel(tr('Numbering')),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _invoicePrefix,
                    decoration: InputDecoration(labelText: tr('Bill prefix')),
                    validator: prefix,
                  ),
                ),
                const SizedBox(width: AppSizes.gap),
                Expanded(
                  child: TextFormField(
                    controller: _quotationPrefix,
                    decoration:
                        InputDecoration(labelText: tr('Quotation prefix')),
                    validator: prefix,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr('Numbers restart every financial year, e.g. INV/26-27/0001.'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          BottomActionBar(label: tr('Save'), busy: _saving, onPressed: _save),
    );
  }
}
