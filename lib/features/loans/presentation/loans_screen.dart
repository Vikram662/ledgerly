import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/loans_repository.dart';
import 'loan_widgets.dart';

/// Lender's Loans tab: profit on top, then loans given, loans taken and
/// people. [tab]: 0 given, 1 taken, 2 people.
class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({super.key, this.tab, this.showMenu = false});

  final int? tab;

  /// True when this is a bottom tab: big title and no Back.
  final bool showMenu;

  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

enum _Filter { open, late, closed }

class _LoansScreenState extends ConsumerState<LoansScreen> {
  late int _tab = (widget.tab ?? 0).clamp(0, 2);
  _Filter _filter = _Filter.open;

  @override
  void didUpdateWidget(LoansScreen old) {
    super.didUpdateWidget(old);
    if (widget.tab != null && widget.tab != old.tab) {
      _tab = widget.tab!.clamp(0, 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final views = ref.watch(loanViewsProvider);
    final summary = ref.watch(loansSummaryProvider);
    final (fabLabel, fabRoute) = switch (_tab) {
      0 => (tr('Loan given'), Routes.newLoan(LoanDirection.given)),
      1 => (tr('Loan taken'), Routes.newLoan(LoanDirection.taken)),
      _ => (tr('Add person'), Routes.addLoanParty),
    };
    return Scaffold(
      appBar: widget.showMenu
          ? tabAppBar(tr('Loans'))
          : AppBar(title: Text(tr('Loans'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(fabRoute),
        icon: const Icon(Icons.add),
        label: Text(fabLabel),
      ),
      body: views.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => Center(child: Text(errorText(e))),
        data: (all) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (summary != null) _ProfitHero(summary: summary),
            const SizedBox(height: 12),
            SegmentedTabs<int>(
              value: _tab,
              options: {0: tr('Given'), 1: tr('Taken'), 2: tr('People')},
              onChanged: (t) => setState(() => _tab = t),
            ),
            const SizedBox(height: 12),
            if (_tab == 2)
              const _PeopleList()
            else
              ..._loanList(all
                  .where((v) =>
                      v.loan.direction ==
                      (_tab == 0 ? LoanDirection.given : LoanDirection.taken))
                  .toList()),
          ],
        ),
      ),
    );
  }

  List<Widget> _loanList(List<LoanView> list) {
    bool matches(LoanView v) => switch (_filter) {
          _Filter.open => v.open,
          _Filter.late => v.open && v.statement.overdueDays > 0,
          _Filter.closed => !v.open,
        };
    final shown = list.where(matches).toList()
      ..sort((a, b) => a.loan.dueDate.compareTo(b.loan.dueDate));
    final lateCount =
        list.where((v) => v.open && v.statement.overdueDays > 0).length;
    final given = _tab == 0;
    return [
      ChipRow(
        children: [
          for (final (filter, label) in [
            (_Filter.open, tr('Running')),
            (_Filter.late, tr('Late ({count})', {'count': lateCount})),
            (_Filter.closed, tr('Closed')),
          ])
            AppChip(
              label: label,
              selected: _filter == filter,
              onTap: () => setState(() => _filter = filter),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (list.isEmpty)
        EmptyState(
          icon: given ? Icons.call_made : Icons.call_received,
          title: given ? tr('No loans given yet') : tr('No loans taken yet'),
          message: given
              ? tr('Add the money you lend: amount, days or months and interest.')
              : tr('Add the money you take from others to lend on.'),
          actionLabel: given ? tr('Loan given') : tr('Loan taken'),
          onAction: () => context.push(Routes.newLoan(
              given ? LoanDirection.given : LoanDirection.taken)),
        )
      else if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            tr('Nothing here.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
        )
      else
        CardList(children: [for (final v in shown) LoanTile(view: v)]),
    ];
  }
}

/// Dark card: this month's profit, total profit, money out and owed.
class _ProfitHero extends StatelessWidget {
  const _ProfitHero({required this.summary});

  final LoansSummary summary;

  @override
  Widget build(BuildContext context) {
    const soft = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.inputBorder,
    );
    final figure = AppText.tabular.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: Colors.white,
    );
    Widget cell(String label, int paise) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: soft),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(formatPaise(paise), style: figure),
              ),
            ],
          ),
        );
    return HeroPanel(
      label: tr('Profit this month'),
      value: formatPaise(summary.profitThisMonthPaise),
      note: tr('Interest received − interest paid · Total {total}',
          {'total': formatPaise(summary.profitTotalPaise)}),
      footer: Row(
        children: [
          cell(tr('Given out'), summary.givenOutPaise),
          cell(tr('To pay back'), summary.takenOutPaise),
          cell(tr('Expected profit'), summary.expectedProfitPaise),
        ],
      ),
    );
  }
}

class _PeopleList extends ConsumerWidget {
  const _PeopleList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parties = ref.watch(loanPartiesProvider).valueOrNull;
    final views = ref.watch(loanViewsProvider).valueOrNull ?? const [];
    if (parties == null) return const ListSkeleton(rows: 3);
    if (parties.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline,
        title: tr('No people yet'),
        message: tr('Add the people you lend to and the people you take money from.'),
        actionLabel: tr('Add person'),
        onAction: () => context.push(Routes.addLoanParty),
      );
    }
    return CardList(
      children: [
        for (final p in parties)
          Builder(builder: (context) {
            final mine = views.where((v) => v.party.id == p.id && v.open);
            final toGet = mine
                .where((v) => v.given)
                .fold(0, (s, v) => s + v.statement.balancePaise);
            final toPay = mine
                .where((v) => !v.given)
                .fold(0, (s, v) => s + v.statement.balancePaise);
            return ListTile(
              leading: InitialsAvatar(p.name),
              title: Text(p.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: p.phone == null
                  ? null
                  : Text(formatIndianPhone(p.phone!)),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (toGet > 0)
                    Text(tr('To get {amount}', {'amount': formatPaise(toGet)}),
                        style: AppText.tabular.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.successText)),
                  if (toPay > 0)
                    Text(tr('To pay {amount}', {'amount': formatPaise(toPay)}),
                        style: AppText.tabular.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.dangerText)),
                ],
              ),
              onTap: () => context.push(Routes.loanParty(p.id)),
            );
          }),
      ],
    );
  }
}
