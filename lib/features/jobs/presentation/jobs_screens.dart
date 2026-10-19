import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/photos.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../billing/presentation/billing_widgets.dart';
import '../data/jobs_repository.dart';

/// Status pill of a job (wireframe Jobs: Active is blue).
class JobStatusBadge extends StatelessWidget {
  const JobStatusBadge(this.status, {super.key});

  final JobStatus status;

  @override
  Widget build(BuildContext context) => AppBadge(
        jobStatusLabel(status),
        tone: switch (status) {
          JobStatus.planned => BadgeTone.neutral,
          JobStatus.inProgress => BadgeTone.info,
          JobStatus.completed => BadgeTone.success,
        },
      );
}

enum _JobFilter { active, done, all }

/// PRD JB-01: all jobs / sites, open ones first.
class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  _JobFilter _filter = _JobFilter.active;

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Jobs / Sites'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.addJob()),
        icon: const Icon(Icons.add),
        label: Text(tr('New job')),
      ),
      body: jobs.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => Center(child: Text(errorText(e))),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.location_city,
              title: tr('No jobs yet'),
              message:
                  tr('Add a site to track its bills and expenses together.'),
              actionLabel: tr('New job'),
              onAction: () => context.push(Routes.addJob()),
            );
          }
          final active = list
              .where((j) => j.job.status != JobStatus.completed)
              .toList();
          final done = list
              .where((j) => j.job.status == JobStatus.completed)
              .toList();
          final shown = switch (_filter) {
            _JobFilter.active => active,
            _JobFilter.done => done,
            _JobFilter.all => list,
          };
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              ChipRow(
                children: [
                  for (final (filter, label) in [
                    (
                      _JobFilter.active,
                      tr('Active · {count}', {'count': active.length})
                    ),
                    (
                      _JobFilter.done,
                      tr('Done · {count}', {'count': done.length})
                    ),
                    (_JobFilter.all, tr('All')),
                  ])
                    AppChip(
                      label: label,
                      selected: _filter == filter,
                      onTap: () => setState(() => _filter = filter),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(tr('Nothing here'),
                        style: const TextStyle(color: AppColors.muted)),
                  ),
                ),
              for (final item in shown) ...[
                _JobCard(item: item),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.item});

  final JobListItem item;

  @override
  Widget build(BuildContext context) {
    final job = item.job;
    final spent = item.expensesPaise + item.piecePaise;
    final profit = item.profitPaise;
    Widget figure(String label, int paise, Color color) => Expanded(
          child: FigureColumn(
            label: label,
            value: formatPaise(paise),
            color: color,
          ),
        );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(Routes.job(job.id)),
      child: Panel(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          item.clientName,
                          if (job.siteAddress != null) job.siteAddress!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                JobStatusBadge(job.status),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                figure(tr('Billed'), item.billedPaise, AppColors.ink),
                figure(tr('Expense'), spent, AppColors.ink),
                figure(
                  profit >= 0 ? tr('Profit') : tr('Loss'),
                  profit.abs(),
                  profit >= 0 ? AppColors.successText : AppColors.dangerText,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class JobFormScreen extends ConsumerStatefulWidget {
  const JobFormScreen({super.key, this.jobId, this.clientId});

  final String? jobId;
  final String? clientId;

  @override
  ConsumerState<JobFormScreen> createState() => _JobFormScreenState();
}

class _JobFormScreenState extends ConsumerState<JobFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _site = TextEditingController();
  final _contract = TextEditingController();
  late String? _clientId = widget.clientId;
  JobStatus _status = JobStatus.inProgress;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _site, _contract]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_clientId == null) {
      showMessage(context, tr('Choose a client'));
      return;
    }
    setState(() => _saving = true);
    final site = _site.text.trim();
    final id = await ref.read(jobsRepositoryProvider).saveJob(
          id: widget.jobId,
          clientId: _clientId!,
          title: _title.text.trim(),
          siteAddress: site.isEmpty ? null : site,
          status: _status,
          contractValuePaise: parseRupeesToPaise(_contract.text),
        );
    if (!mounted) return;
    if (widget.jobId == null) {
      context.pushReplacement(Routes.job(id));
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.jobId != null && !_loaded) {
      final detail = ref.watch(jobDetailProvider(widget.jobId!)).valueOrNull;
      if (detail == null) {
        return const SkeletonPage();
      }
      _loaded = true;
      final job = detail.job;
      _title.text = job.title;
      _site.text = job.siteAddress ?? '';
      _contract.text = job.contractValuePaise == null
          ? ''
          : paiseToInputText(job.contractValuePaise!);
      _clientId = job.clientId;
      _status = job.status;
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.jobId == null ? tr('New job') : tr('Edit job'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            LabeledField(
              label: tr('Job name'),
              child: TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                    hintText: tr('e.g. Sharma ji 2BHK wiring')),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? tr('Enter job name')
                    : null,
              ),
            ),
            ClientPickerField(
              clientId: _clientId,
              labeled: true,
              onChanged: (id) => setState(() => _clientId = id),
            ),
            LabeledField(
              label: tr('Site address'),
              optional: true,
              child: TextFormField(
                controller: _site,
                decoration:
                    InputDecoration(hintText: tr('Flat, building, area')),
              ),
            ),
            LabeledField(
              label: tr('Contract value'),
              optional: true,
              child: TextFormField(
                controller: _contract,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: '0',
                  prefixText: '₹ ',
                ),
                validator: (v) => v == null ||
                        v.trim().isEmpty ||
                        parseRupeesToPaise(v) != null
                    ? null
                    : tr('Enter a valid amount'),
              ),
            ),
            LabeledField(
              label: tr('Status'),
              child: Wrap(
                spacing: AppSizes.gap,
                runSpacing: AppSizes.gap,
                children: [
                  for (final s in JobStatus.values)
                    AppChip(
                      label: jobStatusLabel(s),
                      selected: _status == s,
                      onTap: () => setState(() => _status = s),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
          label: tr('Save job'), busy: _saving, onPressed: _save),
    );
  }
}

enum _JobRecords { bills, expenses, pieces }

/// PRD JB-01 / EX-03 (wireframe JobDetail): one site with its money summary,
/// quick actions and its bills / expenses / piece work.
class JobDetailScreen extends ConsumerStatefulWidget {
  const JobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen> {
  var _records = _JobRecords.bills;

  @override
  Widget build(BuildContext context) {
    final jobId = widget.jobId;
    final async = ref.watch(jobDetailProvider(jobId));
    final d = async.valueOrNull;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading ? const ListSkeleton() : const NotFoundBody(),
      );
    }
    final job = d.job;
    const grey = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.muted,
    );
    Widget list(List<Widget> rows, String none) => rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(none, textAlign: TextAlign.center, style: grey),
          )
        : CardList(children: rows);
    Widget amount(int paise) => Text(
          formatPaise(paise),
          style: AppText.tabular.copyWith(fontWeight: FontWeight.w800),
        );

    return Scaffold(
      appBar: AppBar(
        actions: [
          AppIconButton(
            icon: Icons.edit_outlined,
            tooltip: tr('Edit job'),
            onPressed: () => context.push(Routes.editJob(jobId)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: JobStatusBadge(job.status),
          ),
          const SizedBox(height: 8),
          Text(
            job.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          InkWell(
            onTap: () => context.push(Routes.client(d.client.id)),
            child: Text(
              [
                d.client.name,
                if (job.siteAddress != null) job.siteAddress!,
                if (job.contractValuePaise != null)
                  tr('Contract {amount}',
                      {'amount': formatPaise(job.contractValuePaise!)}),
              ].join(' · '),
              style: AppText.tabular.merge(grey),
            ),
          ),
          const SizedBox(height: 14),
          Panel(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                AmountRow(label: tr('Billed'), paise: d.billedPaise),
                AmountRow(
                  label: tr('Received'),
                  paise: d.receivedPaise,
                  color: AppColors.successText,
                ),
                AmountRow(
                    label: tr('Expenses'),
                    paise: d.expensesPaise,
                    prefix: '−'),
                AmountRow(
                    label: tr('Piece work'), paise: d.piecePaise, prefix: '−'),
                const Divider(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.profitPaise >= 0 ? tr('Profit') : tr('Loss'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      formatPaise(d.profitPaise.abs()),
                      style: AppText.tabular.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: d.profitPaise >= 0
                            ? AppColors.successText
                            : AppColors.dangerText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr('Daily-wage labour is not counted here yet.'),
                    style: grey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ActionButtons(actions: [
            (
              label: tr('+ New bill'),
              onTap: () => context.push(Routes.newDocument(
                    DocumentKind.invoice,
                    clientId: d.client.id,
                    jobId: jobId,
                  )),
            ),
            (
              label: tr('+ Expense'),
              onTap: () => context.push(Routes.expenseForJob(jobId)),
            ),
          ]),
          const SizedBox(height: 14),
          UnderlineTabs<_JobRecords>(
            value: _records,
            options: {
              _JobRecords.bills:
                  tr('Bills · {count}', {'count': d.bills.length}),
              _JobRecords.expenses:
                  tr('Expenses · {count}', {'count': d.expenses.length}),
              _JobRecords.pieces:
                  tr('Piece work · {count}', {'count': d.pieces.length}),
            },
            onChanged: (r) => setState(() => _records = r),
          ),
          const SizedBox(height: 14),
          switch (_records) {
            _JobRecords.bills => list([
                for (final b in d.bills) CompactDocumentRow(document: b),
              ], tr('No bills linked to this job.')),
            _JobRecords.expenses => list([
                for (final e in d.expenses)
                  ListTile(
                    leading: e.photoPath == null
                        ? null
                        : InkWell(
                            onTap: () => showPhoto(context, e.photoPath!),
                            child: PhotoThumb(name: e.photoPath!, size: 44),
                          ),
                    title: Text(e.remarks?.isNotEmpty == true
                        ? e.remarks!
                        : tr('Expense')),
                    subtitle: Text(dayFormat.format(parseIsoDate(e.date))),
                    trailing: amount(e.amountPaise),
                  ),
              ], tr('No expenses linked to this job.')),
            _JobRecords.pieces => list([
                for (final p in d.pieces)
                  ListTile(
                    title: Text(p.piece.description),
                    subtitle: Text([
                      p.workerName,
                      dayFormat.format(parseIsoDate(p.piece.date)),
                    ].join(' · ')),
                    trailing: amount(p.piece.amountPaise),
                    onTap: () => context.push(Routes.worker(p.piece.workerId)),
                  ),
              ], tr('No piece work on this job.')),
          },
        ],
      ),
    );
  }
}
