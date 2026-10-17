import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/widgets/common.dart';

/// PRD I-S1 / I-T4: monthly salary divisor and weekly off.
class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  static const _help = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.muted,
  );

  static Map<int, String> get _weekdays => {
    DateTime.monday: tr('Monday'),
    DateTime.tuesday: tr('Tuesday'),
    DateTime.wednesday: tr('Wednesday'),
    DateTime.thursday: tr('Thursday'),
    DateTime.friday: tr('Friday'),
    DateTime.saturday: tr('Saturday'),
    DateTime.sunday: tr('Sunday'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    if (settings == null) {
      return const SkeletonPage();
    }
    Future<void> save(AppSettings s) =>
        ref.read(settingsRepositoryProvider).saveSettings(s);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Work rules'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SectionLabel(tr('Weekly off')),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      showCheckmark: false,
                      label: Text(tr('None')),
                      selected: settings.weeklyOffDay == null,
                      onSelected: (_) =>
                          save(settings.copyWith(weeklyOffDay: () => null)),
                    ),
                    for (final entry in _weekdays.entries)
                      ChoiceChip(
                        showCheckmark: false,
                        label: Text(entry.value),
                        selected: settings.weeklyOffDay == entry.key,
                        onSelected: (_) => save(
                            settings.copyWith(weeklyOffDay: () => entry.key)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  tr('On this day "Mark all" marks Off. Weekly off is paid for monthly workers, unpaid for daily workers.'),
                  style: _help,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionLabel(tr('Monthly salary → per-day rate')),
          CardList(
            children: [
              for (final (value, label) in [
                (0, tr('Salary ÷ days in month')),
                (30, tr('Salary ÷ 30')),
                (26, tr('Salary ÷ 26')),
              ])
                ListTile(
                  onTap: () => save(settings.copyWith(monthlyDivisor: value)),
                  title: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: Icon(
                    settings.monthlyDivisor == value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: settings.monthlyDivisor == value
                        ? AppColors.primary
                        : AppColors.faint,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tr('Used for new monthly workers. Each worker can be changed from their wage screen.'),
            style: _help,
          ),
        ],
      ),
    );
  }
}
