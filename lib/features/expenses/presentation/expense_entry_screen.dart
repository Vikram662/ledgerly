import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/photos.dart';
import '../../../core/widgets/amount_pad.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../jobs/presentation/job_picker.dart';
import '../../lock/app_lock_controller.dart';
import '../data/expenses_repository.dart';

/// PRD EX-01: amount → category → mode → Save.
class ExpenseEntryScreen extends ConsumerStatefulWidget {
  const ExpenseEntryScreen({super.key, this.jobId});

  final String? jobId;

  @override
  ConsumerState<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

class _ExpenseEntryScreenState extends ConsumerState<ExpenseEntryScreen> {
  String _amount = '';
  String? _categoryId;
  late String? _jobId = widget.jobId;
  String? _photoName;
  PaymentMode _mode = PaymentMode.cash;
  DateTime _date = dateOnly(DateTime.now());
  final _note = TextEditingController();
  bool _saving = false;

  bool _saved = false;

  @override
  void dispose() {
    _note.dispose();
    // Photo taken but expense not saved: do not leave the file behind.
    if (!_saved) deletePhoto(_photoName);
    super.dispose();
  }

  Future<void> _takePhoto(bool fromCamera) async {
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      final name = await captureBillPhoto(fromCamera: fromCamera);
      if (name == null) return;
      await deletePhoto(_photoName); // replace the previous one
      setState(() => _photoName = name);
    } catch (e) {
      if (mounted) showMessage(context, tr('Could not take photo: {e}', {'e': errorText(e)}));
    } finally {
      lock.suspendRelock = false;
    }
  }

  Future<void> _newCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('New category')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: tr('Category name')),
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
    final id = await ref.read(expensesRepositoryProvider).addCategory(name);
    setState(() => _categoryId = id);
  }

  Future<void> _save() async {
    final paise = parseRupeesToPaise(_amount);
    if (paise == null || paise <= 0) {
      showMessage(context, tr('Enter the amount'));
      return;
    }
    if (_categoryId == null) {
      showMessage(context, tr('Choose a category'));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(expensesRepositoryProvider).addExpense(
            categoryId: _categoryId!,
            amountPaise: paise,
            mode: _mode,
            date: _date,
            remarks: _note.text.trim().isEmpty ? null : _note.text.trim(),
            jobId: _jobId,
            photoName: _photoName,
          );
      _saved = true;
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, tr('✓ Expense {amount} saved', {'amount': formatPaise(paise)}));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, tr('Could not save: {e}', {'e': errorText(e)}));
    }
  }

  Future<void> _photoSheet() async {
    final choice = await showPickerSheet<String>(
      context,
      title: tr('Bill photo (optional)'),
      options: [
        'camera',
        'gallery',
        if (_photoName != null) 'view',
        if (_photoName != null) 'remove',
      ],
      label: (o) => switch (o) {
        'camera' => _photoName == null ? tr('Camera') : tr('Retake'),
        'gallery' => tr('Gallery'),
        'view' => tr('View'),
        _ => tr('Remove photo'),
      },
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'camera':
        await _takePhoto(true);
      case 'gallery':
        await _takePhoto(false);
      case 'view':
        showPhoto(context, _photoName!);
      default:
        await deletePhoto(_photoName);
        setState(() => _photoName = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoriesProvider).valueOrNull ?? const [];
    final paise = parseRupeesToPaise(_amount) ?? 0;
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(tr('New expense')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _photoName == null
                ? SmallOutlinedButton(
                    icon: Icons.photo_camera_outlined,
                    label: tr('Bill photo'),
                    onTap: _photoSheet,
                  )
                : InkWell(
                    onTap: _photoSheet,
                    child: PhotoThumb(name: _photoName!, size: 40),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                AmountDisplay(text: _amount, label: tr('Amount')),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.95,
                  children: [
                    for (final c in categories)
                      _CategoryTile(
                        name: c.name,
                        selected: _categoryId == c.id,
                        onTap: () => setState(() => _categoryId = c.id),
                      ),
                    _CategoryTile(
                      name: tr('New'),
                      icon: Icons.add,
                      selected: false,
                      onTap: _newCategory,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionLabel(tr('Paid by')),
                PaymentModeChips(
                  value: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _note,
                        decoration: InputDecoration(
                          hintText: tr("Note (optional)"),
                          isDense: true,
                          fillColor: AppColors.page,
                          prefixIcon: const Icon(
                            Icons.edit_note,
                            color: AppColors.muted,
                          ),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.small),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.small),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: TextButton(
                            onPressed: () async {
                              final picked = await pickDate(
                                context,
                                initial: _date,
                                last: DateTime.now(),
                              );
                              if (picked != null) {
                                setState(() => _date = dateOnly(picked));
                              }
                            },
                            child: Text(
                              _date == dateOnly(DateTime.now())
                                  ? tr("Today")
                                  : dayFormat.format(_date),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    JobPickerField(
                      jobId: _jobId,
                      compact: true,
                      onChanged: (id) => setState(() => _jobId = id),
                    ),
                  ],
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(color: AppColors.surface),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AmountPad(
                      value: _amount,
                      onChanged: (v) => setState(() => _amount = v),
                    ),
                    const SizedBox(height: 4),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : Text(paise > 0
                              ? tr('Save {amount}',
                                  {'amount': formatPaise(paise)})
                              : tr('Save expense')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.name,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.small),
        side: BorderSide(color: selected ? AppColors.ink : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon != null
                  ? Icon(icon, color: AppColors.muted)
                  : Text(
                      twoInitials(name),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : AppColors.inkSoft,
                      ),
                    ),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
