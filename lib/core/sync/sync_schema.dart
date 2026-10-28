import 'package:drift/drift.dart';

/// A child column that points at a synced table's `id`.
class SyncRef {
  const SyncRef(this.table, this.column);

  final String table;
  final String column;
}

/// What happens when a cloud row clashes on a unique key with a local row
/// that has another id.
enum ClashRule {
  /// Seeded masters: the cloud row wins, local references move to it and the
  /// local copy is deleted (a fresh install seeds its own copies).
  merge,

  /// The newer change wins; the other row is deleted (attendance marked for
  /// the same worker and day on two phones).
  newest,

  /// Bills are never merged: the local bill keeps its data and gets a new
  /// number.
  renumber,
}

/// One local table copied to the cloud (schema v6). Every synced table has a
/// UUID text `id`, so the same row is never stored twice in the cloud.
class SyncTable {
  const SyncTable(
    this.name, {
    this.changedColumn = 'updated_at',
    this.uniqueKeys = const [],
    this.references = const [],
    this.clashRule = ClashRule.merge,
  });

  /// SQL table name.
  final String name;

  /// Best known time of the row's last change, used when the whole database
  /// is queued again (first sync, after a Drive restore).
  final String changedColumn;

  /// Unique columns besides `id`; see [clashRule].
  final List<List<String>> uniqueKeys;

  /// Columns in other tables that point here, moved to the cloud row's id
  /// on a [ClashRule.merge].
  final List<SyncRef> references;

  final ClashRule clashRule;
}

/// Synced tables, parents before children. Not synced: `app_meta` (this
/// phone's state) and `backup_logs` (this phone's backup history).
const syncTables = <SyncTable>[
  SyncTable('business_profiles'),
  SyncTable('roles', uniqueKeys: [
    ['seed_key'],
  ], references: [
    SyncRef('workers', 'role_id'),
  ]),
  SyncTable('units', uniqueKeys: [
    ['code'],
    ['seed_key'],
  ], references: [
    SyncRef('item_masters', 'unit_id'),
    SyncRef('piece_works', 'unit_id'),
    SyncRef('document_lines', 'unit_id'),
  ]),
  SyncTable('expense_categories', uniqueKeys: [
    ['seed_key'],
  ], references: [
    SyncRef('expenses', 'category_id'),
  ]),
  SyncTable('item_masters', uniqueKeys: [
    ['seed_key'],
  ], references: [
    SyncRef('piece_works', 'item_id'),
    SyncRef('document_lines', 'item_id'),
  ]),
  SyncTable('bill_templates', uniqueKeys: [
    ['seed_key'],
  ]),
  SyncTable('workers'),
  SyncTable('wage_histories'),
  SyncTable('holidays', uniqueKeys: [
    ['date'],
  ], clashRule: ClashRule.newest),
  SyncTable('clients'),
  SyncTable('jobs'),
  SyncTable('attendances', uniqueKeys: [
    ['worker_id', 'date'],
  ], clashRule: ClashRule.newest),
  SyncTable('settlements'),
  SyncTable('piece_works'),
  SyncTable('ledger_entries'),
  SyncTable('documents', uniqueKeys: [
    ['kind', 'number', 'revision'],
  ], clashRule: ClashRule.renumber),
  SyncTable('document_lines'),
  SyncTable('payments_received'),
  SyncTable('expenses'),
  SyncTable('suppliers'),
  SyncTable('supplier_ledger'),
  SyncTable('task_reminders'),
  SyncTable('audit_logs', changedColumn: 'at'),
];

final syncTablesByName = {for (final t in syncTables) t.name: t};

/// `app_meta` key present only while cloud rows are being written, so the
/// triggers do not queue them to be sent back.
const syncApplyingKey = 'sync_applying';

/// Epoch milliseconds in SQLite.
const nowMsSql =
    "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)";

/// Creates the outbox and one insert/update/delete trigger per synced table.
/// Every local change lands in `sync_outbox` without touching any
/// repository; the sync engine sends the current row (or a delete).
Future<void> createSyncSchema(DatabaseConnectionUser db) async {
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS sync_outbox (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      tbl TEXT NOT NULL,
      row_id TEXT NOT NULL,
      changed_at INTEGER NOT NULL
    )''');
  await db.customStatement('CREATE INDEX IF NOT EXISTS sync_outbox_row_idx '
      'ON sync_outbox (tbl, row_id)');
  const notApplying = "NOT EXISTS (SELECT 1 FROM app_meta "
      "WHERE meta_key = '$syncApplyingKey')";
  for (final table in syncTables) {
    final t = table.name;
    for (final (event, row) in const [
      ('INSERT', 'NEW'),
      ('UPDATE', 'NEW'),
      ('DELETE', 'OLD'),
    ]) {
      await db.customStatement('''
        CREATE TRIGGER IF NOT EXISTS sync_${t}_${event.toLowerCase()}
        AFTER $event ON $t WHEN $notApplying
        BEGIN
          INSERT INTO sync_outbox (tbl, row_id, changed_at)
          VALUES ('$t', $row.id, $nowMsSql);
        END''');
    }
  }
}

/// Queues every synced row again and forgets the pull position. Used on the
/// first sync after the upgrade and after a Drive restore. Each row keeps its
/// own last-change time, so a cloud row changed later still wins and nothing
/// is duplicated (rows are matched by id).
Future<void> queueAllForSync(DatabaseConnectionUser db) async {
  await db.customStatement('DELETE FROM sync_outbox');
  for (final table in syncTables) {
    await db.customStatement(
      'INSERT INTO sync_outbox (tbl, row_id, changed_at) '
      "SELECT '${table.name}', id, COALESCE(${table.changedColumn}, 0) "
      'FROM ${table.name}',
    );
  }
  await db.customStatement(
    "DELETE FROM app_meta WHERE meta_key IN ('sync_pull_after', 'sync_account')",
  );
}
