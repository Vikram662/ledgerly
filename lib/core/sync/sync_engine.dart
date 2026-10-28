import 'package:drift/drift.dart';

import '../db/database.dart';
import '../db/meta_store.dart';
import '../security/secure_store.dart';
import 'sync_api.dart';
import 'sync_schema.dart';

enum SyncOutcome { synced, notReady, failed }

class SyncResult {
  const SyncResult(this.outcome, {this.pushed = 0, this.pulled = 0, this.error});

  final SyncOutcome outcome;
  final int pushed;
  final int pulled;
  final String? error;
}

/// Two-way cloud sync of the local database (offline first).
///
/// - Every local change is queued in `sync_outbox` by SQLite triggers, so
///   the app keeps working offline and nothing is lost.
/// - Push sends the current row (or a delete) for each queued id. The cloud
///   keys rows by their UUID, so a retry or a Drive restore updates the
///   same row and never adds a copy. The newer change wins.
/// - Pull brings rows changed in the cloud since the last pull. A row with
///   a local change still queued is skipped; that change is sent next and
///   the newer of the two wins.
class SyncEngine {
  SyncEngine({required AppDatabase db, SyncApi? api, SecureStore? secureStore})
      : _db = db,
        _api = api ?? SyncApi(secureStore ?? SecureStore());

  final AppDatabase _db;
  final SyncApi _api;

  static const pushBatch = 200;

  /// One run at a time in this isolate; a second caller waits for it.
  static Future<SyncResult>? _running;

  MetaStore get _meta => MetaStore(_db);

  Future<SyncResult> run() {
    final running = _running;
    if (running != null) return running;
    final future = _run();
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<SyncResult> _run() async {
    if (!await _api.ready) return const SyncResult(SyncOutcome.notReady);
    try {
      var pushed = 0;
      var pulled = 0;
      // A fresh install pulls first: its own seeded masters then merge into
      // the account's existing ones before anything is sent.
      if (await _meta.getInt(MetaKeys.syncPullAfter) == null) {
        pulled += await _pullAll();
      }
      pushed += await _pushAll();
      pulled += await _pullAll();
      // Merging pulled rows can queue changes (a clashing local row was
      // moved or deleted); send them now so the cloud matches.
      if (await pendingCount() > 0) pushed += await _pushAll();
      await _meta.setInt(
          MetaKeys.lastSyncAt, DateTime.now().millisecondsSinceEpoch);
      await _meta.remove(MetaKeys.lastSyncError);
      return SyncResult(SyncOutcome.synced, pushed: pushed, pulled: pulled);
    } on _AccountChanged {
      // Everything was queued again for the new account; start over.
      return _run();
    } catch (error) {
      await _meta.set(MetaKeys.lastSyncError, '$error');
      return SyncResult(SyncOutcome.failed, error: '$error');
    }
  }

  /// Number of local changes not yet in the cloud.
  Future<int> pendingCount() async {
    final row = await _db
        .customSelect(
            'SELECT COUNT(DISTINCT tbl || row_id) AS n FROM sync_outbox')
        .getSingle();
    return row.read<int>('n');
  }

  /// The phone was synced with one account and now another is signed in:
  /// everything on the phone goes to the new account and its data comes
  /// down in full.
  Future<void> _checkAccount(String account) async {
    final known = await _meta.get(MetaKeys.syncAccount);
    if (known == account) return;
    if (known != null) {
      await _db.transaction(() => queueAllForSync(_db));
      await _meta.set(MetaKeys.syncAccount, account);
      throw const _AccountChanged();
    }
    await _meta.set(MetaKeys.syncAccount, account);
  }

  // ─── Push ─────────────────────────────────────────────────────────────────

  Future<int> _pushAll() async {
    var total = 0;
    while (true) {
      final batch = await _readOutbox();
      if (batch.isEmpty) return total;
      await _checkAccount(await _api.push([for (final e in batch) e.row]));
      await _db.transaction(() async {
        for (final entry in batch) {
          // Only what was sent; a newer change keeps its outbox entry.
          await _db.customStatement(
            'DELETE FROM sync_outbox WHERE tbl = ? AND row_id = ? AND seq <= ?',
            [entry.row.table, entry.row.id, entry.lastSeq],
          );
        }
      });
      total += batch.length;
    }
  }

  Future<List<_Outgoing>> _readOutbox() => _db.transaction(() async {
        final queued = await _db.customSelect(
          'SELECT tbl, row_id, MAX(changed_at) AS changed_at, '
          'MAX(seq) AS last_seq FROM sync_outbox '
          'GROUP BY tbl, row_id ORDER BY last_seq LIMIT ?',
          variables: [Variable.withInt(pushBatch)],
        ).get();
        final out = <_Outgoing>[];
        for (final entry in queued) {
          final table = entry.read<String>('tbl');
          final id = entry.read<String>('row_id');
          final lastSeq = entry.read<int>('last_seq');
          if (!syncTablesByName.containsKey(table)) {
            await _db.customStatement(
                'DELETE FROM sync_outbox WHERE tbl = ?', [table]);
            continue;
          }
          final current = await _db.customSelect(
            'SELECT * FROM $table WHERE id = ?',
            variables: [Variable.withString(id)],
          ).getSingleOrNull();
          out.add(_Outgoing(
            SyncRow(
              table: table,
              id: id,
              at: entry.read<int>('changed_at'),
              data: current == null ? null : Map.of(current.data),
              deleted: current == null,
            ),
            lastSeq,
          ));
        }
        return out;
      });

  // ─── Pull ─────────────────────────────────────────────────────────────────

  Future<int> _pullAll() async {
    var after = await _meta.getInt(MetaKeys.syncPullAfter) ?? 0;
    var total = 0;
    while (true) {
      final page = await _api.pull(after);
      await _checkAccount(page.account);
      await _apply(page.rows, page.next);
      total += page.rows.length;
      after = page.next;
      if (!page.more) return total;
    }
  }

  /// Writes cloud rows and the new pull position in one transaction. The
  /// `sync_applying` flag keeps the triggers from queueing them again.
  /// Foreign keys are off meanwhile: a child can arrive before its parent
  /// (the parent was edited later), and the cloud data was valid on the
  /// phone that sent it.
  Future<void> _apply(List<SyncRow> rows, int next) async {
    if (rows.isEmpty) {
      await _meta.setInt(MetaKeys.syncPullAfter, next);
      return;
    }
    final changed = <String>{};
    await _db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await _db.transaction(() async {
        await _db.customStatement(
          'INSERT OR REPLACE INTO app_meta (meta_key, meta_value) '
          "VALUES ('$syncApplyingKey', '1')",
        );
        for (final row in rows) {
          final table = syncTablesByName[row.table];
          if (table == null) continue; // from a newer app version
          if (await _hasPending(row.table, row.id)) continue;
          if (row.deleted || row.data == null) {
            final deleted = await _db.customUpdate(
              'DELETE FROM ${row.table} WHERE id = ?',
              variables: [Variable.withString(row.id)],
            );
            if (deleted == 0) continue;
          } else {
            // Most pulled rows are this phone's own changes coming back;
            // rewriting them would only wake the screens and the backup.
            if (await _sameAsLocal(table, row.data!)) continue;
            if (!await _resolveClashes(table, row, changed)) continue;
            await _upsert(table, row.data!);
          }
          changed.add(row.table);
        }
        await _db.customStatement(
            "DELETE FROM app_meta WHERE meta_key = '$syncApplyingKey'");
        await _db.customStatement(
          'INSERT OR REPLACE INTO app_meta (meta_key, meta_value) '
          'VALUES (?, ?)',
          [MetaKeys.syncPullAfter, '$next'],
        );
      });
    } finally {
      await _db.customStatement('PRAGMA foreign_keys = ON');
    }
    if (changed.isNotEmpty) {
      _db.notifyUpdates({for (final t in changed) TableUpdate(t)});
    }
  }

  Future<bool> _hasPending(String table, String id) async {
    final row = await _db.customSelect(
      'SELECT 1 FROM sync_outbox WHERE tbl = ? AND row_id = ? LIMIT 1',
      variables: [Variable.withString(table), Variable.withString(id)],
    ).getSingleOrNull();
    return row != null;
  }

  /// Last change of a local row: its queued change, else its own column.
  Future<int> _localChangedAt(SyncTable table, String id) async {
    final row = await _db.customSelect(
      'SELECT MAX(COALESCE((SELECT MAX(changed_at) FROM sync_outbox '
      'WHERE tbl = ? AND row_id = ?), 0), COALESCE(${table.changedColumn}, 0)) '
      'AS at FROM ${table.name} WHERE id = ?',
      variables: [
        Variable.withString(table.name),
        Variable.withString(id),
        Variable.withString(id),
      ],
    ).getSingleOrNull();
    return row?.read<int>('at') ?? 0;
  }

  Future<void> _queue(String table, String id) => _db.customStatement(
        'INSERT INTO sync_outbox (tbl, row_id, changed_at) '
        'VALUES (?, ?, $nowMsSql)',
        [table, id],
      );

  /// Handles local rows with another id but the same unique key as [row]
  /// (see [ClashRule]). Every local change made here is queued, so the
  /// cloud ends up the same. False when the local row wins and [row] must
  /// not be written.
  Future<bool> _resolveClashes(
    SyncTable table,
    SyncRow row,
    Set<String> changed,
  ) async {
    final data = row.data!;
    for (final key in table.uniqueKeys) {
      final values = [for (final column in key) data[column]];
      if (values.any((v) => v == null)) continue;
      final clashes = await _db.customSelect(
        'SELECT id FROM ${table.name} WHERE '
        '${key.map((c) => '$c = ?').join(' AND ')} AND id != ?',
        variables: [
          for (final v in values) Variable<Object>(_sqlValue(v)!),
          Variable.withString(row.id),
        ],
      ).get();
      for (final clash in clashes) {
        final local = clash.read<String>('id');
        switch (table.clashRule) {
          case ClashRule.merge:
            for (final ref in table.references) {
              await _db.customStatement(
                'INSERT INTO sync_outbox (tbl, row_id, changed_at) '
                'SELECT ?, id, $nowMsSql FROM ${ref.table} '
                'WHERE ${ref.column} = ?',
                [ref.table, local],
              );
              await _db.customStatement(
                'UPDATE ${ref.table} SET ${ref.column} = ? '
                'WHERE ${ref.column} = ?',
                [row.id, local],
              );
              changed.add(ref.table);
            }
            await _deleteLocal(table.name, local);
          case ClashRule.newest:
            if (await _localChangedAt(table, local) > row.at) {
              // The local row is newer: the cloud row is deleted instead.
              await _queue(table.name, row.id);
              return false;
            }
            await _deleteLocal(table.name, local);
          case ClashRule.renumber:
            await _db.customStatement(
              "UPDATE ${table.name} SET number = number || '-' || "
              'substr(id, 1, 4) WHERE id = ?',
              [local],
            );
            await _queue(table.name, local);
        }
      }
    }
    return true;
  }

  Future<void> _deleteLocal(String table, String id) async {
    await _db.customStatement('DELETE FROM $table WHERE id = ?', [id]);
    await _queue(table, id);
  }

  final _columns = <String, Set<String>>{};

  Future<Set<String>> _knownColumns(String table) async =>
      _columns[table] ??= {
        for (final c
            in await _db.customSelect('PRAGMA table_info($table)').get())
          c.read<String>('name'),
      };

  Future<bool> _sameAsLocal(SyncTable table, Map<String, dynamic> data) async {
    final local = await _db.customSelect(
      'SELECT * FROM ${table.name} WHERE id = ?',
      variables: [Variable.withString('${data['id']}')],
    ).getSingleOrNull();
    if (local == null) return false;
    final known = await _knownColumns(table.name);
    for (final entry in data.entries) {
      if (!known.contains(entry.key)) continue;
      if (local.data[entry.key] != _sqlValue(entry.value)) return false;
    }
    return true;
  }

  /// Insert or update by id. Only columns this app version has are written,
  /// so rows from an older or newer app version still apply.
  Future<void> _upsert(SyncTable table, Map<String, dynamic> data) async {
    final known = await _knownColumns(table.name);
    final columns = [
      for (final c in data.keys)
        if (known.contains(c)) c,
    ];
    final updates = [
      for (final c in columns)
        if (c != 'id') '$c = excluded.$c',
    ];
    await _db.customStatement(
      'INSERT INTO ${table.name} (${columns.join(', ')}) '
      'VALUES (${List.filled(columns.length, '?').join(', ')}) '
      'ON CONFLICT (id) DO '
      '${updates.isEmpty ? 'NOTHING' : 'UPDATE SET ${updates.join(', ')}'}',
      [for (final c in columns) _sqlValue(data[c])],
    );
  }

  static Object? _sqlValue(Object? value) => switch (value) {
        bool b => b ? 1 : 0,
        _ => value,
      };
}

class _Outgoing {
  const _Outgoing(this.row, this.lastSeq);

  final SyncRow row;
  final int lastSeq;
}

class _AccountChanged implements Exception {
  const _AccountChanged();
}
