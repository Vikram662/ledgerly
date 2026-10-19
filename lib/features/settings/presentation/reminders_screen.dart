import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/notify/notifications.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/widgets/common.dart';

final _notificationsEnabledProvider = FutureProvider.autoDispose<bool>(
  (ref) => AppNotifications.instance.enabled(),
);

/// PRD DB-07: choose which reminder notifications to get.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final enabled = ref.watch(_notificationsEnabledProvider).valueOrNull;
    if (settings == null) {
      return const SkeletonPage();
    }
    final r = settings.reminders;
    Future<void> save(ReminderSettings value) => ref
        .read(settingsRepositoryProvider)
        .saveSettings(settings.copyWith(reminders: value));

    Widget toggle(
      String title,
      String subtitle,
      bool value,
      ReminderSettings Function(bool) update,
    ) =>
        SwitchListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: (v) => save(update(v)),
        );

    Future<void> sendTest() async {
      await AppNotifications.instance.requestPermission();
      await AppNotifications.instance.show(
        NotificationKind.monthEnd,
        tr('Ledgerly'),
        tr('Reminders are working.'),
      );
      ref.invalidate(_notificationsEnabledProvider);
      if (context.mounted) showMessage(context, tr('Test sent'));
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('Reminders'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (enabled == false)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const IconTile(Icons.notifications_off_outlined,
                            color: AppColors.warningSurface,
                            iconColor: AppColors.warningText),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tr('Notifications are off for this app'),
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('Turn them on to get the reminders below. If nothing happens, allow notifications in phone Settings → Apps → Ledgerly.'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await AppNotifications.instance.requestPermission();
                        ref.invalidate(_notificationsEnabledProvider);
                      },
                      icon: const Icon(Icons.notifications_active),
                      label: Text(tr('Turn on notifications')),
                    ),
                  ],
                ),
              ),
            ),
          if (enabled == true)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(
                color: AppColors.successSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 20, color: AppColors.successText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('Reminders are working.'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.successText,
                      ),
                    ),
                  ),
                  MiniButton(label: tr('Send test'), onTap: sendTest),
                ],
              ),
            ),
          CardList(children: [
            toggle(
              tr('Backup problems'),
              tr('Backup failed twice, not done for 24 hours, or phone time wrong'),
              r.backup,
              (v) => r.copyWith(backup: v),
            ),
            toggle(
              tr('Overdue bills'),
              tr('Bills past their due date that are not fully paid'),
              r.overdueBills,
              (v) => r.copyWith(overdueBills: v),
            ),
            toggle(
              tr('Month-end settlement'),
              tr('Last day of the month: settle workers\' khata'),
              r.monthEnd,
              (v) => r.copyWith(monthEnd: v),
            ),
            toggle(
              tr('Holidays'),
              tr('The day before a holiday you added'),
              r.holidays,
              (v) => r.copyWith(holidays: v),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            tr('Reminders come at most once a day, between 9 am and 9 pm.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
