import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/backup/backup_providers.dart';
import '../../../core/config.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/language_picker.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final backup = ref.watch(backupStateProvider).valueOrNull;
    final trades = profile == null ? <Trade>{} : Trade.decode(profile.trades);
    final type = ref.watch(userTypeProvider);
    final rules = ref.watch(appSettingsProvider).valueOrNull;
    final weekDay = switch (rules?.weeklyOffDay) {
      DateTime.monday => tr('Monday'),
      DateTime.tuesday => tr('Tuesday'),
      DateTime.wednesday => tr('Wednesday'),
      DateTime.thursday => tr('Thursday'),
      DateTime.friday => tr('Friday'),
      DateTime.saturday => tr('Saturday'),
      DateTime.sunday => tr('Sunday'),
      _ => tr('None'),
    };

    Future<void> changeType() async {
      final selected = await showDialog<UserType>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(tr('Choose account type')),
          children: [
            for (final option in UserType.values)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, option),
                child: ListTile(
                  leading: Icon(option.icon),
                  title: Text(option.label),
                  subtitle: Text(option.description),
                  trailing: option == type
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                ),
              ),
          ],
        ),
      );
      if (selected != null && selected != type) {
        await ref.read(settingsRepositoryProvider).saveUserType(selected);
        if (context.mounted) showMessage(context, tr('Account type updated'));
      }
    }

    Widget tile(IconData icon, String title, String? subtitle, String route) =>
        SettingRow(
          icon: icon,
          label: title,
          subtitle: subtitle == null || subtitle.isEmpty ? null : subtitle,
          onTap: () => context.push(route),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SectionLabel(tr('Business')),
          CardList(
            children: [
              tile(
                  Icons.storefront_outlined,
                  type.personalLike
                      ? tr('My profile')
                      : tr('Business profile'),
                  profile?.name,
                  Routes.businessProfile),
              SettingRow(
                icon: Icons.category_outlined,
                label: tr('Account type'),
                value: type.label,
                onTap: changeType,
              ),
              if (type.usesTrades)
                tile(Icons.handyman_outlined, tr('Trades'),
                    trades.map((t) => t.label).join(', '), Routes.trades),
              if (!type.personalLike)
                tile(Icons.rule, tr('Work rules'),
                    tr('Weekly off: {day}', {'day': weekDay}), Routes.rules),
            ],
          ),
          const SizedBox(height: 16),
          SectionLabel(tr('Data & security')),
          CardList(
            children: [
              tile(
                Icons.cloud_upload_outlined,
                tr('Backup & restore'),
                backup == null || !backup.configured
                    ? tr('Not set up')
                    : tr('Google Drive · {email}',
                        {'email': backup.email ?? ''}),
                Routes.backup,
              ),
              tile(Icons.lock_outline, tr('App lock'),
                  tr('PIN and fingerprint'), Routes.appLock),
              tile(Icons.notifications_none, tr('Reminders'),
                  tr('Backup, overdue bills, month end'), Routes.reminders),
            ],
          ),
          const SizedBox(height: 16),
          SectionLabel(tr('Account')),
          CardList(
            children: [
              if (!type.isFree)
                tile(Icons.workspace_premium_outlined, tr('Ledgerly Pro'),
                    tr('₹99/month subscription'), Routes.subscription),
              const LanguageTile(),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '${tr('Ledgerly')} · ${tr('Version {appVersion}', {
                  'appVersion': AppConfig.appVersion
                })}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.faint),
          ),
        ],
      ),
    );
  }
}
