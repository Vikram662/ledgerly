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
        DateTime.monday: tr('Mon'),
        DateTime.tuesday: tr('Tue'),
        DateTime.wednesday: tr('Wed'),
        DateTime.thursday: tr('Thu'),
        DateTime.friday: tr('Fri'),
        DateTime.saturday: tr('Sat'),
        DateTime.sunday: tr('Sun'),
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
                      labelStyle: TextStyle(
                        color: settings.weeklyOffDay == null
                            ? Colors.white
                            : AppColors.inkSoft,
                        fontWeight: FontWeight.w700,
                      ),
                      label: Text(tr('None')),
                      selected: settings.weeklyOffDay == null,
                      onSelected: (_) =>
                          save(settings.copyWith(weeklyOffDay: () => null)),
                    ),
                    for (final entry in _weekdays.entries)
                      ChoiceChip(
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: settings.weeklyOffDay == entry.key
                              ? Colors.white
                              : AppColors.inkSoft,
                          fontWeight: FontWeight.w700,
                        ),
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
          Column(
            children: [
              for (final (value, label) in [
                (0, tr('Salary ÷ days in month')),
                (30, tr('Salary ÷ 30')),
                (26, tr('Salary ÷ 26')),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: settings.monthlyDivisor == value
                        ? AppColors.primaryTint
                        : AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      side: BorderSide(
                        color: settings.monthlyDivisor == value
                            ? AppColors.primary
                            : AppColors.border,
                        width: settings.monthlyDivisor == value ? 2 : 1,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      onTap: () => save(
                        settings.copyWith(monthlyDivisor: value),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              settings.monthlyDivisor == value
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: settings.monthlyDivisor == value
                                  ? AppColors.primary
                                  : AppColors.faint,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
