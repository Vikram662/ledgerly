import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/measurement.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/billing_repository.dart';
import '../domain/document_totals.dart';
import 'measurement_sheet.dart';

class LineEditResult {
  const LineEditResult.save(DraftLine this.line) : delete = false;
  const LineEditResult.delete()
      : line = null,
        delete = true;

  final DraftLine? line;
  final bool delete;
}

String lineTypeLabel(LineType type) => switch (type) {
      LineType.material => tr('Material'),
      LineType.labour => tr('Labour'),
      LineType.workRate => tr('Work-rate'),
      LineType.lumpSum => tr('Lump-sum'),
    };

Future<LineEditResult?> editLine(BuildContext context, {DraftLine? initial}) =>
    Navigator.of(context).push<LineEditResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _LineEditorScreen(initial: initial),
      ),
    );

/// PRD BL-03 / BL-04 / BL-06 / BL-16: one bill line.
class _LineEditorScreen extends ConsumerStatefulWidget {
  const _LineEditorScreen({this.initial});

  final DraftLine? initial;

  @override
  ConsumerState<_LineEditorScreen> createState() => _LineEditorScreenState();
}

class _LineEditorScreenState extends ConsumerState<_LineEditorScreen> {
  late LineType _type = widget.initial?.lineType ?? LineType.workRate;
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _qty = TextEditingController(
    text: widget.initial == null || widget.initial!.qtyMilli == 0
        ? ''
        : formatMilli(widget.initial!.qtyMilli),
  );
  late final _rate = TextEditingController(
    text: widget.initial == null || widget.initial!.ratePaise == 0
        ? ''
        : paiseToInputText(widget.initial!.ratePaise),
  );
  late String? _itemId = widget.initial?.itemId;
  late String? _unitId = widget.initial?.unitId;
  late String? _unitCode = widget.initial?.unitCode;
  late List<MeasurementEntry> _measurement =
      widget.initial?.measurement ?? const [];

  @override
  void initState() {
    super.initState();
    for (final c in [_qty, _rate]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _qty, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isLumpSum => _type == LineType.lumpSum;

  int get _qtyMilli =>
      _isLumpSum ? milliPerUnit : (parseQtyToMilli(_qty.text) ?? 0);

  int get _ratePaise => parseRupeesToPaise(_rate.text) ?? 0;

  ItemKind? get _kind => switch (_type) {
        LineType.material => ItemKind.material,
        LineType.labour => ItemKind.labour,
        LineType.workRate => ItemKind.workRate,
        LineType.lumpSum => null,
      };

  /// Rate-list items of the chosen line type.
  List<ItemWithUnit> _items(List<ItemWithUnit> all) {
    final kind = _kind;
    if (kind == null) return const [];
    return all.where((i) => i.item.kind == kind).toList();
  }

  void _useItem(ItemWithUnit picked) {
    setState(() {
      _itemId = picked.item.id;
      _name.text = picked.item.name;
      _unitId = picked.unit.id;
      _unitCode = picked.unit.code;
      if (picked.item.defaultRatePaise != null) {
        _rate.text = paiseToInputText(picked.item.defaultRatePaise!);
      }
    });
  }

  Future<void> _pickItem() async {
    final items = _items(ref.read(itemsProvider).valueOrNull ?? const []);
    final picked = await showPickerSheet<ItemWithUnit>(
      context,
      title: tr('Choose {type} item', {'type': lineTypeLabel(_type).toLowerCase()}),
      options: items,
      label: (i) => i.item.name,
      subtitle: (i) => [
        'per ${i.unit.name}',
        if (i.item.defaultRatePaise != null)
          tr('last rate {amount}', {'amount': formatPaise(i.item.defaultRatePaise!)}),
      ].join(' · '),
    );
    if (picked != null) _useItem(picked);
  }

  Future<void> _pickUnit() async {
    final units = ref.read(unitsProvider).valueOrNull ?? const <Unit>[];
    final picked = await showPickerSheet<Unit>(
      context,
      title: tr('Unit'),
      options: units,
      label: (u) => u.name,
      selected: units.where((u) => u.id == _unitId).firstOrNull,
    );
    if (picked != null) {
      setState(() {
        _unitId = picked.id;
        _unitCode = picked.code;
      });
    }
  }

  Future<void> _measure() async {
    final result = await showMeasurementSheet(context, _measurement,
        unit: _unitCode);
    if (result == null) return;
    setState(() {
      _measurement = result.entries;
      _qty.text = formatMilli(result.totalMilli);
    });
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, tr('Enter the item or work name'));
      return;
    }
    if (!_isLumpSum && _qtyMilli <= 0) {
      showMessage(context, tr('Enter quantity'));
      return;
    }
    if (_ratePaise <= 0) {
      showMessage(context, _isLumpSum ? tr('Enter amount') : tr('Enter rate'));
      return;
    }
    Navigator.of(context).pop(LineEditResult.save(DraftLine(
      lineType: _type,
      name: name,
      qtyMilli: _qtyMilli,
      ratePaise: _ratePaise,
      itemId: _itemId,
      unitId: _isLumpSum ? null : _unitId,
      unitCode: _isLumpSum ? null : _unitCode,
      measurement: _isLumpSum ? const [] : _measurement,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(unitsProvider).valueOrNull ?? const <Unit>[];
    final unitName = units.where((u) => u.id == _unitId).firstOrNull?.name;
    final items = _items(ref.watch(itemsProvider).valueOrNull ?? const []);
    final lastRate =
        items.where((i) => i.item.id == _itemId).firstOrNull?.item.defaultRatePaise;
    // A few chips to tap; the list icon in the field opens the full list.
    const chipCount = 6;

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(widget.initial == null ? tr('Add line') : tr('Edit line')),
        actions: [
          if (widget.initial != null) ...[
            AppIconButton(
              icon: Icons.delete_outline,
              tooltip: tr('Delete line'),
              onPressed: () =>
                  Navigator.of(context).pop(const LineEditResult.delete()),
            ),
            const SizedBox(width: 12),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SegmentedTabs<LineType>(
            value: _type,
            options: {for (final t in LineType.values) t: lineTypeLabel(t)},
            onChanged: (t) => setState(() {
              _type = t;
              _itemId = null;
            }),
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: _isLumpSum ? tr('Description') : tr('Item / work'),
            child: TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _isLumpSum ? null : tr('Choose from rate list'),
                suffixIcon: _isLumpSum
                    ? null
                    : IconButton(
                        tooltip: tr('Choose from rate list'),
                        icon: const Icon(Icons.list_alt),
                        onPressed: _pickItem,
                      ),
              ),
              onChanged: (_) => setState(() => _itemId = null),
            ),
          ),
          if (items.isNotEmpty) ...[
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Choose from rate list'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final i in items.take(chipCount))
                        AppChip(
                          label: i.item.defaultRatePaise == null
                              ? i.item.name
                              : '${i.item.name} · '
                                  '${formatPaise(i.item.defaultRatePaise!)}',
                          selected: i.item.id == _itemId,
                          onTap: () => _useItem(i),
                        ),
                      if (items.length > chipCount)
                        AppChip(label: tr('More…'), onTap: _pickItem),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (!_isLumpSum) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: tr('Quantity'),
                    bottomGap: 0,
                    child: TextField(
                      controller: _qty,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: AppText.tabular.copyWith(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PickerField(
                    label: tr('Unit'),
                    value: unitName,
                    onTap: _pickUnit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SmallOutlinedButton(
                  icon: Icons.straighten,
                  label: tr('Measure (L × W × H)'),
                  onTap: _measure,
                ),
                if (_measurement.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('From measurement: {count} rows',
                          {'count': _measurement.length}),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
          ],
          LabeledField(
            label: _isLumpSum
                ? tr('Amount')
                : unitName == null
                    ? tr('Rate')
                    : tr('Rate per {unit}', {'unit': unitName}),
            help: lastRate == null
                ? null
                : tr('last rate {amount}', {'amount': formatPaise(lastRate)}),
            child: TextField(
              controller: _rate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: AppText.tabular
                  .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(prefixText: '₹ '),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        label: tr('Done'),
        onPressed: _save,
        summaryLabel: tr('Line amount'),
        summaryValue: formatPaise(lineAmountPaise(_qtyMilli, _ratePaise)),
      ),
    );
  }
}
