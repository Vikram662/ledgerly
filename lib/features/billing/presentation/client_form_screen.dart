import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/phone_field.dart';
import '../data/billing_repository.dart';

/// PRD BL-01: client name, phone, address.
class ClientFormScreen extends ConsumerStatefulWidget {
  const ClientFormScreen({super.key, this.clientId});

  final String? clientId;

  @override
  ConsumerState<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends ConsumerState<ClientFormScreen> {
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
    await ref.read(billingRepositoryProvider).saveClient(
          id: widget.clientId,
          name: _name.text.trim(),
          phone: normalizeIndianPhone(_phone.text),
          address: address.isEmpty ? null : address,
        );
    if (!mounted) return;
    showMessage(context, tr('Client saved'));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.clientId != null && !_loaded) {
      final client = ref.watch(clientProvider(widget.clientId!)).valueOrNull;
      if (client == null) {
        return const SkeletonPage();
      }
      _loaded = true;
      _name.text = client.client.name;
      _phone.text = client.client.phone == null
          ? ''
          : formatIndianPhone(client.client.phone!);
      _address.text = client.client.address ?? '';
    }

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
            widget.clientId == null ? tr('New client') : tr('Edit client')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            LabeledField(
              label: tr('Name'),
              child: TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(hintText: tr('Client name')),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? tr('Enter name') : null,
              ),
            ),
            LabeledField(
              label: tr('Mobile number'),
              optional: true,
              help: tr('Used for WhatsApp bills and payment reminders.'),
              child: PhoneField(controller: _phone, name: _name),
            ),
            LabeledField(
              label: tr('Address'),
              optional: true,
              child: TextFormField(
                controller: _address,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: tr('Shown on the bill')),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
          label: tr('Save client'), busy: _saving, onPressed: _save),
    );
  }
}
