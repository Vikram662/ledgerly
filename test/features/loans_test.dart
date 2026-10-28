import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/db/database.dart';
import 'package:thekedaar/core/db/enums.dart';
import 'package:thekedaar/features/loans/data/loans_repository.dart';
import 'package:thekedaar/features/loans/domain/loan_calculator.dart';

const lakh = 100000 * 100; // ₹1,00,000 in paise

LoanTerms daily({int principal = lakh, int perDay = 40000, int days = 5}) =>
    LoanTerms(
      principalPaise: principal,
      start: DateTime(2026, 10, 1),
      termCount: days,
      period: LoanPeriod.day,
      rateKind: LoanRateKind.fixed,
      rateValue: perDay,
    );

LoanPaymentInput pay(String id, DateTime date, int paise) =>
    LoanPaymentInput(id: id, date: date, amountPaise: paise);

void main() {
  group('loan calculator', () {
    test('₹1 lakh for 5 days at ₹400 a day comes back as ₹1,02,000', () {
      final terms = daily();
      expect(terms.dueDate, DateTime(2026, 10, 6));
      expect(terms.termInterestPaise, 2000 * 100);
      expect(terms.termTotalPaise, 102000 * 100);

      final onDue = computeStatement(terms, const [],
          asOf: DateTime(2026, 10, 6));
      expect(onDue.balancePaise, 102000 * 100);
      expect(onDue.overdueDays, 0);
    });

    test('interest keeps running at the same rate after the due date', () {
      final late = computeStatement(daily(), const [],
          asOf: DateTime(2026, 10, 9));
      expect(late.interestOwedPaise, 8 * 400 * 100);
      expect(late.overdueDays, 3);
    });

    test('2% a month: whole months, then days as a share of 30', () {
      final terms = LoanTerms(
        principalPaise: lakh,
        start: DateTime(2026, 1, 31),
        termCount: 2,
        period: LoanPeriod.month,
        rateKind: LoanRateKind.percent,
        rateValue: 200,
      );
      expect(terms.dueDate, DateTime(2026, 3, 31));
      expect(terms.termInterestPaise, 4000 * 100);
      // 31 Jan → 28 Feb is one month; 15 more days is half a month.
      final s = computeStatement(terms, const [], asOf: DateTime(2026, 3, 15));
      expect(s.interestOwedPaise, 3000 * 100);
    });

    test('a payment clears interest first, then principal', () {
      final s = computeStatement(
        daily(),
        [pay('p1', DateTime(2026, 10, 3), 50800 * 100)],
        asOf: DateTime(2026, 10, 3),
      );
      // 2 days of interest = ₹800, the rest goes to principal.
      expect(s.splits.single.interestPaise, 800 * 100);
      expect(s.splits.single.principalPaise, 50000 * 100);
      expect(s.principalLeftPaise, 50000 * 100);
      // Half the principal left: the fixed rate halves to ₹200 a day.
      final later = computeStatement(
        daily(),
        [pay('p1', DateTime(2026, 10, 3), 50800 * 100)],
        asOf: DateTime(2026, 10, 6),
      );
      expect(later.interestOwedPaise, 3 * 200 * 100);
    });

    test('a closed loan stops interest and writes off the rest', () {
      final s = computeStatement(
        daily(),
        [pay('p1', DateTime(2026, 10, 6), 100000 * 100)],
        asOf: DateTime(2026, 10, 20),
        closedOn: DateTime(2026, 10, 6),
      );
      expect(s.balancePaise, 0);
      expect(s.writtenOffPaise, 2000 * 100);
      expect(s.overdueDays, 0);
    });

    test('deal profit is interest earned minus what the source money cost',
        () {
      final given = daily();
      // Taken ₹2 lakh at ₹500 a day: ₹250 a day for this ₹1 lakh deal.
      final source = LoanTerms(
        principalPaise: 2 * lakh,
        start: DateTime(2026, 9, 25),
        termCount: 30,
        period: LoanPeriod.day,
        rateKind: LoanRateKind.fixed,
        rateValue: 50000,
      );
      expect(dealCostPaise(given, source, DateTime(2026, 10, 6)),
          5 * 250 * 100);
    });
  });

  group('loans repository', () {
    late AppDatabase db;
    late LoansRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = LoansRepository(db);
    });

    tearDown(() => db.close());

    test('full payment closes the loan; deleting it reopens', () async {
      final borrower = await repo.saveParty(name: 'Ramesh');
      final loanId = await repo.saveLoan(
        direction: LoanDirection.given,
        partyId: borrower,
        principalPaise: lakh,
        startDate: DateTime(2026, 10, 1),
        termCount: 5,
        period: LoanPeriod.day,
        rateKind: LoanRateKind.fixed,
        rateValue: 40000,
      );
      final paymentId = await repo.addPayment(
        loanId: loanId,
        date: DateTime(2026, 10, 6),
        amountPaise: 102000 * 100,
        mode: PaymentMode.cash,
      );
      var loan = (await repo.loadLoans(DateTime(2026, 10, 20))).single;
      expect(loan.loan.status, LoanStatus.closed);
      expect(loan.loan.closedDate, '2026-10-06');
      expect(loan.statement.writtenOffPaise, 0);

      await repo.deletePayment(paymentId);
      loan = (await repo.loadLoans(DateTime(2026, 10, 20))).single;
      expect(loan.loan.status, LoanStatus.open);
    });

    test('summary: money out, money owed and profit', () async {
      final source = await repo.saveParty(name: 'Seth ji');
      final borrower = await repo.saveParty(name: 'Ramesh');
      final takenId = await repo.saveLoan(
        direction: LoanDirection.taken,
        partyId: source,
        principalPaise: lakh,
        startDate: DateTime(2026, 10, 1),
        termCount: 5,
        period: LoanPeriod.day,
        rateKind: LoanRateKind.fixed,
        rateValue: 30000,
      );
      final givenId = await repo.saveLoan(
        direction: LoanDirection.given,
        partyId: borrower,
        principalPaise: lakh,
        startDate: DateTime(2026, 10, 1),
        termCount: 5,
        period: LoanPeriod.day,
        rateKind: LoanRateKind.fixed,
        rateValue: 40000,
        sourceLoanId: takenId,
      );
      await repo.addPayment(
        loanId: givenId,
        date: DateTime(2026, 10, 6),
        amountPaise: 102000 * 100,
        mode: PaymentMode.cash,
      );
      await repo.addPayment(
        loanId: takenId,
        date: DateTime(2026, 10, 6),
        amountPaise: 101500 * 100,
        mode: PaymentMode.bank,
      );

      final views = await repo.loadLoans(DateTime(2026, 10, 6));
      final given = views.firstWhere((v) => v.given);
      expect(given.dealProfitPaise, 500 * 100);

      final summary = LoansSummary.of(views, DateTime(2026, 10, 6));
      expect(summary.profitThisMonthPaise, 500 * 100);
      expect(summary.givenOutPaise, 0);
      expect(summary.takenOutPaise, 0);
    });
  });
}
