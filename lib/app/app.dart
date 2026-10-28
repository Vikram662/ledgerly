import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/backup/backup_providers.dart';
import '../core/db/enums.dart';
import '../core/db/providers.dart';
import '../core/i18n/i18n.dart';
import '../core/notify/notifications.dart';
import '../core/sync/sync_providers.dart';
import '../core/update/app_update.dart';
import '../features/lock/lock_screens.dart';
import '../features/subscription/subscription_controller.dart';
import 'router.dart';
import 'theme.dart';

class ThekedaarApp extends ConsumerStatefulWidget {
  const ThekedaarApp({
    super.key,
    required this.needsOnboarding,
    this.userType = UserType.contractor,
  });

  /// True on first launch, before the business profile exists.
  final bool needsOnboarding;

  /// The saved profile's type, read before the first frame so the right
  /// tabs show at once.
  final UserType userType;

  @override
  ConsumerState<ThekedaarApp> createState() => _ThekedaarAppState();
}

class _ThekedaarAppState extends ConsumerState<ThekedaarApp> {
  late UserType _userType = widget.userType;
  late GoRouter _router = buildRouter(
    ref: ref,
    userType: _userType,
    initialLocation:
        widget.needsOnboarding ? Routes.onboarding : Routes.dashboard,
  );

  @override
  void initState() {
    super.initState();
    // Tabs depend on the user type (PRD C10): after onboarding, or when the
    // type changes, start a fresh router on Home.
    ref.listenManual(businessProfileProvider, (_, next) {
      final type = next.valueOrNull?.userType;
      if (type == null || type == _userType) return;
      final old = _router;
      setState(() {
        _userType = type;
        _router = buildRouter(
          ref: ref,
          userType: type,
          initialLocation: Routes.dashboard,
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    });
    // Auto backup triggers live as long as this app scope (PRD D3.1).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(backupCoordinatorProvider).start();
      ref.read(syncCoordinatorProvider).start();
      ref.read(subscriptionControllerProvider.notifier).refresh();
      ref.read(subscriptionServiceProvider).startFcmTokenSync();
      const AppUpdateChecker().check(context);
    });
    appLanguage.addListener(_onLanguageChanged);
    final notifications = AppNotifications.instance;
    notifications.tapped.addListener(_onNotificationTapped);
    notifications.initForApp().then((_) => _openTappedNotification());
  }

  /// Redraws every screen in the new language, keeping the open pages.
  void _onLanguageChanged() {
    setState(() {});
    rebuildAllWidgets(context);
  }

  /// Opens the screen a notification is about. Behind the lock screen the
  /// page is already open when the user unlocks.
  void _onNotificationTapped() => _openTappedNotification();

  Future<void> _openTappedNotification() async {
    final kind = AppNotifications.instance.tapped.value;
    if (kind == null || !mounted) return;
    // On a cold start the profile may still be loading; before onboarding
    // there is nothing to open.
    final profile = await ref.read(businessProfileProvider.future);
    if (profile == null || !mounted) return;
    if (AppNotifications.instance.tapped.value != kind) return;
    AppNotifications.instance.tapped.value = null;
    final route = switch (kind) {
      NotificationKind.backupFailed ||
      NotificationKind.backupPending ||
      NotificationKind.clockWrong ||
      NotificationKind.backupProgress =>
        Routes.backup,
      NotificationKind.overdueBills => Routes.dues(),
      NotificationKind.monthEnd => Routes.khataTab(0),
      NotificationKind.holiday => Routes.attendanceMonth,
      NotificationKind.taskReminder => Routes.tasks,
      NotificationKind.loanDue => Routes.loans,
    };
    // Tabs are switched with go; others open on top.
    if (Routes.isTab(route)) {
      _router.go(route);
    } else {
      _router.go(Routes.dashboard);
      _router.push(route);
    }
  }

  @override
  void dispose() {
    appLanguage.removeListener(_onLanguageChanged);
    AppNotifications.instance.tapped.removeListener(_onNotificationTapped);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: tr('Ledgerly'),
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      locale: appLanguage.value.locale,
      supportedLocales: [for (final l in AppLanguage.values) l.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
      builder: (context, child) => LockGate(
        // Pull down on any screen's list to refresh it (all screens re-read
        // the database). Only vertical scrolling triggers it.
        child: RefreshIndicator(
          color: AppColors.blue700,
          edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
          notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
          onRefresh: () => ref.read(backupCoordinatorProvider).refreshAll(),
          child: child ?? const SizedBox(),
        ),
      ),
    );
  }
}
