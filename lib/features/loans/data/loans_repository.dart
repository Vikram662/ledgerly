import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/audit.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/db/tables.dart';
import '../../../core/db/watch.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/ids.dart';
import '../domain/loan_calculator.dart';

final loansRepositoryProvider = Provider<LoansRepository>(
  (ref) => LoansRepository(ref.watch(databaseProvider)),
);

/// Every loan with its party, payments and today's statement.
final loanViewsProvider = StreamProvider<List<LoanView>>(
  (ref) => ref.watch(loansRepositoryProvider).watchLoans(),
);

final loanViewProvider = StreamProvider.family<LoanView?, String>(
  (ref, id) => ref.watch(loansRepositoryProvider).watchLoans().map(
        (all) => all.where((l) => l.loan.id == id).firstOrNull,
      ),
);

final loanPartiesProvider = StreamProvider<List<LoanParty>>(
  (ref) => ref.watch(loansRepositoryProvider).watchParties(),
);

final loansSummaryProvider = Provider<LoansSummary?>((ref) {
  final views = ref.watch(loanViewsProvider).valueOrNull;
  return views == null ? null : LoansSummary.of(views, DateTime.now());
});

LoanTerms termsOf(Loan loan) => LoanTerms(
      principalPaise: loan.principalPaise,
      start: parseIsoDate(loan.startDate),
      termCount: loan.termCount,
      period: loan.period,
      rateKind: loan.rateKind,
      rateValue: loan.rateValue,
    );

class LoanView {
  const LoanView({
    required this.loan,
    required this.party,
    required this.payments,
    required this.statement,
    this.source,
    this.dealCostPaise,
  });

  final Loan loan;
  final LoanParty party;

  /// Newest first.
  final List<LoanPayment> payments;
  final LoanStatement statement;

  /// For a given loan: the taken loan its money came from.
  final LoanView? source;

  /// What the source money cost for this deal so far.
  final int? dealCostPaise;

  bool get given => loan.direction == LoanDirection.given;
  bool get open => loan.status == LoanStatus.open;
  LoanTerms get terms => termsOf(loan);

  /// Interest earned on this deal minus what its money cost.
  int? get dealProfitPaise => dealCostPaise == null
      ? null
      : statement.interestAccruedPaise - dealCostPaise!;

  bool dueOn(DateTime day) =>
      open && statement.balancePaise > 0 && isoDate(day) == loan.dueDate;
}

/// Home and Loans tab totals.
class LoansSummary {
  const LoansSummary({
    required this.givenOutPaise,
    required this.takenOutPaise,
    required this.interestToReceivePaise,
    required this.interestToPayPaise,
    required this.profitThisMonthPaise,
    required this.profitTotalPaise,
    required this.dueToday,
    required this.overdue,
  });

  factory LoansSummary.of(List<LoanView> views, DateTime now) {
    var givenOut = 0, takenOut = 0, toReceive = 0, toPay = 0;
    var monthProfit = 0, totalProfit = 0, dueToday = 0, overdue = 0;
    for (final v in views) {
      final s = v.statement;
      final sign = v.given ? 1 : -1;
      if (v.open) {
        if (v.given) {
          givenOut += s.balancePaise;
          toReceive += s.interestOwedPaise;
        } else {
          takenOut += s.balancePaise;
          toPay += s.interestOwedPaise;
        }
        if (v.dueOn(now)) dueToday++;
        if (s.overdueDays > 0) overdue++;
      }
      for (final split in s.splits) {
        totalProfit += sign * split.interestPaise;
        if (split.date.year == now.year && split.date.month == now.month) {
          monthProfit += sign * split.interestPaise;
        }
      }
    }
    return LoansSummary(
      givenOutPaise: givenOut,
      takenOutPaise: takenOut,
      interestToReceivePaise: toReceive,
      interestToPayPaise: toPay,
      profitThisMonthPaise: monthProfit,
      profitTotalPaise: totalProfit,
      dueToday: dueToday,
      overdue: overdue,
    );
  }

  /// Still out with borrowers (principal + interest run up).
  final int givenOutPaise;

  /// Still owed to the people money was taken from.
  final int takenOutPaise;
  final int interestToReceivePaise;
  final int interestToPayPaise;

  /// Interest received minus interest paid, by payment date.
  final int profitThisMonthPaise;
  final int profitTotalPaise;
  final int dueToday;
  final int overdue;

  /// Profit if everything owed today were settled now.
  int get expectedProfitPaise =>
      profitTotalPaise + interestToReceivePaise - interestToPayPaise;
}

class LoansRepository {
  LoansRepository(this._db);

  final AppDatabase _db;

  Stream<List<LoanParty>> watchParties() => (_db.select(_db.loanParties)
        ..orderBy([(p) => OrderingTerm.asc(p.name.lower())]))
      .watch();

  Stream<List<LoanView>> watchLoans() => watchComputed(
        _db,
        [_db.loans, _db.loanParties, _db.loanPayments],
        () => loadLoans(DateTime.now()),
      );

  /// Every loan with its statement on [asOf]; newest first.
  Future<List<LoanView>> loadLoans(DateTime asOf) async {
    final parties = {
      for (final p in await _db.select(_db.loanParties).get()) p.id: p,
    };
    final payments = <String, List<LoanPayment>>{};
    for (final p in await (_db.select(_db.loanPayments)
          ..orderBy([
            (p) => OrderingTerm.desc(p.date),
            (p) => OrderingTerm.desc(p.createdAt),
          ]))
        .get()) {
      payments.putIfAbsent(p.loanId, () => []).add(p);
    }
    final loans = await (_db.select(_db.loans)
          ..orderBy([
            (l) => OrderingTerm.desc(l.startDate),
            (l) => OrderingTerm.desc(l.createdAt),
          ]))
        .get();

    LoanView view(Loan loan, {LoanView? source}) {
      final list = payments[loan.id] ?? const <LoanPayment>[];
      final closedOn =
          loan.closedDate == null ? null : parseIsoDate(loan.closedDate!);
      final statement = computeStatement(
        termsOf(loan),
        [
          for (final p in list)
            LoanPaymentInput(
              id: p.id,
              date: parseIsoDate(p.date),
              amountPaise: p.amountPaise,
            ),
        ],
        asOf: asOf,
        closedOn: closedOn,
      );
      return LoanView(
        loan: loan,
        party: parties[loan.partyId] ??
            LoanParty(
              id: loan.partyId,
              name: '?',
              createdAt: 0,
              updatedAt: 0,
            ),
        payments: list,
        statement: statement,
        source: source,
        dealCostPaise: source == null
            ? null
            : dealCostPaise(termsOf(loan), source.terms, closedOn ?? asOf),
      );
    }

    final taken = {
      for (final l in loans)
        if (l.direction == LoanDirection.taken) l.id: view(l),
    };
    return [
      for (final l in loans)
        taken[l.id] ??
            view(l,
                source:
                    l.sourceLoanId == null ? null : taken[l.sourceLoanId]),
    ];
  }

  // ─── People ───────────────────────────────────────────────────────────────

  Future<String> saveParty({
    String? id,
    required String name,
    String? phone,
    String? address,
    String? note,
  }) async {
    if (id == null) {
      final newPartyId = newId();
      await _db.into(_db.loanParties).insert(LoanPartiesCompanion.insert(
            id: newPartyId,
            name: name,
            phone: Value(phone),
            address: Value(address),
            note: Value(note),
          ));
      return newPartyId;
    }
    await (_db.update(_db.loanParties)..where((p) => p.id.equals(id))).write(
      LoanPartiesCompanion(
        name: Value(name),
        phone: Value(phone),
        address: Value(address),
        note: Value(note),
        updatedAt: Value(nowMs()),
      ),
    );
    return id;
  }

  /// Only a person with no loans can be deleted. False when they have one.
  Future<bool> deleteParty(String id) => _db.transaction(() async {
        final used = await (_db.select(_db.loans)
              ..where((l) => l.partyId.equals(id))
              ..limit(1))
            .getSingleOrNull();
        if (used != null) return false;
        await (_db.delete(_db.loanParties)..where((p) => p.id.equals(id)))
            .go();
        return true;
      });

  // ─── Loans ────────────────────────────────────────────────────────────────

  Future<String> saveLoan({
    String? id,
    required LoanDirection direction,
    required String partyId,
    required int principalPaise,
    required DateTime startDate,
    required int termCount,
    required LoanPeriod period,
    required LoanRateKind rateKind,
    required int rateValue,
    String? sourceLoanId,
    String? note,
  }) async {
    if (principalPaise <= 0) throw ArgumentError('Amount must be more than 0');
    if (termCount <= 0) throw ArgumentError('Term must be at least 1');
    if (rateValue < 0) throw ArgumentError('Rate cannot be negative');
    final due = addPeriods(dateOnly(startDate), termCount, period);
    final source = direction == LoanDirection.given ? sourceLoanId : null;
    if (id == null) {
      final newLoanId = newId();
      await _db.into(_db.loans).insert(LoansCompanion.insert(
            id: newLoanId,
            direction: direction,
            partyId: partyId,
            principalPaise: principalPaise,
            startDate: isoDate(startDate),
            termCount: termCount,
            period: period,
            dueDate: isoDate(due),
            rateKind: rateKind,
            rateValue: rateValue,
            sourceLoanId: Value(source),
            status: LoanStatus.open,
            note: Value(note),
          ));
      await writeAudit(_db,
          entity: 'loan',
          entityId: newLoanId,
          action: AuditAction.create,
          after: {
            'direction': direction.name,
            'partyId': partyId,
            'principalPaise': principalPaise,
          });
      return newLoanId;
    }
    await (_db.update(_db.loans)..where((l) => l.id.equals(id))).write(
      LoansCompanion(
        direction: Value(direction),
        partyId: Value(partyId),
        principalPaise: Value(principalPaise),
        startDate: Value(isoDate(startDate)),
        termCount: Value(termCount),
        period: Value(period),
        dueDate: Value(isoDate(due)),
        rateKind: Value(rateKind),
        rateValue: Value(rateValue),
        sourceLoanId: Value(source),
        note: Value(note),
        updatedAt: Value(nowMs()),
      ),
    );
    await _closeIfSettled(id);
    return id;
  }

  /// Interest stops on [date]; whatever is unpaid is written off.
  Future<void> closeLoan(String id, DateTime date) =>
      (_db.update(_db.loans)..where((l) => l.id.equals(id))).write(
        LoansCompanion(
          status: const Value(LoanStatus.closed),
          closedDate: Value(isoDate(date)),
          updatedAt: Value(nowMs()),
        ),
      );

  Future<void> reopenLoan(String id) =>
      (_db.update(_db.loans)..where((l) => l.id.equals(id))).write(
        LoansCompanion(
          status: const Value(LoanStatus.open),
          closedDate: const Value(null),
          updatedAt: Value(nowMs()),
        ),
      );

  /// Deletes the loan with its payments. Loans lent from it keep their data
  /// and only lose the link.
  Future<void> deleteLoan(String id) => _db.transaction(() async {
        final before = await (_db.select(_db.loans)
              ..where((l) => l.id.equals(id)))
            .getSingle();
        await (_db.update(_db.loans)..where((l) => l.sourceLoanId.equals(id)))
            .write(LoansCompanion(
          sourceLoanId: const Value(null),
          updatedAt: Value(nowMs()),
        ));
        await (_db.delete(_db.loanPayments)..where((p) => p.loanId.equals(id)))
            .go();
        await (_db.delete(_db.loans)..where((l) => l.id.equals(id))).go();
        await writeAudit(_db,
            entity: 'loan',
            entityId: id,
            action: AuditAction.delete,
            before: before.toJson());
      });

  // ─── Payments ─────────────────────────────────────────────────────────────

  /// Money received (given loan) or paid back (taken loan). The loan closes
  /// by itself once nothing is owed.
  Future<String> addPayment({
    required String loanId,
    required DateTime date,
    required int amountPaise,
    required PaymentMode mode,
    String? note,
  }) async {
    if (amountPaise <= 0) throw ArgumentError('Amount must be more than 0');
    final id = newId();
    await _db.transaction(() async {
      await _db.into(_db.loanPayments).insert(LoanPaymentsCompanion.insert(
            id: id,
            loanId: loanId,
            date: isoDate(date),
            amountPaise: amountPaise,
            mode: mode,
            note: Value(note),
          ));
      await writeAudit(_db,
          entity: 'loan_payment',
          entityId: id,
          action: AuditAction.create,
          after: {'loanId': loanId, 'amountPaise': amountPaise});
      await _closeIfSettled(loanId);
    });
    return id;
  }

  /// A deleted payment reopens a loan that it had closed.
  Future<void> deletePayment(String id) => _db.transaction(() async {
        final before = await (_db.select(_db.loanPayments)
              ..where((p) => p.id.equals(id)))
            .getSingle();
        await (_db.delete(_db.loanPayments)..where((p) => p.id.equals(id)))
            .go();
        await writeAudit(_db,
            entity: 'loan_payment',
            entityId: id,
            action: AuditAction.delete,
            before: before.toJson());
        final loan = await _loan(before.loanId);
        if (loan.status == LoanStatus.closed) {
          final paidUp = await _settledOn(loan);
          if (paidUp == null) await reopenLoan(loan.id);
        }
      });

  Future<Loan> _loan(String id) =>
      (_db.select(_db.loans)..where((l) => l.id.equals(id))).getSingle();

  /// The day of the payment that cleared [loan], or null if still owed.
  Future<DateTime?> _settledOn(Loan loan) async {
    final payments = await (_db.select(_db.loanPayments)
          ..where((p) => p.loanId.equals(loan.id)))
        .get();
    if (payments.isEmpty) return null;
    final inputs = [
      for (final p in payments)
        LoanPaymentInput(
          id: p.id,
          date: parseIsoDate(p.date),
          amountPaise: p.amountPaise,
        ),
    ];
    final lastDay = inputs
        .map((p) => p.date)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    // Owed on the day of the last payment, so a payoff is not undone by
    // interest counted after it.
    final statement = computeStatement(termsOf(loan), inputs, asOf: lastDay);
    return statement.settled ? lastDay : null;
  }

  Future<void> _closeIfSettled(String loanId) async {
    final loan = await _loan(loanId);
    if (loan.status == LoanStatus.closed) return;
    final day = await _settledOn(loan);
    if (day != null) await closeLoan(loanId, day);
  }
}
