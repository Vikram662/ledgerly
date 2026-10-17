import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/backup/backup_providers.dart';
import '../core/db/enums.dart';
import '../core/db/providers.dart';
import '../core/i18n/i18n.dart';
import '../core/utils/phone.dart';
import '../core/utils/photos.dart';
import '../core/widgets/common.dart';
import '../core/widgets/language_picker.dart';
import '../features/backup/presentation/backup_screen.dart';
import 'router.dart';
import 'theme.dart';

/// Side menu with every section of the app (PRD E1 header menu).
/// Bottom tabs stay for the 4 most used sections.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final backup = ref.watch(backupStateProvider).valueOrNull;
    final type = ref.watch(userTypeProvider);
    final contractor = type == UserType.contractor;
    final personal = type == UserType.personal;
    final location = GoRouterState.of(context).uri.toString();

    /// A bottom-tab section is switched to; other pages open on top.
    Widget item(
      IconData icon,
      String title,
      String route, {
      String? subtitle,
      Widget? trailing,
    }) {
      final selected = Routes.isTab(route) && location == route;
      return ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: trailing,
        selected: selected,
        onTap: () {
          Navigator.of(context).pop(); // close the drawer
          openRoute(context, route);
        },
      );
    }

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.slate600,
            ),
          ),
        );

    final backupDot = switch (backup?.health) {
      BackupHealth.synced => AppColors.successFill,
      BackupHealth.pending => AppColors.amber500,
      _ => AppColors.dangerFill,
    };

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Business profile header → opens the profile screen.
            InkWell(
              onTap: () {
                Navigator.of(context).pop();
                context.push(Routes.businessProfile);
              },
              child: Container(
                color: AppColors.slate900,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Row(
                  children: [
                    if (profile?.logoPath != null)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(3),
                        child: PhotoThumb(
                          key: ValueKey(profile!.logoPath),
                          name: profile!.logoPath!,
                          size: 46,
                          fit: BoxFit.contain,
                        ),
                      )
                    else
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.amber500,
                        foregroundColor: AppColors.slate900,
                        child: Text(
                          initials(profile?.name ?? 'T'),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile?.name ?? tr('Thekedaar'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (profile?.phone != null)
                            Text(
                              formatIndianPhone(profile!.phone!),
                              style: const TextStyle(color: Color(0xFFCBD5E1)),
                            ),
                          Text(
                            personal
                                ? tr('Edit profile')
                                : tr('Edit business profile'),
                            style: TextStyle(
                              color: AppColors.amber500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            item(Icons.home_outlined, tr('Home'), Routes.dashboard),
            if (!personal) ...[
              heading(tr('Billing')),
              item(Icons.receipt_long_outlined, tr('Bills'),
                  Routes.billingTab(0)),
              item(Icons.request_quote_outlined, tr('Quotations'),
                  Routes.billingTab(1)),
              item(Icons.people_outline,
                  contractor ? tr('Clients') : tr('Customers'),
                  Routes.billingTab(2)),
              item(Icons.payments_outlined, tr('Payments received'),
                  Routes.billingTab(3)),
              if (contractor)
                item(Icons.location_city_outlined, tr('Jobs / Sites'),
                    Routes.jobs),
              heading(contractor ? tr('Workers & Khata') : tr('Staff & Khata')),
              item(Icons.groups_outlined,
                  contractor ? tr('Workers') : tr('Staff'), Routes.workers),
              item(Icons.fact_check_outlined, tr('Mark attendance'),
                  Routes.attendance()),
              item(Icons.calendar_month_outlined, tr('Attendance register'),
                  Routes.attendanceMonth,
                  subtitle: contractor
                      ? tr('All workers, month calendar')
                      : tr('All staff, month calendar')),
              item(Icons.account_balance_wallet_outlined, tr('Khata balances'),
                  Routes.khataTab(0)),
              item(Icons.history, tr('Khata entries'), Routes.khataTab(1)),
            ],
            heading(tr('Expenses')),
            item(Icons.receipt_outlined, tr('Expenses'), Routes.expenses,
                subtitle: tr('Kharcha log, month-wise')),
            if (!personal)
              item(Icons.store_outlined, tr('Suppliers'), Routes.suppliers,
                  subtitle: tr('Udhaar purchases & payments')),
            heading(personal ? tr('Reminders') : tr('Reports & Tasks')),
            item(Icons.task_alt_outlined, tr('Tasks & Reminders'), Routes.tasks,
                subtitle: contractor
                    ? tr('Site visits, payments & alerts')
                    : tr('Bills, payments & alerts')),
            item(Icons.calendar_month_outlined, tr('Calendar'), Routes.calendar,
                subtitle: tr('What happened on each day')),
            if (!personal)
              item(Icons.account_balance_outlined, tr('Lena / Dena'),
                  Routes.dues()),
            heading(tr('Settings')),
            const LanguageTile(closeDrawer: true),
            item(
                Icons.store_mall_directory_outlined,
                personal ? tr('My profile') : tr('Business profile'),
                Routes.businessProfile),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: Text(tr('Backup now')),
              subtitle: Text(tr('Upload to Google Drive')),
              onTap: () {
                // The drawer closes; keep what we need from its context.
                final messenger = ScaffoldMessenger.of(context);
                final router = GoRouter.of(context);
                final coordinator = ref.read(backupCoordinatorProvider);
                final running = ref.read(backupRunningProvider);
                Navigator.of(context).pop();
                if (backup == null || !backup.configured) {
                  router.push(Routes.backup);
                  return;
                }
                void say(String text) => messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(text)));
                if (running) {
                  say(tr('Backup is already running'));
                  return;
                }
                say(tr('Backup started…'));
                coordinator
                    .runNow(BackupTrigger.manual)
                    .then((r) => say(backupResultMessage(r)));
              },
            ),
            item(
              Icons.cloud_upload_outlined,
              tr('Backup & restore'),
              Routes.backup,
              trailing: Icon(Icons.circle, size: 12, color: backupDot),
            ),
            item(Icons.notifications_active_outlined, tr('Notification settings'),
                Routes.notificationSettings),
            if (!type.isFree)
              item(Icons.workspace_premium_outlined, tr('Thekedaar Pro'),
                  Routes.subscription,
                  subtitle: tr('₹99/month · Manage plan')),
            item(Icons.settings_outlined, tr('All settings'), Routes.settings,
                subtitle: contractor
                    ? tr('Trades, work rules, app lock')
                    : tr('Backup, reminders, app lock')),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
