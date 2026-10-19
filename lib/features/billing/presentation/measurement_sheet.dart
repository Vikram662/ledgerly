import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/measurement.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';

class MeasurementResult {
  const MeasurementResult(this.entries);

  final List<MeasurementEntry> entries;

  int get totalMilli => measurementTotalMilli(entries);
}

/// PRD BL-16: rows of nos × L × W × H, with deductions (doors, windows).
/// Returns null if cancelled.
/// [unit] (e.g. "sq.ft") is shown in the header and next to the total.
Future<MeasurementResult?> showMeasurementSheet(
  BuildContext context,
  List<MeasurementEntry> initial, {
  String? unit,
}) {
  return Navigator.of(context).push<MeasurementResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _MeasurementPage(initial: initial, unit: unit),
    ),
  );
}

class _Row {
  _Row({MeasurementEntry? entry, this.isDeduction = false})
      : label = TextEditingController(text: entry?.label ?? ''),
        nos = TextEditingController(text: '${entry?.nos ?? 1}'),
        length = TextEditingController(
            text: entry == null ? '' : formatMilli(entry.lengthMilli)),
        width = TextEditingController(
            text: entry?.widthMilli == null ? '' : formatMilli(entry!.widthMilli!)),
        height = TextEditingController(
            text: entry?.heightMilli == null
                ? ''
                : formatMilli(entry!.heightMilli!)) {
    if (entry != null) isDeduction = entry.isDeduction;
  }

  final TextEditingController label;
  final TextEditingController nos;
  final TextEditingController length;
  final TextEditingController width;
  final TextEditingController height;
  bool isDeduction;

  Iterable<TextEditingController> get controllers =>
      [label, nos, length, width, height];

  MeasurementEntry? toEntry() {
    final l = parseQtyToMilli(length.text);
    if (l == null || l <= 0) return null;
    return MeasurementEntry(
      label: label.text.trim(),
      nos: int.tryParse(nos.text.trim()) ?? 1,
      lengthMilli: l,
      widthMilli: parseQtyToMilli(width.text),
      heightMilli: parseQtyToMilli(height.text),
      isDeduction: isDeduction,
    );
  }

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}

class _MeasurementPage extends StatefulWidget {
  const _MeasurementPage({required this.initial, this.unit});

  final List<MeasurementEntry> initial;
  final String? unit;

  @override
  State<_MeasurementPage> createState() => _MeasurementPageState();
}

class _MeasurementPageState extends State<_MeasurementPage> {
  late final List<_Row> _rows = widget.initial.isEmpty
      ? [_Row()]
      : [for (final e in widget.initial) _Row(entry: e)];

  @override
  void initState() {
    super.initState();
    for (final row in _rows) {
      _listen(row);
    }
  }

  void _listen(_Row row) {
    for (final c in row.controllers) {
      c.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _add({bool deduction = false}) {
    final row = _Row(isDeduction: deduction);
    _listen(row);
    setState(() => _rows.add(row));
  }

  List<MeasurementEntry> get _entries =>
      [for (final r in _rows) r.toEntry()].whereType<MeasurementEntry>().toList();

  @override
  Widget build(BuildContext context) {
    final total = measurementTotalMilli(_entries);
    final unit = widget.unit;
    String withUnit(String qty) => unit == null ? qty : '$qty $unit';
    const head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: AppColors.muted,
    );
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(tr('Measurement')),
        actions: [
          if (unit != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(
            tr('Enter length, and width or height as needed. Use the same unit (ft or m) for all rows.'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _grid([
                  Text(tr('Nos'), textAlign: TextAlign.center, style: head),
                  const Text('L', textAlign: TextAlign.center, style: head),
                  const Text('W', textAlign: TextAlign.center, style: head),
                  const Text('H', textAlign: TextAlign.center, style: head),
                ], Text(tr('Total'), textAlign: TextAlign.right, style: head)),
                for (var i = 0; i < _rows.length; i++) ...[
                  const SizedBox(height: 12),
                  _rowView(i),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _AddButton(
                        icon: Icons.add,
                        label: tr('Add row'),
                        color: AppColors.primary,
                        onTap: _add,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AddButton(
                        icon: Icons.remove,
                        label: tr('Add deduction'),
                        color: AppColors.dangerText,
                        onTap: () => _add(deduction: true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Total'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          withUnit(formatMilli(total)),
                          style: AppText.tabular.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: total <= 0
                        ? null
                        : () => Navigator.of(context)
                            .pop(MeasurementResult(_entries)),
                    child: Text(
                      tr('Use total {total}', {'total': formatMilli(total)}),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Four equal columns (Nos, L, W, H) and a 72px total column.
  Widget _grid(List<Widget> cells, Widget total) => Row(
        children: [
          for (final cell in cells) ...[
            Expanded(child: cell),
            const SizedBox(width: 6),
          ],
          SizedBox(width: 72, child: total),
        ],
      );

  Widget _rowView(int index) {
    final row = _rows[index];
    final entry = row.toEntry();
    final deduction = row.isDeduction;
    final cellBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.inputBorder),
    );
    Widget cell(TextEditingController c) => SizedBox(
          height: 44,
          child: TextField(
            controller: c,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppText.tabular
                .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '–',
              hintStyle: const TextStyle(color: AppColors.inputBorder),
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: cellBorder,
              enabledBorder: cellBorder,
            ),
          ),
        );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (deduction)
              const Text('− ',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.dangerText)),
            Expanded(
              child: TextField(
                controller: row.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: deduction ? AppColors.dangerText : AppColors.ink,
                ),
                decoration: InputDecoration(
                  hintText: deduction
                      ? tr('Deduction (e.g. Door)')
                      : tr('Label (e.g. Hall wall)'),
                  isDense: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            if (_rows.length > 1)
              InkResponse(
                radius: 18,
                onTap: () {
                  final removed = _rows.removeAt(index);
                  setState(() {});
                  // Fields still hold the controllers until rebuilt.
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => removed.dispose());
                },
                child: Tooltip(
                  message: tr('Remove row'),
                  child: const Icon(Icons.close,
                      size: 18, color: AppColors.muted),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        _grid(
          [cell(row.nos), cell(row.length), cell(row.width), cell(row.height)],
          Text(
            entry == null
                ? '—'
                : '${deduction ? '−' : ''}${formatMilli(entry.qtyMilli)}',
            textAlign: TextAlign.right,
            style: AppText.tabular.copyWith(
              fontWeight: FontWeight.w800,
              color: deduction ? AppColors.dangerText : AppColors.ink,
            ),
          ),
        ),
      ],
    );
    if (!deduction) return content;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.dangerSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: content,
    );
  }
}

/// "+ Add row" / "− Add deduction" outlined button.
class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        side: const BorderSide(color: AppColors.faint, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
