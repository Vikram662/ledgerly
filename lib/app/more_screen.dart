import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backup/backup_providers.dart';
import '../core/db/enums.dart';
import '../core/db/providers.dart';
import '../core/i18n/i18n.dart';
import '../core/utils/money.dart';
import '../core/utils/photos.dart';
import '../core/widgets/common.dart';
import '../core/widgets/language_picker.dart';
import '../features/billing/data/billing_repository.dart';
import '../features/expenses/data/expenses_repository.dart';
import '../features/jobs/data/jobs_repository.dart';
import '../features/lock/app_lock_controller.dart';
import '../features/subscription/subscription_controller.dart';
import '../features/tasks/data/tasks_repository.dart';
import 'router.dart';
import 'theme.dart';

/// Every section that is not a bottom tab (wireframe "More", PRD E1).
/// Opened from the business tile on Home.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final type = ref.watch(userTypeProvider);
    final contractor = type == UserType.contractor;
    final personal = type == UserType.personal;
    final backup = ref.watch(backupStateProvider).valueOrNull;
    final lock = ref.watch(appLockProvider);
    final access = ref.watch(subscriptionControllerProvider).valueOrNull;
    final now = DateTime.now();

    // Live one-line details under each tile.
    final jobs = ref.watch(jobsProvider).valueOrNull;
    final activeJobs =
        jobs?.where((j) => j.job.status != JobStatus.completed).length;
    final tasks = ref.watch(pendingTasksProvider).valueOrNull;
    final overdue = tasks?.where((t) => t.dueAt.isBefore(now)).length ?? 0;
    final expenses = ref
        .watch(monthExpensesProvider((year: now.year, month: now.month)))
        .valueOrNull;
    final spent = expenses?.fold<int>(0, (s, e) => s + e.expense.amountPaise);
    final suppliers = ref.watch(suppliersProvider).valueOrNull;
    final toPay = suppliers?.fold<int>(
        0,
        (s, b) =>
            s + (b.purchasedPaise - b.paidPaise).clamp(0, 1 << 52).toInt());
    final clients = ref.watch(clientsProvider).valueOrNull?.length;

    final trade = profile?.trades
        .split(',')
        .map((t) => t.trim())
        .firstWhere((t) => t.isNotEmpty, orElse: () => '');
    final kindLine =
        (trade == null || trade.isEmpty || !contractor) ? type.label : trade;
    final pro = access?.kind == AccessKind.active ||
        access?.kind == AccessKind.offlineGrace;

    void go(String route) => openRoute(context, route);

    final work = <Widget>[
      if (!personal)
        NavTile(
          icon: Icons.location_city_outlined,
          label: tr('Jobs / Sites'),
          detail: activeJobs == null
              ? null
              : tr('{count} active', {'count': activeJobs}),
          onTap: () => go(Routes.jobs),
        ),
      if (!Routes.isTab(Routes.tasks))
        NavTile(
          icon: Icons.task_alt_outlined,
          label: contractor ? tr('Tasks & visits') : tr('Tasks & reminders'),
          detail: overdue > 0
              ? tr('{count} overdue', {'count': overdue})
              : tr('{count} pending', {'count': tasks?.length ?? 0}),
          onTap: () => go(Routes.tasks),
        ),
      NavTile(
        icon: Icons.calendar_month_outlined,
        label: tr('Calendar'),
        detail: tr('This month'),
        onTap: () => go(Routes.calendar),
      ),
      if (!personal)
        NavTile(
          icon: Icons.grid_view_outlined,
          label: tr('Attendance register'),
          detail: tr('Month view'),
          onTap: () => go(Routes.attendanceMonth),
        ),
      if (!Routes.isTab(Routes.workers))
        NavTile(
          icon: Icons.groups_outlined,
          label: contractor ? tr('Workers') : tr('People'),
          onTap: () => go(Routes.workers),
        ),
      if (!Routes.isTab(Routes.khata))
        NavTile(
          icon: Icons.account_balance_wallet_outlined,
          label: personal ? tr('Payments & wages') : tr('Khata'),
          detail: personal
              ? tr('Salary and helper payments')
              : tr('Advances & wages'),
          onTap: () => go(Routes.khata),
        ),
    ];

    final money = <Widget>[
      if (!Routes.isTab(Routes.expenses))
        NavTile(
          icon: Icons.receipt_outlined,
          label: tr('Expenses'),
          detail: spent == null
              ? null
              : tr('{amount} this month', {'amount': formatPaise(spent)}),
          onTap: () => go(Routes.expenses),
        ),
      if (!personal) ...[
        NavTile(
          icon: Icons.store_outlined,
          label: tr('Suppliers'),
          detail: toPay == null
              ? null
              : tr('{amount} to pay', {'amount': formatPaise(toPay)}),
          onTap: () => go(Routes.suppliers),
        ),
        NavTile(
          icon: Icons.account_balance_outlined,
          label: tr('Lena / Dena'),
          detail: tr('Dues report'),
          onTap: () => go(Routes.dues()),
        ),
        NavTile(
          icon: Icons.people_outline,
          label: contractor ? tr('Clients') : tr('Customers'),
          detail: clients == null
              ? null
              : (contractor
                  ? tr('{count} clients', {'count': clients})
                  : tr('{count} customers', {'count': clients})),
          onTap: () => go(Routes.billingTab(2)),
        ),
        if (!Routes.isTab(Routes.billing))
          NavTile(
            icon: Icons.receipt_long_outlined,
            label: tr('Billing'),
            onTap: () => go(Routes.billing),
          ),
      ],
    ];

    final backupOn = backup?.configured == true;
    final lockValue = lock.biometricEnabled ? tr('Fingerprint') : tr('PIN');

    return Scaffold(
      appBar: AppBar(title: Text(tr('More'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: const BorderSide(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => go(Routes.businessProfile),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    if (profile?.logoPath != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: PhotoThumb(
                          key: ValueKey(profile!.logoPath),
                          name: profile.logoPath!,
                          size: 52,
                          fit: BoxFit.contain,
                        ),
                      )
                    else
                      BrandTile(name: profile?.name ?? '', size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile?.name ?? tr('Ledgerly'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '$kindLine · ${personal ? tr('Edit profile') : tr('Edit business profile')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (pro) TagBadge(tr('PRO')),
                    if (type.isFree)
                      TagBadge(
                        tr('FREE'),
                        color: AppColors.successSurface,
                        textColor: AppColors.successText,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (work.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionLabel(tr('Work')),
            TileGrid(children: work),
          ],
          if (money.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionLabel(tr('Money')),
            TileGrid(children: money),
          ],
          const SizedBox(height: 12),
          SectionLabel(tr('Settings')),
          CardList(
            children: [
              SettingRow(
                icon: Icons.cloud_upload_outlined,
                label: tr('Google Drive backup'),
                value: backupOn ? tr('On') : tr('Off'),
                valueColor:
                    backupOn ? AppColors.successText : AppColors.dangerText,
                onTap: () => go(Routes.backup),
              ),
              SettingRow(
                icon: Icons.lock_outline,
                label: tr('App lock'),
                value: lockValue,
                onTap: () => go(Routes.appLock),
              ),
              SettingRow(
                icon: Icons.notifications_none,
                label: tr('Reminders'),
                onTap: () => go(Routes.reminders),
              ),
              if (contractor)
                SettingRow(
                  icon: Icons.rule,
                  label: tr('Wage rules & trades'),
                  onTap: () => go(Routes.settings),
                )
              else
                SettingRow(
                  icon: Icons.rule,
                  label: tr('Work rules'),
                  onTap: () => go(Routes.rules),
                ),
              SettingRow(
                icon: Icons.translate,
                label: tr('Language'),
                value: appLanguage.value.nativeName,
                onTap: () => showLanguagePicker(context),
              ),
              if (!type.isFree)
                SettingRow(
                  icon: Icons.workspace_premium_outlined,
                  label: tr('Ledgerly Pro'),
                  value: tr('₹99 / month'),
                  onTap: () => go(Routes.subscription),
                ),
              SettingRow(
                icon: Icons.settings_outlined,
                label: tr('All settings'),
                onTap: () => go(Routes.settings),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
