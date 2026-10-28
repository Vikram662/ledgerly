import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/config.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/widgets/common.dart';

/// Cloud sync status on the Backup screen, with "Sync now".
class CloudSyncPanel extends ConsumerWidget {
  const CloudSyncPanel({super.key});

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(syncCoordinatorProvider).syncNow();
    if (!context.mounted) return;
    showMessage(
      context,
      switch (result.outcome) {
        SyncOutcome.synced => tr('Cloud sync done ✓'),
        SyncOutcome.notReady => tr('Register or log in to sync with the cloud'),
        SyncOutcome.failed =>
          tr('Cloud sync failed. ({error})', {'error': result.error ?? ''}),
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.subscriptionConfigured) return const SizedBox.shrink();
    final state = ref.watch(syncStateProvider).valueOrNull;
    final running = ref.watch(syncRunningProvider);
    const grey = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.muted,
    );
    final error = state?.lastError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(tr('Cloud sync')),
        Panel(
          child: Row(
            children: [
              const IconTile(Icons.cloud_sync_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state?.lastSyncAt == null
                          ? tr('Last sync: never')
                          : tr('Last sync: {date}', {
                              'date': dayTimeFormat.format(state!.lastSyncAt!)
                            }),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      tr('Saved on this phone first, then in the cloud every few minutes when online.'),
                      style: grey,
                    ),
                    if (error != null)
                      Text(error, style: grey.copyWith(color: AppColors.dangerText)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              running
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: () => _syncNow(context, ref),
                      child: Text(tr('Sync now')),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
