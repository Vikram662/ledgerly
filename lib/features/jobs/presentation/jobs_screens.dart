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

StatusChip jobStatusChip(JobStatus status) => switch (status) {
      JobStatus.planned => StatusChip(
          label: jobStatusLabel(status),
          color: AppColors.slate600,
          icon: Icons.schedule,
        ),
      JobStatus.inProgress => StatusChip(
          label: jobStatusLabel(status),
          color: AppColors.blue700,
          icon: Icons.construction,
        ),
      JobStatus.completed => StatusChip(
          label: jobStatusLabel(status),
          color: AppColors.successText,
          icon: Icons.check_circle,
        ),
    };

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
      bottomNavigationBar: BottomActionBar(
        label: tr('New job'),
        onPressed: () => context.push(Routes.addJob()),
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              SegmentedTabs<_JobFilter>(
                value: _filter,
                options: {
                  _JobFilter.active:
                      tr('Active · {count}', {'count': active.length}),
                  _JobFilter.done:
                      tr('Done · {count}', {'count': done.length}),
                  _JobFilter.all: tr('All'),
                },
                onChanged: (f) => setState(() => _filter = f),
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
    final (bg, fg) = switch (job.status) {
      JobStatus.planned => (AppColors.track, AppColors.inkSoft),
      JobStatus.inProgress => (AppColors.successSurface, AppColors.successText),
      JobStatus.completed => (AppColors.primarySurface, AppColors.primary),
    };
    final spent = item.expensesPaise + item.piecePaise;
    final profit = item.profitPaise;
    Widget figure(String label, int paise, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
              Text(
                formatPaise(paise),
                style: AppText.tabular.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
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
                TagBadge(jobStatusLabel(job.status), color: bg, textColor: fg),
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
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            ClientPickerField(
              clientId: _clientId,
              onChanged: (id) => setState(() => _clientId = id),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr('Job name'),
                hintText: tr('e.g. Sharma ji 2BHK wiring'),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? tr('Enter job name') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _site,
              maxLines: 2,
              decoration:
                  InputDecoration(labelText: tr('Site address (optional)')),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contract,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('Contract value (optional)'),
                prefixText: '₹ ',
              ),
              validator: (v) => v == null ||
                      v.trim().isEmpty ||
                      parseRupeesToPaise(v) != null
                  ? null
                  : tr('Enter a valid amount'),
            ),
            const SizedBox(height: 16),
            SectionLabel(tr('Status')),
            SegmentedTabs<JobStatus>(
              value: _status,
              options: {
                for (final s in JobStatus.values) s: jobStatusLabel(s),
              },
              onChanged: (s) => setState(() => _status = s),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          BottomActionBar(label: tr('Save'), busy: _saving, onPressed: _save),
    );
  }
}

/// PRD JB-01 / EX-03: one site with its bills, expenses and rough profit.
class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(jobDetailProvider(jobId));
    final d = async.valueOrNull;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const ListSkeleton()
            : const NotFoundBody(),
      );
    }
    final job = d.job;

    return Scaffold(
      appBar: AppBar(
        title: Text(job.title),
        actions: [
          AppIconButton(
            icon: Icons.edit_outlined,
            tooltip: tr('Edit'),
            onPressed: () => context.push(Routes.editJob(jobId)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              jobStatusChip(job.status),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => context.push(Routes.client(d.client.id)),
                  child: Text(d.client.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
            ],
          ),
          if (job.siteAddress != null) ...[
            const SizedBox(height: 4),
            Text(job.siteAddress!),
          ],
          const SizedBox(height: 12),
          Panel(
            child: Column(
              children: [
                if (job.contractValuePaise != null)
                  AmountRow(label: tr('Contract value'), paise: job.contractValuePaise!),
                AmountRow(label: tr('Billed'), paise: d.billedPaise),
                AmountRow(
                  label: tr('Received'),
                  paise: d.receivedPaise,
                  color: AppColors.successText,
                ),
                const Divider(),
                AmountRow(label: tr('Expenses'), paise: d.expensesPaise, prefix: '− '),
                if (d.piecePaise > 0)
                  AmountRow(label: tr('Piece work'), paise: d.piecePaise, prefix: '− '),
                const Divider(),
                AmountRow(
                  label: d.profitPaise >= 0 ? tr('Profit') : tr('Loss'),
                  paise: d.profitPaise.abs(),
                  bold: true,
                  color: d.profitPaise >= 0
                      ? AppColors.successText
                      : AppColors.dangerText,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr('Daily-wage labour is not counted here yet.'),
                    style: TextStyle(fontSize: 12, color: AppColors.slate600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push(Routes.newDocument(
                    DocumentKind.invoice,
                    clientId: d.client.id,
                    jobId: jobId,
                  )),
                  icon: const Icon(Icons.receipt_long),
                  label: Text(tr('New bill')),
                ),
              ),
              const SizedBox(width: AppSizes.gap),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push(Routes.expenseForJob(jobId)),
                  icon: const Icon(Icons.receipt),
                  label: Text(tr('Expense')),
                ),
              ),
            ],
          ),
          SectionTitle(tr('Bills')),
          if (d.bills.isEmpty)
            Text(tr('No bills linked to this job.'),
                style: TextStyle(color: AppColors.slate600))
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final b in d.bills)
                    ListTile(
                      title: Text(b.number),
                      subtitle: Row(
                        children: [
                          documentStatusChip(b.status, b.kind),
                          const SizedBox(width: 8),
                          Text(dayFormat.format(parseIsoDate(b.date))),
                        ],
                      ),
                      trailing: Text(formatPaise(b.totalPaise),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => context.push(Routes.document(b.id)),
                    ),
                ],
              ),
            ),
          SectionTitle(tr('Expenses')),
          if (d.expenses.isEmpty)
            Text(tr('No expenses linked to this job.'),
                style: TextStyle(color: AppColors.slate600))
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
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
                      trailing: Text(formatPaise(e.amountPaise),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
