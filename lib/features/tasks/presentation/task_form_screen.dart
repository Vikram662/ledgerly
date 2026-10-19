import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/phone_field.dart';
import '../../../core/widgets/pickers.dart';
import '../../jobs/data/jobs_repository.dart';
import '../data/tasks_repository.dart';

class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, this.taskId});

  final String? taskId;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _personNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  TaskType _taskType = TaskType.siteVisit;
  String? _selectedJobId;
  DateTime _dueDate = DateTime.now();
  TimeOfDay _dueTime = const TimeOfDay(hour: 10, minute: 0);
  bool _isAlertActive = true;
  int? _intervalMinutes;
  bool _saving = false;
  bool _initialized = false;

  final List<int?> _intervalOptions = [null, 15, 30, 60, 120, 1440];

  String _intervalLabel(int? mins) {
    if (mins == null) return tr('At task time');
    if (mins < 60) return tr('{mins} min repeat', {'mins': mins});
    if (mins == 60) return tr('Every 1 hour');
    if (mins == 120) return tr('Every 2 hours');
    if (mins == 1440) return tr('Daily');
    return tr('{mins} min repeat', {'mins': mins});
  }

  @override
  void dispose() {
    _titleController.dispose();
    _personNameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _loadExisting(TaskReminder t) {
    _titleController.text = t.title;
    _taskType = t.taskType;
    _selectedJobId = t.jobId;
    _personNameController.text = t.personName ?? '';
    _phoneController.text = t.phone ?? '';
    _notesController.text = t.notes ?? '';
    final dt = DateTime.fromMillisecondsSinceEpoch(t.scheduledAt);
    _dueDate = dt;
    _dueTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
    _isAlertActive = t.isAlertActive;
    _intervalMinutes = t.intervalMinutes;
    _initialized = true;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dueTime,
    );
    if (picked != null) {
      setState(() => _dueTime = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final repo = ref.read(tasksRepositoryProvider);
    final scheduledAt = DateTime(
      _dueDate.year,
      _dueDate.month,
      _dueDate.day,
      _dueTime.hour,
      _dueTime.minute,
    );

    try {
      await repo.saveTask(
        id: widget.taskId,
        title: _titleController.text.trim(),
        taskType: _taskType,
        jobId: _selectedJobId,
        personName: _personNameController.text.trim().isEmpty
            ? null
            : _personNameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        scheduledAt: scheduledAt,
        intervalMinutes: _intervalMinutes,
        isAlertActive: _isAlertActive,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Failed to save task: {e}', {'e': errorText(e)}))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.taskId != null;
    final jobsAsync = ref.watch(jobsProvider);

    if (isEdit && !_initialized) {
      final taskAsync = ref.watch(taskByIdProvider(widget.taskId!));
      return taskAsync.when(
        data: (t) {
          if (t == null) {
            return Scaffold(
              appBar: AppBar(title: Text(tr('Task not found'))),
              body: Center(child: Text(tr('This task does not exist.'))),
            );
          }
          _loadExisting(t);
          return _buildForm(jobsAsync, isEdit);
        },
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: Text(tr('Error'))),
          body: Center(child: Text(tr('Error loading task: {e}', {'e': errorText(e)}))),
        ),
      );
    }

    return _buildForm(jobsAsync, isEdit);
  }

  Widget _buildForm(AsyncValue<List<JobListItem>> jobsAsync, bool isEdit) {
    final jobItems = jobsAsync.valueOrNull ?? [];
    final df = DateFormat('EEE, dd MMM yyyy', uiDateLocale);

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(isEdit ? tr('Edit task') : tr('New task')),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: tr('Delete task'),
              icon: const Icon(Icons.delete_outline, color: AppColors.dangerFill),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(tr('Delete Task?')),
                    content: Text(
                        tr('Are you sure you want to delete this task reminder?')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(tr('Cancel')),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.dangerFill),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(tr('Delete')),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await ref
                      .read(tasksRepositoryProvider)
                      .deleteTask(widget.taskId!);
                  if (mounted) context.pop();
                }
              },
            ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        label: isEdit ? tr('Update Task') : tr('Save task'),
        busy: _saving,
        onPressed: _save,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            LabeledField(
              label: tr('Task title'),
              child: TextFormField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText:
                      tr('e.g. Inspect plaster work, Call client for cheque'),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? tr('Enter a title') : null,
              ),
            ),
            LabeledField(
              label: tr('Category'),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in TaskType.values)
                    AppChip(
                      label: type.label,
                      selected: _taskType == type,
                      onTap: () => setState(() => _taskType = type),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: LabeledField(
                    label: tr('Date'),
                    child: TapField(value: df.format(_dueDate), onTap: _pickDate),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LabeledField(
                    label: tr('Time'),
                    child: TapField(
                      value: _dueTime.format(context),
                      icon: Icons.access_time,
                      onTap: _pickTime,
                    ),
                  ),
                ),
              ],
            ),
            PickerField(
              label: tr('Linked site / job (optional)'),
              icon: Icons.location_city_outlined,
              value: jobItems
                      .where((j) => j.job.id == _selectedJobId)
                      .firstOrNull
                      ?.job
                      .title ??
                  tr('No site linked'),
              onTap: () async {
                const none = '__none__';
                final picked = await showPickerSheet<String>(
                  context,
                  title: tr('Linked site / job (optional)'),
                  options: [none, for (final j in jobItems) j.job.id],
                  label: (id) => id == none
                      ? tr('No site linked')
                      : jobItems.firstWhere((j) => j.job.id == id).job.title,
                  selected: _selectedJobId ?? none,
                );
                if (picked != null) {
                  setState(() =>
                      _selectedJobId = picked == none ? null : picked);
                }
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: LabeledField(
                    label: tr('Contact person'),
                    child: TextFormField(
                      controller: _personNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          InputDecoration(hintText: tr('e.g. Ramesh Bhai')),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LabeledField(
                    label: tr('Phone'),
                    child: PhoneField(
                      controller: _phoneController,
                      name: _personNameController,
                      hint: '9876543210',
                      validate: false,
                      countryCode: false,
                    ),
                  ),
                ),
              ],
            ),
            Panel(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr('Ring at task time'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(tr('Push notification reminder')),
                value: _isAlertActive,
                onChanged: (v) => setState(() => _isAlertActive = v),
              ),
            ),
            if (_isAlertActive) ...[
              const SizedBox(height: 14),
              LabeledField(
                label: tr('Repeat'),
                child: ChipRow(
                  children: [
                    for (final mins in _intervalOptions)
                      AppChip(
                        label: _intervalLabel(mins),
                        selected: _intervalMinutes == mins,
                        onTap: () => setState(() => _intervalMinutes = mins),
                      ),
                  ],
                ),
              ),
            ] else
              const SizedBox(height: 14),
            LabeledField(
              label: tr('Notes'),
              optional: true,
              child: TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: tr('Enter any additional details or instructions...'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
