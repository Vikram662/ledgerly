import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/common.dart';
import '../../lock/app_lock_controller.dart';
import '../../lock/lock_screens.dart';

/// PRD C1 (wireframe AppLockSettings): fingerprint on/off, change PIN,
/// lock now.
class AppLockSettingsScreen extends ConsumerWidget {
  const AppLockSettingsScreen({super.key});

  Future<void> _changePin(BuildContext context) async {
    if (!await confirmIdentity(context, reason: tr('Enter current PIN'))) {
      return;
    }
    if (!context.mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const PinSetupScreen(popOnDone: true),
      ),
    );
    if ((changed ?? false) && context.mounted) {
      showMessage(context, tr('PIN changed'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    Future<void> setBiometric(bool enabled) async {
      if (!enabled) return lock.setBiometricEnabled(false);
      // Turn on, then prove a finger works; undo if not.
      await lock.setBiometricEnabled(true);
      final confirmed = await lock.authenticateBiometric(
        reason: tr('Confirm fingerprint'),
        unlock: false,
      );
      if (!confirmed) await lock.setBiometricEnabled(false);
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('App lock'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.successSurface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.lock_outline,
                      size: 34, color: AppColors.successText),
                ),
                const SizedBox(height: 10),
                Text(
                  tr('Your data is locked'),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text(
                    tr('The app also locks after 2 minutes in the background.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          CardList(
            children: [
              SettingRow(
                label: tr('Unlock with fingerprint / face'),
                subtitle: lock.biometricAvailable
                    ? tr('PIN stays as backup')
                    : tr('Not available on this phone'),
                onTap: lock.biometricAvailable
                    ? () => setBiometric(!lock.biometricEnabled)
                    : null,
                trailing: Switch(
                  value: lock.biometricEnabled,
                  onChanged: lock.biometricAvailable ? setBiometric : null,
                ),
              ),
              SettingRow(
                label: tr('Change PIN'),
                subtitle: tr('Asks for your current PIN first'),
                onTap: () => _changePin(context),
              ),
              SettingRow(
                label: tr('Lock now'),
                subtitle: tr('Shows the PIN screen'),
                onTap: lock.lockNow,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
