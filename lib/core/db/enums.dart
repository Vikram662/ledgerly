// Enums are stored in SQLite by their `name`. Never rename or remove a value
// without a schema migration, or existing rows will fail to load.

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

/// Who uses the app (PRD C10). Decides the bottom tabs, the default seed
/// data and whether data entry needs the subscription.
enum UserType {
  contractor('Contractor', 'Workers, sites, attendance and bills',
      Icons.engineering_outlined),
  shop('Shopkeeper', 'Cloth, kirana, medical or any shop',
      Icons.storefront_outlined),
  personal('Personal', 'Salary, home expenses and savings',
      Icons.person_outline),
  lender('Lender', 'Loans given and taken, interest and profit',
      Icons.handshake_outlined);

  const UserType(this._label, this._description, this.icon);

  final String _label;
  final String _description;
  final IconData icon;

  String get label => tr(_label);
  String get description => tr(_description);

  /// Personal use is free; contractors and shops need the subscription.
  bool get isFree => this == UserType.personal;

  /// Contractors choose trades; the other types have one seed pack each.
  bool get usesTrades => this == UserType.contractor;

  /// A lender has everything a personal user has (expenses, reminders,
  /// people), plus loans. Lender is paid, so this is not [isFree].
  bool get personalLike => this == UserType.personal || this == UserType.lender;
}

/// Trades a contractor can work in (PRD C0). [seedFile] is the JSON file in
/// `assets/seed/` holding that trade's default roles, items and templates.
enum Trade {
  electrical('Electrical', 'electrical'),
  plumbing('Plumbing', 'plumbing'),
  civil('Civil / Construction', 'civil'),
  painting('Painting', 'painting'),
  tiles('Tiles / Flooring', 'tiles'),
  carpentry('Carpentry / Interior', 'carpentry'),
  pop('POP / False Ceiling', 'pop'),
  fabrication('Fabrication / Welding', 'fabrication'),
  labourSupply('Labour Supply', 'labour_supply'),
  other('Other', 'other');

  const Trade(this._label, this.seedFile);

  final String _label;
  final String seedFile;

  String get label => tr(_label);

  /// Stored in `BusinessProfile.trades` as comma separated names.
  static String encode(Iterable<Trade> trades) {
    final sorted = trades.toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return sorted.map((t) => t.name).join(',');
  }

  static Set<Trade> decode(String value) => {
        for (final name in value.split(','))
          if (name.isNotEmpty) Trade.values.byName(name),
      };
}

enum UnitDimension { count, length, area, volume, weight, time, other }

enum WageModel { daily, monthly, piece }

enum AttendanceStatus { present, half, absent, leavePaid, leaveUnpaid, off }

enum PaymentMode { cash, phonePe, paytm, gPay, bank, cheque }

enum LedgerType {
  advance,
  payment,
  bonus,
  deduction,
  emi,
  reversal,
  carryForward,
}

enum SettlementStatus { locked, reversed }

enum ItemKind { material, workRate, labour }

enum LineType { material, labour, workRate, lumpSum }

enum DocumentKind { quotation, invoice }

enum DocumentStatus { draft, sent, partiallyPaid, paid, cancelled }

enum JobStatus { planned, inProgress, completed }

/// Supplier khata (PRD EX-02): material on credit, or money paid.
enum SupplierEntryType { purchase, payment }

/// Loans (lender user type): money given to a borrower, or taken from
/// someone to lend on.
enum LoanDirection { given, taken }

/// A loan's term and interest run per day or per month.
enum LoanPeriod { day, month }

/// Interest as fixed rupees per period (₹400 a day on ₹1 lakh) or a percent
/// per period (2% a month).
enum LoanRateKind { fixed, percent }

enum LoanStatus { open, closed }

enum AuditAction { create, update, reverse, delete }

enum BackupTrigger { scheduled, onChange, manual, internetBack, preRestore }

enum BackupStatus { success, failed, skipped }

/// Task & Site Visit categories (PRD C8).
enum TaskType {
  siteVisit('Site Visit'),
  clientMeeting('Client Meeting'),
  materialProcurement('Material Purchase'),
  workerPayment('Worker Payment'),
  engineerReview('Engineer Review'),
  other('Other Task');

  const TaskType(this._label);
  final String _label;

  String get label => tr(_label);

  IconData get icon => switch (this) {
        TaskType.siteVisit => Icons.location_on_outlined,
        TaskType.clientMeeting => Icons.handshake_outlined,
        TaskType.materialProcurement => Icons.local_shipping_outlined,
        TaskType.workerPayment => Icons.payments_outlined,
        TaskType.engineerReview => Icons.engineering_outlined,
        TaskType.other => Icons.task_alt_outlined,
      };
}
