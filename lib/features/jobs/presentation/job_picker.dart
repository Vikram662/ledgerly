import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app/theme.dart";
import "../../../core/db/enums.dart";
import "../../../core/i18n/i18n.dart";
import "../../../core/widgets/pickers.dart";
import "../data/jobs_repository.dart";

/// Optional job / site field. With [clientId], only that client's jobs.
/// Completed jobs are hidden unless already selected.
class JobPickerField extends ConsumerWidget {
  const JobPickerField({
    super.key,
    required this.jobId,
    required this.onChanged,
    this.clientId,
    this.compact = false,
  });

  final String? jobId;
  final String? clientId;
  final ValueChanged<String?> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(jobsProvider).valueOrNull ?? const [];
    final jobs = all
        .where((j) =>
            (clientId == null || j.job.clientId == clientId) &&
            (j.job.status != JobStatus.completed || j.job.id == jobId))
        .toList();
    final selected = all.where((j) => j.job.id == jobId).firstOrNull;

    Future<void> pick() async {
      const none = "__none__";
      final picked = await showPickerSheet<String>(
        context,
        title: jobs.isEmpty ? tr("No open jobs yet") : tr("Choose job / site"),
        options: [none, for (final j in jobs) j.job.id],
        label: (id) {
          if (id == none) return tr("No job");
          final j = jobs.firstWhere((j) => j.job.id == id);
          return "${j.job.title} · ${j.clientName}";
        },
        selected: jobId ?? none,
      );
      if (picked == null) return;
      onChanged(picked == none ? null : picked);
    }

    if (compact) {
      final name = selected?.job.title ?? tr("none");
      return Material(
        color: AppColors.page,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: pick,
          child: Container(
            height: 44,
            constraints: const BoxConstraints(maxWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(
              tr("Job: {name}", {"name": name}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.inkSoft,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return PickerField(
      label: tr("Job / site (optional)"),
      icon: Icons.location_city,
      value: selected == null
          ? null
          : "${selected.job.title} · ${selected.clientName}",
      onTap: pick,
    );
  }
}
