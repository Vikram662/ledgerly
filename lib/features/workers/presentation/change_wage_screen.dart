import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/workers_repository.dart';

/// PRD WK-03: new wage from a date; history is kept.
class ChangeWageScreen extends ConsumerStatefulWidget {
  const ChangeWageScreen({super.key, required this.workerId});

  final String workerId;

  @override
  ConsumerState<ChangeWageScreen> createState() => _ChangeWageScreenState();
}

class _ChangeWageScreenState extends ConsumerState<ChangeWageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rate = TextEditingController();
  final _otRate = TextEditingController();
  WageModel _model = WageModel.daily;
  int _divisor = 30;
  DateTime _from = dateOnly(DateTime.now());
  bool _saving = false;
  bool _loaded = false;

  @override
  void dispose() {
    _rate.dispose();
    _otRate.dispose();
    super.dispose();
  }

  void _fill(WageHistory? current) {
    if (_loaded || current == null) return;
    _loaded = true;
    _model = current.model;
    _divisor = current.monthlyDivisor;
    if (current.ratePaise > 0) _rate.text = paiseToInputText(current.ratePaise);
    if (current.otRatePaise > 0) {
      _otRate.text = paiseToInputText(current.otRatePaise);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(workersRepositoryProvider).changeWage(
            workerId: widget.workerId,
            model: _model,
            ratePaise:
                _model == WageModel.piece ? 0 : parseRupeesToPaise(_rate.text)!,
            otRatePaise: parseRupeesToPaise(_otRate.text) ?? 0,
            monthlyDivisor: _divisor,
            effectiveFrom: _from,
          );
      if (!mounted) return;
      showMessage(context, tr('Wage updated'));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final history =
        ref.watch(wageHistoryProvider(widget.workerId)).valueOrNull ?? const [];
    final worker = ref.watch(workerProvider(widget.workerId)).valueOrNull;
    final today = isoDate(DateTime.now());
    final current =
        history.where((w) => w.effectiveFrom.compareTo(today) <= 0).firstOrNull;
    _fill(current);
    final amountStyle =
        AppText.tabular.copyWith(fontSize: 17, fontWeight: FontWeight.w700);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Change wage'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (worker != null)
              Panel(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    InitialsAvatar(worker.worker.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            worker.worker.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          if (current != null)
                            Text(
                              tr('Now {wage} · from {date}', {
                                'wage': wageLabel(current),
                                'date': dayFormat
                                    .format(parseIsoDate(current.effectiveFrom)),
                              }),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SegmentedTabs<WageModel>(
              value: _model,
              options: {
                WageModel.daily: tr('Daily'),
                WageModel.monthly: tr('Monthly'),
                WageModel.piece: tr('Piece-rate'),
              },
              onChanged: (model) => setState(() => _model = model),
            ),
            const SizedBox(height: 16),
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
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        style: amountStyle,
                        decoration: const InputDecoration(prefixText: '₹ '),
                        validator: (v) {
                          final p = parseRupeesToPaise(v ?? '');
                          return p == null || p <= 0 ? tr('Enter amount') : null;
                        },
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: amountStyle,
                      decoration: const InputDecoration(prefixText: '₹ '),
                    ),
                  ),
                ),
              ],
            ),
            if (_model == WageModel.monthly)
              LabeledField(
                label: tr('Per-day rate for monthly salary'),
                child: Wrap(
                  spacing: AppSizes.gap,
                  children: [
                    for (final (value, label) in [
                      (30, '÷ 30'),
                      (26, '÷ 26'),
                      (0, tr('÷ days in month')),
                    ])
                      ChoiceChip(
                        showCheckmark: false,
                        label: Text(label),
                        selected: _divisor == value,
                        onSelected: (_) => setState(() => _divisor = value),
                      ),
                  ],
                ),
              ),
            LabeledField(
              label: tr('New wage from'),
              help: tr('Days before this date keep the old rate.'),
              child: TapField(
                value: dayFormat.format(_from),
                onTap: () async {
                  final picked = await pickDate(context, initial: _from);
                  if (picked != null) setState(() => _from = dateOnly(picked));
                },
              ),
            ),
            if (history.isNotEmpty) ...[
              SectionLabel(tr('History')),
              Panel(
                child: Column(
                  children: [
                    for (var i = 0; i < history.length; i++)
                      _HistoryRow(
                        wage: history[i],
                        current: history[i].id == current?.id,
                        last: i == history.length - 1,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        label: tr('Save new wage'),
        busy: _saving,
        onPressed: _save,
      ),
    );
  }
}

/// One step of the wage timeline: a dot, a line down, rate and date.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.wage,
    required this.current,
    required this.last,
  });

  final WageHistory wage;
  final bool current;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final rate = wage.otRatePaise > 0
        ? '${wageLabel(wage)} · ${tr('OT {amount}', {'amount': formatPaise(wage.otRatePaise)})}'
        : wageLabel(wage);
    final from =
        tr('From {date}', {'date': dayFormat.format(parseIsoDate(wage.effectiveFrom))});
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: current ? AppColors.primary : AppColors.inputBorder,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: AppColors.divider),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rate,
                    style: AppText.tabular
                        .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    current ? '$from · ${tr('current')}' : from,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
