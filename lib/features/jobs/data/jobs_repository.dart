import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/audit.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/db/watch.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/ids.dart';

final jobsRepositoryProvider = Provider<JobsRepository>(
  (ref) => JobsRepository(ref.watch(databaseProvider)),
);

final jobsProvider = StreamProvider<List<JobListItem>>(
  (ref) => ref.watch(jobsRepositoryProvider).watchJobs(),
);

final jobDetailProvider = StreamProvider.family<JobDetail?, String>(
  (ref, id) => ref.watch(jobsRepositoryProvider).watchJob(id),
);

String jobStatusLabel(JobStatus status) => switch (status) {
      JobStatus.planned => tr('Planned'),
      JobStatus.inProgress => tr('In progress'),
      JobStatus.completed => tr('Completed'),
    };

class JobListItem {
  const JobListItem({
    required this.job,
    required this.clientName,
    this.billedPaise = 0,
    this.expensesPaise = 0,
    this.piecePaise = 0,
  });

  final Job job;
  final String clientName;

  /// Same rules as [JobDetail]: non-draft, non-cancelled invoices.
  final int billedPaise;
  final int expensesPaise;
  final int piecePaise;

  /// Billed − expenses − piece work, as on the job detail screen.
  int get profitPaise => billedPaise - expensesPaise - piecePaise;
}

/// PRD JB-01 / EX-03: a site with its bills and expenses.
class JobDetail {
  const JobDetail({
    required this.job,
    required this.client,
    required this.billedPaise,
    required this.receivedPaise,
    required this.expensesPaise,
    required this.piecePaise,
    required this.bills,
    required this.expenses,
    this.pieces = const [],
  });

  final Job job;
  final Client client;

  /// Non-cancelled, non-draft bills linked to this job.
  final int billedPaise;
  final int receivedPaise;
  final int expensesPaise;

  /// Piece work booked against this job.
  final int piecePaise;
  final List<BillDocument> bills;
  final List<Expense> expenses;

  /// Piece work booked against this job, newest first, with the worker.
  final List<({PieceWork piece, String workerName})> pieces;

  /// Billed − expenses − piece work. Daily-wage labour is not included yet.
  int get profitPaise => billedPaise - expensesPaise - piecePaise;
}

class JobsRepository {
  JobsRepository(this._db);

  final AppDatabase _db;

  Stream<List<JobListItem>> watchJobs() => watchComputed(
        _db,
        [
          _db.jobs,
          _db.clients,
          _db.documents,
          _db.expenses,
          _db.pieceWorks,
        ],
        () async {
          final rows = await (_db.select(_db.jobs).join([
            innerJoin(
                _db.clients, _db.clients.id.equalsExp(_db.jobs.clientId)),
          ])
                ..orderBy([
                  OrderingTerm.asc(_db.jobs.status),
                  OrderingTerm.desc(_db.jobs.createdAt),
                ]))
              .get();

          final billed = <String, int>{};
          final bills = await (_db.select(_db.documents)
                ..where((d) =>
                    d.jobId.isNotNull() &
                    d.kind.equalsValue(DocumentKind.invoice)))
              .get();
          for (final b in bills) {
            if (b.status == DocumentStatus.draft ||
                b.status == DocumentStatus.cancelled) {
              continue;
            }
            billed[b.jobId!] = (billed[b.jobId!] ?? 0) + b.totalPaise;
          }

          final spent = <String, int>{};
          final expenses = await (_db.select(_db.expenses)
                ..where((e) => e.jobId.isNotNull()))
              .get();
          for (final e in expenses) {
            spent[e.jobId!] = (spent[e.jobId!] ?? 0) + e.amountPaise;
          }

          final piece = <String, int>{};
          final pieces = await (_db.select(_db.pieceWorks)
                ..where((p) => p.jobId.isNotNull()))
              .get();
          for (final p in pieces) {
            piece[p.jobId!] = (piece[p.jobId!] ?? 0) + p.amountPaise;
          }

          return [
            for (final row in rows)
              () {
                final job = row.readTable(_db.jobs);
                return JobListItem(
                  job: job,
                  clientName: row.readTable(_db.clients).name,
                  billedPaise: billed[job.id] ?? 0,
                  expensesPaise: spent[job.id] ?? 0,
                  piecePaise: piece[job.id] ?? 0,
                );
              }(),
          ];
        },
      );

  Stream<JobDetail?> watchJob(String id) => watchComputed(
        _db,
        [
          _db.jobs,
          _db.documents,
          _db.paymentsReceived,
          _db.expenses,
          _db.pieceWorks,
          _db.workers,
        ],
        () async {
          final job = await (_db.select(_db.jobs)
                ..where((j) => j.id.equals(id)))
              .getSingleOrNull();
          if (job == null) return null;
          final client = await (_db.select(_db.clients)
                ..where((c) => c.id.equals(job.clientId)))
              .getSingle();
          final bills = await (_db.select(_db.documents)
                ..where((d) =>
                    d.jobId.equals(id) &
                    d.kind.equalsValue(DocumentKind.invoice))
                ..orderBy([(d) => OrderingTerm.desc(d.date)]))
              .get();
          final counted = bills.where((b) =>
              b.status != DocumentStatus.draft &&
              b.status != DocumentStatus.cancelled);
          final billIds = [for (final b in counted) b.id];
          final received = billIds.isEmpty
              ? 0
              : (await (_db.select(_db.paymentsReceived)
                        ..where((p) => p.documentId.isIn(billIds)))
                      .get())
                  .fold(0, (sum, p) => sum + p.amountPaise);
          final expenses = await (_db.select(_db.expenses)
                ..where((e) => e.jobId.equals(id))
                ..orderBy([(e) => OrderingTerm.desc(e.date)]))
              .get();
          final pieceRows = await (_db.select(_db.pieceWorks).join([
            innerJoin(
                _db.workers, _db.workers.id.equalsExp(_db.pieceWorks.workerId)),
          ])
                ..where(_db.pieceWorks.jobId.equals(id))
                ..orderBy([OrderingTerm.desc(_db.pieceWorks.date)]))
              .get();
          final pieces = [
            for (final row in pieceRows)
              (
                piece: row.readTable(_db.pieceWorks),
                workerName: row.readTable(_db.workers).name,
              ),
          ];
          return JobDetail(
            job: job,
            client: client,
            billedPaise: counted.fold(0, (sum, b) => sum + b.totalPaise),
            receivedPaise: received,
            expensesPaise: expenses.fold(0, (sum, e) => sum + e.amountPaise),
            piecePaise: pieces.fold(0, (sum, p) => sum + p.piece.amountPaise),
            bills: bills,
            expenses: expenses,
            pieces: pieces,
          );
        },
      );

  Future<String> saveJob({
    String? id,
    required String clientId,
    required String title,
    String? siteAddress,
    required JobStatus status,
    int? contractValuePaise,
  }) async {
    if (id == null) {
      final jobId = newId();
      await _db.into(_db.jobs).insert(JobsCompanion.insert(
            id: jobId,
            clientId: clientId,
            title: title,
            siteAddress: Value(siteAddress),
            status: status,
            contractValuePaise: Value(contractValuePaise),
          ));
      await writeAudit(_db,
          entity: 'job', entityId: jobId, action: AuditAction.create);
      return jobId;
    }
    await (_db.update(_db.jobs)..where((j) => j.id.equals(id))).write(
      JobsCompanion(
        clientId: Value(clientId),
        title: Value(title),
        siteAddress: Value(siteAddress),
        status: Value(status),
        contractValuePaise: Value(contractValuePaise),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    return id;
  }

  Future<void> setStatus(String id, JobStatus status) =>
      (_db.update(_db.jobs)..where((j) => j.id.equals(id))).write(
        JobsCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
}
