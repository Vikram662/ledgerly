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
import '../../../core/utils/money.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/billing_repository.dart';
import '../../jobs/presentation/job_picker.dart';
import '../domain/document_totals.dart';
import 'billing_widgets.dart';
import 'line_editor_screen.dart';

/// Create or edit a bill / quotation (PRD BL-02..BL-07).
class DocumentEditorScreen extends ConsumerStatefulWidget {
  const DocumentEditorScreen({
    super.key,
    required this.kind,
    this.documentId,
    this.clientId,
    this.jobId,
  });

  final DocumentKind kind;
  final String? documentId;
  final String? clientId;
  final String? jobId;

  @override
  ConsumerState<DocumentEditorScreen> createState() =>
      _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends ConsumerState<DocumentEditorScreen> {
  late DocumentKind _kind = widget.kind;
  late String? _clientId = widget.clientId;
  late String? _jobId = widget.jobId;
  DateTime _date = dateOnly(DateTime.now());
  DateTime? _dueDate;
  final List<DraftLine> _lines = [];
  bool _percentDiscount = false;
  final _discount = TextEditingController();
  bool _roundOff = true;
  final _notes = TextEditingController();
  final _terms = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _number;

  @override
  void initState() {
    super.initState();
    _discount.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    for (final c in [_discount, _notes, _terms]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(billingRepositoryProvider);
    if (widget.documentId == null) {
      _terms.text = await repo.defaultTerms();
    } else {
      final detail = await repo.watchDocument(widget.documentId!).first;
      if (detail != null) {
        final d = detail.document;
        _kind = d.kind;
        _number = d.number;
        _clientId = d.clientId;
        _jobId = d.jobId;
        _date = parseIsoDate(d.date);
        _dueDate = d.dueDate == null ? null : parseIsoDate(d.dueDate!);
        _lines.addAll(detail.lines.map((l) => l.toDraft()));
        _percentDiscount = d.discountPercentBp != null;
        _discount.text = d.discountPercentBp != null
            ? paiseToInputText(d.discountPercentBp!)
            : (d.discountPaise == 0 ? '' : paiseToInputText(d.discountPaise));
        _roundOff = d.roundOff;
        _notes.text = d.notes ?? '';
        _terms.text = d.terms ?? '';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  DocumentDraft _draft() {
    final discountValue = parseScaledDiscount(_discount.text);
    return DocumentDraft(
      id: widget.documentId,
      kind: _kind,
      clientId: _clientId ?? '',
      jobId: _jobId,
      date: _date,
      dueDate: _dueDate,
      lines: List.of(_lines),
      discountPercentBp: _percentDiscount ? discountValue : null,
      discountPaise: _percentDiscount ? 0 : discountValue,
      roundOff: _roundOff,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      terms: _terms.text.trim().isEmpty ? null : _terms.text.trim(),
    );
  }

  /// Rupees or percent, both with 2 decimals → integer (paise / basis points).
  static int parseScaledDiscount(String text) =>
      parseRupeesToPaise(text.trim().isEmpty ? '0' : text) ?? 0;

  Future<void> _addLine() async {
    final result = await editLine(context);
    if (result?.line != null) setState(() => _lines.add(result!.line!));
  }

  Future<void> _editLine(int index) async {
    final result = await editLine(context, initial: _lines[index]);
    if (result == null) return;
    setState(() {
      if (result.delete) {
        _lines.removeAt(index);
      } else {
        _lines[index] = result.line!;
      }
    });
  }

  Future<void> _useTemplate() async {
    final templates = ref.read(templatesProvider).valueOrNull ?? const [];
    final picked = await showPickerSheet<BillTemplate>(
      context,
      title: tr('Start from template'),
      options: templates,
      label: (t) => t.name,
    );
    if (picked == null) return;
    final lines =
        await ref.read(billingRepositoryProvider).linesFromTemplate(picked);
    setState(() => _lines.addAll(lines));
    if (mounted && lines.any((l) => l.qtyMilli == 0)) {
      showMessage(context, tr('Template added. Tap each line to enter quantity.'));
    }
  }

  Future<void> _save() async {
    if (_clientId == null) {
      showMessage(context, tr('Choose a client'));
      return;
    }
    if (_lines.isEmpty) {
      showMessage(context, tr('Add at least one line'));
      return;
    }
    final blank = _lines.indexWhere((l) => l.qtyMilli <= 0 || l.ratePaise <= 0);
    if (blank >= 0) {
      showMessage(context, tr('Line {blank}: enter quantity and rate', {'blank': blank + 1}));
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref.read(billingRepositoryProvider).saveDocument(_draft());
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (widget.documentId == null) {
        context.pushReplacement(Routes.document(id));
      } else {
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, tr('Could not save: {e}', {'e': errorText(e)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInvoice = _kind == DocumentKind.invoice;
    final isNew = widget.documentId == null;
    final title = isNew
        ? (isInvoice ? tr('New bill') : tr('New quotation'))
        : tr('Edit {number}', {'number': _number ?? ''});
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const ListSkeleton(),
      );
    }
    final totals = _draft().totals;

    return Scaffold(
      appBar: AppBar(leading: const CloseButton(), title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (isNew) ...[
            SegmentedTabs<DocumentKind>(
              value: _kind,
              options: {
                DocumentKind.invoice: tr('Bill'),
                DocumentKind.quotation: tr('Quotation'),
              },
              onChanged: (kind) => setState(() => _kind = kind),
            ),
            const SizedBox(height: 14),
          ],
          ClientPickerField(
            clientId: _clientId,
            onChanged: (id) => setState(() {
              if (id != _clientId) _jobId = null;
              _clientId = id;
            }),
          ),
          const SizedBox(height: 14),
          if (_clientId != null) ...[
            JobPickerField(
              clientId: _clientId,
              jobId: _jobId,
              onChanged: (id) => setState(() => _jobId = id),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: tr('Date'),
                  bottomGap: 0,
                  child: TapField(
                    value: dayFormat.format(_date),
                    onTap: () async {
                      final picked = await pickDate(context, initial: _date);
                      if (picked != null) {
                        setState(() => _date = dateOnly(picked));
                      }
                    },
                  ),
                ),
              ),
              if (isInvoice) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: LabeledField(
                    label: tr('Due date'),
                    bottomGap: 0,
                    child: TapField(
                      value:
                          _dueDate == null ? null : dayFormat.format(_dueDate!),
                      placeholder: tr('None'),
                      onTap: () async {
                        final picked = await pickDate(context,
                            initial: _dueDate ?? _date);
                        if (picked != null) {
                          setState(() => _dueDate = dateOnly(picked));
                        }
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SectionLabel(
            tr('Items & work'),
            trailing: _lines.isEmpty
                ? TextButton(
                    onPressed: _useTemplate,
                    child: Text(tr('Start from template')),
                  )
                : null,
          ),
          if (_lines.isNotEmpty)
            CardList(
              children: [
                for (var i = 0; i < _lines.length; i++)
                  _LineRow(line: _lines[i], onTap: () => _editLine(i)),
              ],
            ),
          const SizedBox(height: 8),
          _DashedButton(
            icon: Icons.add,
            label: tr('Add line'),
            onTap: _addLine,
          ),
          const SizedBox(height: 8),
          SectionLabel(tr('Discount & total')),
          Panel(
            child: Column(
              children: [
                AmountRow(label: tr('Subtotal'), paise: totals.subtotalPaise),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('Discount'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      child: SegmentedTabs<bool>(
                        value: _percentDiscount,
                        options: const {false: '₹', true: '%'},
                        onChanged: (v) => setState(() => _percentDiscount = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: _discount,
                        textAlign: TextAlign.end,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: AppText.tabular.copyWith(
                            fontSize: 15, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '0',
                        ),
                      ),
                    ),
                  ],
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  tileColor: Colors.transparent,
                  title: Text(tr('Round off to nearest rupee')),
                  value: _roundOff,
                  onChanged: (v) => setState(() => _roundOff = v ?? false),
                ),
                if (totals.discountPaise != 0)
                  AmountRow(
                    label: tr('Discount'),
                    paise: totals.discountPaise,
                    prefix: '− ',
                  ),
                if (totals.roundOffPaise != 0)
                  AmountRow(label: tr('Round off'), paise: totals.roundOffPaise),
                const Divider(),
                AmountRow(
                    label: tr('Total'), paise: totals.totalPaise, bold: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SectionLabel(tr('Notes & terms')),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: InputDecoration(hintText: tr('Notes (optional)')),
          ),
          const SizedBox(height: 12),
          LabeledField(
            label: tr('Terms & conditions (one per line)'),
            child: TextField(controller: _terms, maxLines: 5),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        label: tr('Save {amount}', {'amount': formatPaise(totals.totalPaise)}),
        busy: _saving,
        onPressed: _save,
        summaryLabel: tr('Total'),
        summaryValue: formatPaise(totals.totalPaise),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.onTap});

  final DraftLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final incomplete = line.lineType != LineType.lumpSum &&
        (line.qtyMilli <= 0 || line.ratePaise <= 0);
    final detail = line.lineType == LineType.lumpSum
        ? tr('Lump-sum')
        : '${formatMilli(line.qtyMilli)} ${line.unitCode ?? ''} × '
            '${formatPaise(line.ratePaise)}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    incomplete ? tr('Tap to enter quantity and rate') : detail,
                    style: AppText.tabular.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          incomplete ? AppColors.warningText : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              incomplete ? '—' : formatPaise(line.amountPaise),
              style: AppText.tabular.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: incomplete ? AppColors.faint : AppColors.ink,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}

/// 52px button with a dashed-looking grey border ("+ Add line").
class _DashedButton extends StatelessWidget {
  const _DashedButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSizes.tapSecondary),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
