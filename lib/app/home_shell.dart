import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/db/enums.dart';
import '../core/i18n/i18n.dart';

/// One bottom tab. [label] is the English text passed to `tr`.
class AppTab {
  const AppTab(this.path, this.icon, this.selectedIcon, this.label);

  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _home = AppTab('/', Icons.home_outlined, Icons.home, 'Home');
const _attendance = AppTab(
    '/attendance', Icons.fact_check_outlined, Icons.fact_check, 'Attendance');
const _billing = AppTab(
    '/billing', Icons.receipt_long_outlined, Icons.receipt_long, 'Billing');
const _khata = AppTab('/khata', Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet, 'Khata');
const _workers =
    AppTab('/workers', Icons.groups_outlined, Icons.groups, 'Workers');
const _staff = AppTab('/workers', Icons.groups_outlined, Icons.groups, 'Staff');
const _expenses =
    AppTab('/expenses', Icons.receipt_outlined, Icons.receipt, 'Expenses');
const _tasks =
    AppTab('/tasks', Icons.task_alt_outlined, Icons.task_alt, 'Reminders');

/// Bottom tabs per user type (PRD C10). router.dart builds one shell branch
/// per tab, in this order.
List<AppTab> tabsFor(UserType type) => switch (type) {
      UserType.contractor => const [
          _home,
          _attendance,
          _billing,
          _khata,
          _workers,
        ],
      UserType.shop => const [_home, _billing, _expenses, _khata, _staff],
      // Personal mode is free, but still needs a complete ledger surface.
      UserType.personal => const [_home, _expenses, _tasks],
    };

class HomeShell extends StatelessWidget {
  const HomeShell({
    super.key,
    required this.navigationShell,
    required this.tabs,
  });

  final StatefulNavigationShell navigationShell;
  final List<AppTab> tabs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tr(tab.label),
            ),
        ],
      ),
    );
  }
}
