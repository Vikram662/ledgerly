import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/audit.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/presentation/measurement_sheet.dart';
import '../../jobs/presentation/job_picker.dart';
import '../../workers/presentation/worker_picker.dart';
import '../data/khata_repository.dart';

/// PRD WK-05: piece-rate / theka work — kaam × qty × rate.
class PieceWorkScreen extends ConsumerStatefulWidget {
  const PieceWorkScreen({super.key, this.workerId});

  final String? workerId;

  @override
  ConsumerState<PieceWorkScreen> createState() => _PieceWorkScreenState();
}

class _PieceWorkScreenState extends ConsumerState<PieceWorkScreen> {
  late String? _workerId = widget.workerId;
  final _description = TextEditingController();
  final _qty = TextEditingController();
  final _rate = TextEditingController();
  String? _itemId;
  String? _jobId;
  Unit? _unit;
  DateTime _date = dateOnly(DateTime.now());
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_qty, _rate]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_description, _qty, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _amount {
    final qty = parseQtyToMilli(_qty.text);
    final rate = parseRupeesToPaise(_rate.text);
    return qty == null || rate == null ? 0 : lineAmountPaise(qty, rate);
  }

  /// Labour and work-rate items from the rate list.
  List<ItemWithUnit> _workItems(List<ItemWithUnit> all) =>
      all.where((i) => i.item.kind != ItemKind.material).toList();

  void _useItem(ItemWithUnit picked) {
    setState(() {
      _itemId = picked.item.id;
      _description.text = picked.item.name;
      _unit = picked.unit;
      if (picked.item.defaultRatePaise != null) {
        _rate.text = paiseToInputText(picked.item.defaultRatePaise!);
      }
    });
  }

  Future<void> _pickItem() async {
    final items = _workItems(ref.read(itemsProvider).valueOrNull ?? const []);
    final picked = await showPickerSheet<ItemWithUnit>(
      context,
      title: tr('Choose work'),
      options: items,
      label: (i) => i.item.name,
      subtitle: (i) => tr('per {name}', {'name': i.unit.name}),
    );
    if (picked != null) _useItem(picked);
  }

  Future<void> _pickUnit() async {
    final units = ref.read(unitsProvider).valueOrNull ?? const [];
    final picked = await showPickerSheet<Unit>(
      context,
      title: tr('Unit'),
      options: units,
      label: (u) => u.name,
      selected: _unit,
    );
    if (picked != null) setState(() => _unit = picked);
  }

  Future<void> _measure() async {
    final total = await showMeasurementSheet(context, const [],
        unit: _unit?.code);
    if (total != null) _qty.text = formatMilli(total.totalMilli);
  }

  Future<void> _save() async {
    final qty = parseQtyToMilli(_qty.text);
    final rate = parseRupeesToPaise(_rate.text);
    final description = _description.text.trim();
    final problem = _workerId == null
        ? tr('Choose a worker')
        : description.isEmpty
            ? tr('Enter the work')
            : qty == null || qty <= 0
                ? tr('Enter quantity')
                : rate == null || rate <= 0
                    ? tr('Enter rate')
                    : null;
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(khataRepositoryProvider).addPieceWork(
            workerId: _workerId!,
            date: _date,
            description: description,
            qtyMilli: qty!,
            ratePaise: rate!,
            itemId: _itemId,
            unitId: _unit?.id,
            jobId: _jobId,
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, tr('Piece work saved: {amount}', {'amount': formatPaise(_amount)}));
      context.pop();
    } on PeriodLockedException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, tr(e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final amountStyle =
        AppText.tabular.copyWith(fontSize: 17, fontWeight: FontWeight.w700);
    final items = _workItems(ref.watch(itemsProvider).valueOrNull ?? const []);
    // A few chips to tap; the list icon in the field opens the full list.
    const chipCount = 6;
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(tr('Piece work')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          WorkerPickerField(
            workerId: _workerId,
            onChanged: (w) => setState(() => _workerId = w.worker.id),
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: tr('Work'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (items.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final i in items.take(chipCount))
                        AppChip(
                          label: i.item.defaultRatePaise == null
                              ? i.item.name
                              : '${i.item.name} · '
                                  '${formatPaise(i.item.defaultRatePaise!)}/${i.unit.code}',
                          selected: i.item.id == _itemId,
                          onTap: () => _useItem(i),
                        ),
                      if (items.length > chipCount)
                        AppChip(label: tr('More…'), onTap: _pickItem),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _description,
                  decoration: InputDecoration(
                    hintText: tr('e.g. Floor tiling'),
                    suffixIcon: IconButton(
                      tooltip: tr('Choose from list'),
                      icon: const Icon(Icons.list),
                      onPressed: _pickItem,
                    ),
                  ),
                  onChanged: (_) => setState(() => _itemId = null),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: LabeledField(
                  label: tr('Quantity'),
                  child: TextField(
                    controller: _qty,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: amountStyle,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: PickerField(
                    label: tr('Unit'),
                    value: _unit?.name,
                    onTap: _pickUnit,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: SmallOutlinedButton(
              icon: Icons.straighten,
              label: tr('Measure (L × W × H)'),
              onTap: _measure,
            ),
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: _unit == null
                ? tr('Rate')
                : tr('Rate per {unit}', {'unit': _unit!.name}),
            child: TextField(
              controller: _rate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: amountStyle,
              decoration: const InputDecoration(prefixText: '₹ '),
            ),
          ),
          LabeledField(
            label: tr('Date'),
            child: TapField(
              value: dayFormat.format(_date),
              onTap: () async {
                final picked = await pickDate(context,
                    initial: _date, last: DateTime.now());
                if (picked != null) setState(() => _date = dateOnly(picked));
              },
            ),
          ),
          JobPickerField(
            jobId: _jobId,
            onChanged: (id) => setState(() => _jobId = id),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        label: tr('Save'),
        busy: _saving,
        onPressed: _save,
        summaryLabel: tr('Amount'),
        summaryValue: formatPaise(_amount),
      ),
    );
  }
}
