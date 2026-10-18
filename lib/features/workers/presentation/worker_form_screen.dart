import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/utils/upi.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/workers_repository.dart';

/// PRD WK-01 / WK-02: add a worker, or edit name/phone/role/UPI.
/// Wage changes go through [ChangeWageScreen] to keep history.
class WorkerFormScreen extends ConsumerStatefulWidget {
  const WorkerFormScreen({super.key, this.workerId});

  final String? workerId;

  @override
  ConsumerState<WorkerFormScreen> createState() => _WorkerFormScreenState();
}

class _WorkerFormScreenState extends ConsumerState<WorkerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _upi = TextEditingController();
  final _rate = TextEditingController();
  final _otRate = TextEditingController();
  String? _roleId;
  WageModel _model = WageModel.daily;
  DateTime _joinDate = dateOnly(DateTime.now());
  bool _saving = false;
  bool _loaded = false;

  bool get _isEdit => widget.workerId != null;

  @override
  void dispose() {
    for (final c in [_name, _phone, _upi, _rate, _otRate]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fillFrom(WorkerListItem item) {
    if (_loaded) return;
    _loaded = true;
    final w = item.worker;
    _name.text = w.name;
    _phone.text = w.phone == null ? '' : formatIndianPhone(w.phone!);
    _upi.text = w.upiId ?? '';
    _roleId = w.roleId;
    _joinDate = parseIsoDate(w.joinDate);
  }

  String? _validateAmount(String? value, {required bool isRequired}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return isRequired ? tr('Enter amount') : null;
    final paise = parseRupeesToPaise(text);
    if (paise == null || paise < 0) return tr('Enter a valid amount');
    if (isRequired && paise == 0) return tr('Enter amount');
    return null;
  }

  Future<void> _addRole() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('New role')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: tr('Role name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(tr('Add')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final id = await ref.read(workersRepositoryProvider).addRole(name);
    setState(() => _roleId = id);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(workersRepositoryProvider);
    final name = _name.text.trim();
    final upi = _upi.text.trim();
    try {
      if (_isEdit) {
        await repo.updateWorker(
          id: widget.workerId!,
          name: name,
          phone: normalizeIndianPhone(_phone.text),
          roleId: _roleId,
          upiId: upi.isEmpty ? null : upi,
        );
      } else {
        final settings = await ref.read(appSettingsProvider.future);
        await repo.addWorker(NewWorker(
          name: name,
          phone: normalizeIndianPhone(_phone.text),
          roleId: _roleId,
          upiId: upi.isEmpty ? null : upi,
          joinDate: _joinDate,
          wageModel: _model,
          ratePaise:
              _model == WageModel.piece ? 0 : parseRupeesToPaise(_rate.text)!,
          otRatePaise: parseRupeesToPaise(_otRate.text) ?? 0,
          monthlyDivisor: settings.monthlyDivisor,
        ));
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(
          context, _isEdit ? tr('Saved') : tr('{name} added', {'name': name}));
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(
          context,
          tr('Could not save. Please try again. ({error})',
              {'error': errorText(error)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final personal = ref.watch(userTypeProvider).isFree;
    if (_isEdit) {
      final item = ref.watch(workerProvider(widget.workerId!)).valueOrNull;
      if (item == null) {
        return const SkeletonPage();
      }
      _fillFrom(item);
    }
    final roles = ref.watch(rolesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(_isEdit
            ? (personal ? tr('Edit person') : tr('Edit worker'))
            : (personal ? tr('Add person') : tr('Add worker'))),
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
                decoration: InputDecoration(hintText: tr('Worker name')),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? tr('Enter name')
                    : null,
              ),
            ),
            LabeledField(
              label: tr('Mobile number'),
              optional: true,
              child: TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: tr('10-digit number'),
                  prefixIcon: const PhoneCountryCode(),
                ),
                validator: (value) => (value == null ||
                        value.trim().isEmpty ||
                        normalizeIndianPhone(value) != null)
                    ? null
                    : tr('Enter a valid 10-digit mobile number'),
              ),
            ),
            LabeledField(
              label: tr('Role'),
              child: roles.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text(tr('Could not load roles: {error}',
                    {'error': errorText(error)})),
                data: (list) => Wrap(
                  spacing: AppSizes.gap,
                  runSpacing: AppSizes.gap,
                  children: [
                    for (final role in list)
                      ChoiceChip(
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: _roleId == role.id
                              ? Colors.white
                              : AppColors.inkSoft,
                          fontWeight: FontWeight.w700,
                        ),
                        label: Text(role.name),
                        selected: _roleId == role.id,
                        onSelected: (selected) =>
                            setState(() => _roleId = selected ? role.id : null),
                      ),
                    ActionChip(
                      label: Text(tr('+ New role')),
                      onPressed: _addRole,
                    ),
                  ],
                ),
              ),
            ),
            if (!_isEdit) ...[
              SectionLabel(tr('Wage')),
              SegmentedTabs<WageModel>(
                value: _model,
                options: {
                  WageModel.daily: tr('Daily'),
                  WageModel.monthly: tr('Monthly'),
                  WageModel.piece: tr('Piece-rate'),
                },
                onChanged: (model) => setState(() => _model = model),
              ),
              const SizedBox(height: 14),
              if (_model == WageModel.piece)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    tr('Rate is entered with each piece-work entry (e.g. per sq.ft).'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_model != WageModel.piece) ...[
                    Expanded(
                      child: LabeledField(
                        label: _model == WageModel.daily
                            ? tr('Rate per day')
                            : tr('Salary per month'),
                        child: TextFormField(
                          controller: _rate,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: AppText.tabular.copyWith(
                              fontSize: 17, fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(prefixText: '₹ '),
                          validator: (v) =>
                              _validateAmount(v, isRequired: true),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: LabeledField(
                      label: tr('OT per hour'),
                      optional: true,
                      child: TextFormField(
                        controller: _otRate,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: AppText.tabular.copyWith(
                            fontSize: 17, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(prefixText: '₹ '),
                        validator: (v) => _validateAmount(v, isRequired: false),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isEdit) ...[
                  Expanded(
                    child: LabeledField(
                      label: tr('Joining date'),
                      child: TapField(
                        value: dayFormat.format(_joinDate),
                        onTap: () async {
                          final picked = await pickDate(
                            context,
                            initial: _joinDate,
                            last: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() => _joinDate = dateOnly(picked));
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: LabeledField(
                    label: tr('UPI ID'),
                    optional: true,
                    child: TextFormField(
                      controller: _upi,
                      decoration:
                          const InputDecoration(hintText: 'name@okaxis'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty || isValidUpiId(v))
                              ? null
                              : tr('Enter a UPI ID like name@okaxis'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        label: _isEdit ? tr('Save') : tr('Save worker'),
        busy: _saving,
        onPressed: _save,
      ),
    );
  }
}
