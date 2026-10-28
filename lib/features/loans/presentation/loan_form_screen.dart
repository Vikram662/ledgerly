import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/decimal.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/loans_repository.dart';
import '../domain/loan_calculator.dart';
import 'loan_widgets.dart';

/// New or edited loan: given or taken, person, amount, date, term, interest
/// and (for a given loan) which taken loan the money came from. Shows the
/// due date and the amount to get back as you type.
class LoanFormScreen extends ConsumerStatefulWidget {
  const LoanFormScreen({
    super.key,
    this.loanId,
    this.direction = LoanDirection.given,
    this.partyId,
  });

  final String? loanId;
  final LoanDirection direction;
  final String? partyId;

  @override
  ConsumerState<LoanFormScreen> createState() => _LoanFormScreenState();
}

class _LoanFormScreenState extends ConsumerState<LoanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _term = TextEditingController(text: '30');
  final _rate = TextEditingController();
  final _note = TextEditingController();
  late LoanDirection _direction = widget.direction;
  late String? _partyId = widget.partyId;
  String? _sourceLoanId;
  DateTime _start = dateOnly(DateTime.now());
  LoanPeriod _period = LoanPeriod.day;
  LoanRateKind _rateKind = LoanRateKind.fixed;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEdit => widget.loanId != null;

  @override
  void initState() {
    super.initState();
    for (final c in [_amount, _term, _rate]) {
      c.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final c in [_amount, _term, _rate, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  /// True while [_load] fills the fields during build, where setState is
  /// not allowed (the build already shows the new values).
  bool _filling = false;

  void _refresh() {
    if (!_filling) setState(() {});
  }

  int? get _principal => parseRupeesToPaise(_amount.text);
  int? get _termCount => int.tryParse(_term.text.trim());

  /// Paise per period, or basis points per period.
  int? get _rateValue => _rateKind == LoanRateKind.fixed
      ? parseRupeesToPaise(_rate.text)
      : parseScaled(_rate.text, 2);

  LoanTerms? get _terms {
    final principal = _principal, count = _termCount, rate = _rateValue;
    if (principal == null || principal <= 0) return null;
    if (count == null || count <= 0 || rate == null || rate < 0) return null;
    return LoanTerms(
      principalPaise: principal,
      start: _start,
      termCount: count,
      period: _period,
      rateKind: _rateKind,
      rateValue: rate,
    );
  }

  void _load(LoanView v) {
    final loan = v.loan;
    _loaded = true;
    _direction = loan.direction;
    _partyId = loan.partyId;
    _sourceLoanId = loan.sourceLoanId;
    _start = parseIsoDate(loan.startDate);
    _period = loan.period;
    _rateKind = loan.rateKind;
    _filling = true;
    try {
      _amount.text = paiseToInputText(loan.principalPaise);
      _term.text = '${loan.termCount}';
      _rate.text = loan.rateKind == LoanRateKind.fixed
          ? paiseToInputText(loan.rateValue)
          : formatScaled(loan.rateValue, 2);
      _note.text = loan.note ?? '';
    } finally {
      _filling = false;
    }
  }

  Future<void> _pickParty(List<LoanParty> parties) async {
    final picked = await showPickerSheet<LoanParty>(
      context,
      title: _direction == LoanDirection.given
          ? tr('Given to')
          : tr('Taken from'),
      options: parties,
      label: (p) => p.name,
      selected: parties.where((p) => p.id == _partyId).firstOrNull,
    );
    if (picked != null && mounted) setState(() => _partyId = picked.id);
  }

  Future<void> _newParty() async {
    final id = await context.push<String>(Routes.addLoanParty);
    if (id != null && mounted) setState(() => _partyId = id);
  }

  Future<void> _pickSource(List<LoanView> taken) async {
    const none = '';
    final picked = await showPickerSheet<String>(
      context,
      title: tr('Money from'),
      options: [none, for (final v in taken) v.loan.id],
      label: (id) {
        if (id == none) return tr('My own money');
        final v = taken.firstWhere((t) => t.loan.id == id);
        return '${v.party.name} · ${formatPaise(v.loan.principalPaise)}';
      },
      subtitle: (id) {
        if (id == none) return '';
        return rateLabel(taken.firstWhere((t) => t.loan.id == id).loan);
      },
      selected: _sourceLoanId ?? none,
    );
    if (picked != null && mounted) {
      setState(() => _sourceLoanId = picked == none ? null : picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_partyId == null) {
      showMessage(context, tr('Choose the person'));
      return;
    }
    final terms = _terms;
    if (terms == null) return;
    setState(() => _saving = true);
    try {
      final id = await ref.read(loansRepositoryProvider).saveLoan(
            id: widget.loanId,
            direction: _direction,
            partyId: _partyId!,
            principalPaise: terms.principalPaise,
            startDate: _start,
            termCount: terms.termCount,
            period: _period,
            rateKind: _rateKind,
            rateValue: terms.rateValue,
            sourceLoanId: _sourceLoanId,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, tr('Loan saved'));
      if (_isEdit) {
        context.pop();
      } else {
        context.pushReplacement(Routes.loan(id));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEdit && !_loaded) {
      final v = ref.watch(loanViewProvider(widget.loanId!)).valueOrNull;
      if (v == null) return const SkeletonPage();
      _load(v);
    }
    final parties = ref.watch(loanPartiesProvider).valueOrNull ?? const [];
    final party = parties.where((p) => p.id == _partyId).firstOrNull;
    final taken = (ref.watch(loanViewsProvider).valueOrNull ?? const [])
        .where((v) => !v.given && (v.open || v.loan.id == _sourceLoanId))
        .toList();
    final source = taken.where((v) => v.loan.id == _sourceLoanId).firstOrNull;
    final given = _direction == LoanDirection.given;
    final terms = _terms;
    final per = periodLabel(_period);
    String? requiredText(String? v) =>
        (v == null || v.trim().isEmpty) ? tr('Required') : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? tr('Edit loan') : tr('New loan')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            SegmentedTabs<LoanDirection>(
              value: _direction,
              options: {
                LoanDirection.given: tr('I gave (diya)'),
                LoanDirection.taken: tr('I took (liya)'),
              },
              onChanged: (d) => setState(() => _direction = d),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: PickerField(
                    label: given ? tr('Given to') : tr('Taken from'),
                    value: party?.name,
                    icon: Icons.person_outline,
                    onTap: () async {
                      if (parties.isEmpty) return _newParty();
                      await _pickParty(parties);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                AppIconButton(
                  icon: Icons.person_add_alt_1_outlined,
                  tooltip: tr('+ New person'),
                  onPressed: _newParty,
                ),
              ],
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: tr('Amount'),
              child: TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(prefixText: '₹ '),
                validator: (v) {
                  final p = parseRupeesToPaise(v ?? '');
                  return p == null || p <= 0 ? tr('Enter the amount') : null;
                },
              ),
            ),
            PickerField(
              label: given ? tr('Date given') : tr('Date taken'),
              value: dayFormat.format(_start),
              icon: Icons.event_outlined,
              onTap: () async {
                final picked = await pickDate(context, initial: _start);
                if (picked != null) setState(() => _start = dateOnly(picked));
              },
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: tr('For how long'),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: TextFormField(
                      controller: _term,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                          ? tr('Required')
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedTabs<LoanPeriod>(
                      value: _period,
                      options: {
                        LoanPeriod.day: tr('Days'),
                        LoanPeriod.month: tr('Months'),
                      },
                      onChanged: (p) => setState(() => _period = p),
                    ),
                  ),
                ],
              ),
            ),
            LabeledField(
              label: tr('Interest'),
              help: _rateKind == LoanRateKind.fixed
                  ? tr('Rupees per {period} on the whole amount, e.g. 400',
                      {'period': per})
                  : tr('Percent per {period}, e.g. 2', {'period': per}),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rate,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText:
                            _rateKind == LoanRateKind.fixed ? '₹ ' : null,
                        suffixText: _rateKind == LoanRateKind.fixed
                            ? '/ $per'
                            : '% / $per',
                      ),
                      validator: requiredText,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: SegmentedTabs<LoanRateKind>(
                      value: _rateKind,
                      options: const {
                        LoanRateKind.fixed: '₹',
                        LoanRateKind.percent: '%',
                      },
                      onChanged: (k) => setState(() => _rateKind = k),
                    ),
                  ),
                ],
              ),
            ),
            if (given) ...[
              PickerField(
                label: tr('Money from'),
                value: source == null
                    ? tr('My own money')
                    : '${source.party.name} · ${formatPaise(source.loan.principalPaise)}',
                icon: Icons.call_received,
                onTap: () => _pickSource(taken),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 14),
                child: Text(
                  tr('Pick the loan you took this money from to see this deal\'s profit.'),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ],
            LabeledField(
              label: tr('Note'),
              optional: true,
              child: TextFormField(controller: _note, maxLines: 2),
            ),
            if (terms != null) _Preview(terms: terms, given: given),
          ],
        ),
      ),
      bottomNavigationBar:
          BottomActionBar(label: tr('Save'), busy: _saving, onPressed: _save),
    );
  }
}

/// "Due 6 Oct 2026 · Interest ₹2,000 · Get back ₹1,02,000".
class _Preview extends StatelessWidget {
  const _Preview({required this.terms, required this.given});

  final LoanTerms terms;
  final bool given;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: FigureColumn(
              label: tr('Due on'),
              value: dayFormat.format(terms.dueDate),
            ),
          ),
          Expanded(
            child: FigureColumn(
              label: tr('Interest'),
              value: formatPaise(terms.termInterestPaise),
            ),
          ),
          Expanded(
            child: FigureColumn(
              label: given ? tr('To get back') : tr('To pay back'),
              value: formatPaise(terms.termTotalPaise),
              color: given ? AppColors.successText : AppColors.dangerText,
            ),
          ),
        ],
      ),
    );
  }
}
