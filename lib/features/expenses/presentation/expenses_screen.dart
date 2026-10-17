import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/photos.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pickers.dart';
import '../data/expenses_repository.dart';

/// PRD EX-01: expenses by month, with a category bar and day groups.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key, this.showMenu = false});

  /// True when this is a bottom tab: big title and no Back.
  final bool showMenu;

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

/// Bar colours for the top categories; the rest share the last one.
const _barColors = [
  AppColors.primary,
  AppColors.amber500,
  AppColors.ink,
  AppColors.inputBorder,
];

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  Future<void> _delete(ExpenseItem item) async {
    final ok = await confirmDialog(
      context,
      title: tr('Delete this expense?'),
      message: '${item.categoryName} · ${formatPaise(item.expense.amountPaise)}',
      confirmLabel: tr('Delete'),
      destructive: true,
    );
    if (ok) {
      await ref.read(expensesRepositoryProvider).deleteExpense(item.expense.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(
      monthExpensesProvider((year: _month.year, month: _month.month)),
    );
    final personal = ref.watch(userTypeProvider) == UserType.personal;
    final actions = [
      if (!personal)
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const StadiumBorder(),
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            onPressed: () => context.push(Routes.suppliers),
            child: Text(tr('Suppliers')),
          ),
        ),
    ];

    return Scaffold(
      appBar: widget.showMenu
          ? tabAppBar(tr('Expenses'), actions: actions)
          : AppBar(
              title: Text(tr('Expenses')),
              actions: [...actions, const SizedBox(width: 8)],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.addExpense),
        icon: const Icon(Icons.add),
        label: Text(tr('Add expense')),
      ),
      body: items.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => Center(child: Text(errorText(e))),
        data: (list) {
          final total = list.fold(0, (sum, i) => sum + i.expense.amountPaise);
          final byCategory = totalsByCategory(list);
          // Day groups, newest first.
          final days = <String, List<ExpenseItem>>{};
          for (final item in list) {
            days.putIfAbsent(item.expense.date, () => []).add(item);
          }
          final dayKeys = days.keys.toList()..sort((a, b) => b.compareTo(a));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              _MonthTotalCard(
                month: _month,
                canGoNext: !_isCurrentMonth,
                onShift: _shift,
                total: total,
                categories: byCategory,
              ),
              if (list.isEmpty)
                EmptyState(
                  icon: Icons.receipt,
                  title: tr('No expenses this month'),
                  message: personal
                      ? tr('Rent, groceries, bills and travel go here.')
                      : tr('Petrol, material, food, tools and rent go here.'),
                  actionLabel: tr('Add expense'),
                  onAction: () => context.push(Routes.addExpense),
                )
              else ...[
                for (final day in dayKeys) ...[
                  _DayHeader(
                    date: parseIsoDate(day),
                    total: days[day]!
                        .fold(0, (sum, i) => sum + i.expense.amountPaise),
                  ),
                  CardList(
                    children: [
                      for (final item in days[day]!)
                        _ExpenseRow(
                            item: item, onLongPress: () => _delete(item)),
                    ],
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    tr('Long-press an entry to delete it.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Month switcher, the month's total and a stacked bar by category.
class _MonthTotalCard extends StatelessWidget {
  const _MonthTotalCard({
    required this.month,
    required this.canGoNext,
    required this.onShift,
    required this.total,
    required this.categories,
  });

  final DateTime month;
  final bool canGoNext;
  final ValueChanged<int> onShift;
  final int total;
  final List<({String category, int totalPaise})> categories;

  @override
  Widget build(BuildContext context) {
    // Top three categories, then everything else together.
    final top = categories.take(3).toList();
    final rest = categories.skip(3).fold(0, (s, c) => s + c.totalPaise);
    final parts = [
      for (final c in top) (c.category, c.totalPaise),
      if (rest > 0) (tr('Other'), rest),
    ];

    Widget roundButton(IconData icon, String tip, VoidCallback? onTap) =>
        IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
            fixedSize: const Size.square(36),
            minimumSize: const Size.square(36),
            backgroundColor: AppColors.page,
          ),
        );

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              roundButton(
                  Icons.chevron_left, tr('Previous month'), () => onShift(-1)),
              Expanded(
                child: Text(
                  monthFormat.format(month),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              roundButton(Icons.chevron_right, tr('Next month'),
                  canGoNext ? () => onShift(1) : null),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tr('Total spent'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          Text(
            formatPaise(total),
            style: AppText.tabular.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < parts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    flex: parts[i].$2 <= 0 ? 1 : parts[i].$2,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: _barColors[i.clamp(0, _barColors.length - 1)],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (var i = 0; i < parts.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _barColors[i.clamp(0, _barColors.length - 1)],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${parts[i].$1} ${formatPaise(parts[i].$2)}',
                        style: AppText.tabular.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.total});

  final DateTime date;
  final int total;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final label = date == today
        ? tr('Today')
        : date == DateTime(today.year, today.month, today.day - 1)
            ? tr('Yesterday')
            : DateFormat('EEE, d MMM', uiDateLocale).format(date);
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: AppColors.muted,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(label.toUpperCase(), style: style)),
          Text(formatPaise(total), style: AppText.tabular.merge(style)),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.item, required this.onLongPress});

  final ExpenseItem item;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final e = item.expense;
    final details = [
      if (e.remarks != null && e.remarks!.isNotEmpty) e.remarks!,
      paymentModeLabel(e.mode),
      if (item.jobTitle != null) item.jobTitle!,
    ].join(' · ');
    return InkWell(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (e.photoPath != null)
              InkWell(
                onTap: () => showPhoto(context, e.photoPath!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: PhotoThumb(name: e.photoPath!, size: 40),
                ),
              )
            else
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.page,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  twoInitials(item.categoryName),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.categoryName,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatPaise(e.amountPaise),
              style: AppText.tabular
                  .copyWith(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
