import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backup/backup_providers.dart';
import '../db/database.dart';
import '../db/meta_store.dart';
import '../db/providers.dart';
import '../security/secure_store.dart';
import 'sync_engine.dart';

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(
    db: ref.watch(databaseProvider),
    secureStore: ref.watch(secureStoreProvider),
  ),
);

class SyncState {
  const SyncState({required this.lastSyncAt, required this.lastError});

  final DateTime? lastSyncAt;
  final String? lastError;
}

final syncStateProvider = StreamProvider<SyncState>((ref) {
  final meta = MetaStore(ref.watch(databaseProvider));
  return meta.watchAll().map((m) {
    final last = m.intValue(MetaKeys.lastSyncAt);
    return SyncState(
      lastSyncAt:
          last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
      lastError: m[MetaKeys.lastSyncError],
    );
  });
});

final syncRunningProvider = StateProvider<bool>((ref) => false);

/// Starts cloud sync triggers for the life of the app scope.
final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final coordinator = SyncCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// When cloud sync runs while the app is open:
/// - data changed → in ~10 seconds
/// - every 5 minutes
/// - internet comes back, or the app comes to the front
/// - app goes to the background with changes left → a background job that
///   Android runs once there is internet, even if the app is closed
class SyncCoordinator with WidgetsBindingObserver {
  SyncCoordinator(this._ref);

  final Ref _ref;
  StreamSubscription<Object?>? _tableSub;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  Timer? _changeTimer;
  Timer? _periodic;
  bool _started = false;

  static const _ignoredTables = {'app_meta', 'backup_logs'};

  AppDatabase get _db => _ref.read(databaseProvider);
  SyncEngine get _engine => _ref.read(syncEngineProvider);

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _tableSub = _db.tableUpdates().listen((updates) {
      if (updates.every((u) => _ignoredTables.contains(u.table))) return;
      _changeTimer?.cancel();
      _changeTimer = Timer(const Duration(seconds: 10), () async {
        // Pulled rows also fire table updates; only local changes need a run.
        if (await _engine.pendingCount() > 0) unawaited(syncNow());
      });
    });
    _netSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(syncNow());
      }
    });
    _periodic = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(syncNow()),
    );
    unawaited(() async {
      try {
        await _ref.read(backupSchedulerProvider).scheduleSyncPeriodic();
      } catch (_) {
        // WorkManager unavailable (tests); foreground triggers still work.
      }
    }());
    unawaited(syncNow());
  }

  Future<SyncResult> syncNow() async {
    final running = _ref.read(syncRunningProvider.notifier);
    running.state = true;
    try {
      return await _engine.run();
    } finally {
      running.state = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(() async {
        try {
          if (await _engine.pendingCount() > 0) {
            await _ref.read(backupSchedulerProvider).scheduleSyncPending();
          }
        } catch (_) {}
      }());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(syncNow());
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tableSub?.cancel();
    _netSub?.cancel();
    _changeTimer?.cancel();
    _periodic?.cancel();
  }
}
