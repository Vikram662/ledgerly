import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../attendance/data/attendance_repository.dart';
import '../data/workers_repository.dart';

/// Workers tab: search, role chips, today's attendance dot per worker.
class WorkersScreen extends ConsumerStatefulWidget {
  const WorkersScreen({super.key});

  @override
  ConsumerState<WorkersScreen> createState() => _WorkersScreenState();
}

/// Chip value for workers who have left.
const _left = '\u0000left';

class _WorkersScreenState extends ConsumerState<WorkersScreen> {
  String _query = '';

  /// Null: all active workers; a role name; or [_left].
  String? _chip;

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(userTypeProvider) == UserType.shop;
    final activeAsync = ref.watch(activeWorkersProvider);
    final inactive = ref.watch(inactiveWorkersProvider).valueOrNull ?? const [];
    final today =
        ref.watch(attendanceDayProvider(isoDate(DateTime.now()))).valueOrNull ??
            const [];
    final status = {
      for (final row in today) row.worker.id: row.attendance?.status,
    };
    final active = activeAsync.valueOrNull ?? const [];
    final roles = {
      for (final w in active)
        if (w.roleName != null) w.roleName!,
    }.toList()
      ..sort();

    final personal = ref.watch(userTypeProvider) == UserType.personal;
    final title =
        personal ? tr('People') : (shop ? tr('Staff') : tr('Workers'));
    final addLabel = personal
        ? tr('Add person')
        : (shop ? tr('Add staff') : tr('Add worker'));

    return Scaffold(
      appBar: tabAppBar(
        title,
        subtitle: Text(tr('{active} active · {left} left',
            {'active': active.length, 'left': inactive.length})),
      ),
      floatingActionButton: _chip == _left
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(Routes.addWorker),
              icon: const Icon(Icons.person_add_alt),
              label: Text(addLabel),
            ),
      body: activeAsync.when(
        loading: () => const ListSkeleton(),
        error: (error, _) => Center(
          child: Text(tr(
              'Could not load workers: {error}', {'error': errorText(error)})),
        ),
        data: (_) {
          if (active.isEmpty && inactive.isEmpty) {
            return EmptyState(
              icon: Icons.groups,
              title: shop ? tr('No staff yet') : tr('No workers yet'),
              message:
                  tr('Add your workers to mark attendance and keep khata.'),
              actionLabel: shop ? tr('Add staff') : tr('Add first worker'),
              onAction: () => context.push(Routes.addWorker),
            );
          }
          final base = _chip == _left
              ? inactive
              : _chip == null
                  ? active
                  : active.where((w) => w.roleName == _chip).toList();
          final q = _query;
          final items = q.isEmpty
              ? base
              : base
                  .where((w) =>
                      w.worker.name.toLowerCase().contains(q) ||
                      (w.worker.phone ?? '').contains(q))
                  .toList();

          Widget chip(String? value, String label) => AppChip(
                label: label,
                selected: _chip == value,
                onTap: () => setState(() => _chip = value),
              );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              SearchField(
                hint: tr('Search name or phone'),
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 14),
              ChipRow(
                children: [
                  chip(null, tr('All')),
                  for (final role in roles) chip(role, role),
                  if (inactive.isNotEmpty) chip(_left, tr('Left')),
                ],
              ),
              const SizedBox(height: 14),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    tr('Nothing here'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: AppColors.muted),
                  ),
                )
              else
                CardList(
                  children: [
                    for (final item in items)
                      _WorkerRow(
                        item: item,
                        dot: item.worker.isActive
                            ? _dotColor(status[item.worker.id])
                            : null,
                      ),
                  ],
                ),
              if (_chip != _left && items.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    LegendDot(
                        color: AppColors.successFill,
                        label: tr('Present today')),
                    LegendDot(color: AppColors.amber500, label: tr('Half')),
                    LegendDot(
                        color: AppColors.dangerFill, label: tr('Absent')),
                    LegendDot(
                        color: AppColors.inputBorder,
                        label: tr('Not marked')),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static Color _dotColor(AttendanceStatus? status) => switch (status) {
        AttendanceStatus.present => AppColors.successFill,
        AttendanceStatus.half => AppColors.amber500,
        AttendanceStatus.absent => AppColors.dangerFill,
        null => AppColors.inputBorder,
        _ => AppColors.primary,
      };
}

class _WorkerRow extends StatelessWidget {
  const _WorkerRow({required this.item, required this.dot});

  final WorkerListItem item;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(Routes.worker(item.worker.id)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                InitialsAvatar(item.worker.name),
                if (dot != null)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.worker.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (item.roleName != null) AppBadge(item.roleName!),
                      AppBadge(wageLabel(item.wage)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}
