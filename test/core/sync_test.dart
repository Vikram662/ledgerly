import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/db/database.dart';
import 'package:thekedaar/core/db/enums.dart';
import 'package:thekedaar/core/sync/sync_api.dart';
import 'package:thekedaar/core/sync/sync_engine.dart';
import 'package:thekedaar/core/sync/sync_schema.dart';

/// The worker's `sync_rows` table in memory: one row per (table, id), the
/// newer `at` wins, every write bumps `seq` (cloudflare-subscription
/// `syncPush` / `syncPull`).
class FakeCloud {
  final rows = <String, SyncRow>{};
  var _seq = 0;

  List<SyncRow> live(String table) => [
        for (final r in rows.values)
          if (r.table == table && !r.deleted) r,
      ];
}

class FakeSyncApi implements SyncApi {
  FakeSyncApi(this.cloud, {this.account = 'account-1'});

  final FakeCloud cloud;
  final String account;
  var pushes = 0;

  @override
  Future<bool> get ready async => true;

  @override
  Future<String> push(List<SyncRow> rows) async {
    pushes++;
    for (final sent in rows) {
      // Same JSON round trip as the real server.
      final row = SyncRow.fromJson(
          jsonDecode(jsonEncode(sent.toJson())) as Map<String, dynamic>);
      final key = '${row.table}/${row.id}';
      final old = cloud.rows[key];
      final winner = old == null || row.at >= old.at ? row : old;
      cloud.rows[key] = SyncRow(
        table: winner.table,
        id: winner.id,
        at: old == null || row.at > old.at ? row.at : old.at,
        data: winner.data,
        deleted: winner.deleted,
        seq: ++cloud._seq,
      );
    }
    return account;
  }

  @override
  Future<SyncPage> pull(int after) async {
    // Small pages so paging is exercised.
    final rows = cloud.rows.values.where((r) => r.seq! > after).toList()
      ..sort((a, b) => a.seq!.compareTo(b.seq!));
    final page = rows.take(3).toList();
    return SyncPage(
      account: account,
      rows: [
        for (final r in page)
          SyncRow.fromJson(
              jsonDecode(jsonEncode({...r.toJson(), 'seq': r.seq}))
                  as Map<String, dynamic>),
      ],
      next: page.isEmpty ? after : page.last.seq!,
      more: rows.length > page.length,
    );
  }
}

Future<int> outboxCount(AppDatabase db) async => (await db
        .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
        .getSingle())
    .read<int>('n');

void main() {
  late FakeCloud cloud;
  late AppDatabase phoneA;
  late AppDatabase phoneB;

  setUp(() {
    cloud = FakeCloud();
    phoneA = AppDatabase(NativeDatabase.memory());
    phoneB = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await phoneA.close();
    await phoneB.close();
  });

  SyncEngine engine(AppDatabase db) =>
      SyncEngine(db: db, api: FakeSyncApi(cloud));

  Future<void> sync(AppDatabase db) async {
    final result = await engine(db).run();
    expect(result.outcome, SyncOutcome.synced, reason: result.error);
  }

  Future<void> addRole(AppDatabase db, String id) =>
      db.into(db.roles).insert(RolesCompanion.insert(
            id: id,
            name: 'Mistri',
            seedKey: const Value('role:mistri'),
          ));

  Future<void> addWorker(AppDatabase db, String id, String roleId) =>
      db.into(db.workers).insert(WorkersCompanion.insert(
            id: id,
            name: 'Raju',
            joinDate: '2026-10-01',
            roleId: Value(roleId),
          ));

  test('local changes are queued by triggers and sent once', () async {
    await addRole(phoneA, 'role-a');
    await addWorker(phoneA, 'worker-1', 'role-a');
    expect(await outboxCount(phoneA), 2);

    await sync(phoneA);
    expect(await outboxCount(phoneA), 0);
    expect(cloud.live('workers').single.data!['name'], 'Raju');

    // Pulling its own rows back does not queue them again.
    await sync(phoneA);
    expect(await outboxCount(phoneA), 0);
  });

  test('a new phone gets all data back without duplicate masters', () async {
    await addRole(phoneA, 'role-a');
    await addWorker(phoneA, 'worker-1', 'role-a');
    await sync(phoneA);

    // Fresh install: seeded its own copy of the same role (other id) and
    // added a worker on it before the first sync.
    await addRole(phoneB, 'role-b');
    await addWorker(phoneB, 'worker-2', 'role-b');
    await sync(phoneB);

    final roles = await phoneB.select(phoneB.roles).get();
    expect(roles.map((r) => r.id), ['role-a']);
    final workers = await phoneB.select(phoneB.workers).get();
    expect(workers.map((w) => w.id).toSet(), {'worker-1', 'worker-2'});
    expect(workers.every((w) => w.roleId == 'role-a'), isTrue);

    // The cloud also ends with one role, and worker-2 points at it.
    expect(cloud.live('roles').map((r) => r.id), ['role-a']);
    expect(
      cloud.live('workers').firstWhere((r) => r.id == 'worker-2').data!['role_id'],
      'role-a',
    );
  });

  test('restoring a backup sends everything again without duplicates',
      () async {
    await addRole(phoneA, 'role-a');
    await addWorker(phoneA, 'worker-1', 'role-a');
    await sync(phoneA);
    final before = cloud.rows.length;

    // What RestoreService.afterRestore does on the restored database.
    await phoneA.transaction(() => queueAllForSync(phoneA));
    expect(await outboxCount(phoneA), 2);
    await sync(phoneA);

    expect(cloud.rows.length, before);
    expect(cloud.live('workers'), hasLength(1));
    expect(await phoneA.select(phoneA.workers).get(), hasLength(1));
  });

  test('after a restore, a row changed later in the cloud keeps the newer '
      'version', () async {
    await phoneA.into(phoneA.clients).insert(ClientsCompanion.insert(
          id: 'client-1',
          name: 'Old name',
          updatedAt: const Value(1000),
        ));
    await sync(phoneA);
    // Edited later on another phone.
    final newer = DateTime.now().millisecondsSinceEpoch + 60000;
    await FakeSyncApi(cloud).push([
      SyncRow(
        table: 'clients',
        id: 'client-1',
        at: newer,
        data: {
          ...cloud.rows['clients/client-1']!.data!,
          'name': 'New name',
        },
      ),
    ]);

    // Restore the old backup: its row is older than the cloud's.
    await phoneA.transaction(() => queueAllForSync(phoneA));
    await sync(phoneA);

    final client = await phoneA.select(phoneA.clients).getSingle();
    expect(client.name, 'New name');
    expect(cloud.live('clients').single.data!['name'], 'New name');
  });

  test('deletes reach the other phone', () async {
    await phoneA.into(phoneA.clients).insert(
        ClientsCompanion.insert(id: 'client-1', name: 'Sharma ji'));
    await sync(phoneA);
    await sync(phoneB);
    expect(await phoneB.select(phoneB.clients).get(), hasLength(1));

    await (phoneA.delete(phoneA.clients)
          ..where((c) => c.id.equals('client-1')))
        .go();
    await sync(phoneA);
    await sync(phoneB);

    expect(await phoneB.select(phoneB.clients).get(), isEmpty);
    expect(cloud.rows['clients/client-1']!.deleted, isTrue);
  });

  test('a change made offline is kept when the cloud has an older one',
      () async {
    await phoneA.into(phoneA.clients).insert(
        ClientsCompanion.insert(id: 'client-1', name: 'First'));
    await sync(phoneA);
    await sync(phoneB);

    // Phone B edits while offline; phone A's older edit is in the cloud.
    await (phoneA.update(phoneA.clients)
          ..where((c) => c.id.equals('client-1')))
        .write(const ClientsCompanion(name: Value('From A')));
    await sync(phoneA);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await (phoneB.update(phoneB.clients)
          ..where((c) => c.id.equals('client-1')))
        .write(const ClientsCompanion(name: Value('From B')));

    await sync(phoneB);
    await sync(phoneA);

    expect((await phoneB.select(phoneB.clients).getSingle()).name, 'From B');
    expect((await phoneA.select(phoneA.clients).getSingle()).name, 'From B');
  });

  test('same worker and day marked on two phones keeps one attendance',
      () async {
    await addRole(phoneA, 'role-a');
    await addWorker(phoneA, 'worker-1', 'role-a');
    await sync(phoneA);
    await sync(phoneB);

    await phoneA.into(phoneA.attendances).insert(AttendancesCompanion.insert(
          id: 'att-a',
          workerId: 'worker-1',
          date: '2026-10-20',
          status: AttendanceStatus.present,
        ));
    await sync(phoneA);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await phoneB.into(phoneB.attendances).insert(AttendancesCompanion.insert(
          id: 'att-b',
          workerId: 'worker-1',
          date: '2026-10-20',
          status: AttendanceStatus.half,
        ));
    await sync(phoneB);
    await sync(phoneA);

    for (final db in [phoneA, phoneB]) {
      final rows = await db.select(db.attendances).get();
      expect(rows.map((r) => r.status), [AttendanceStatus.half]);
    }
    expect(cloud.live('attendances').map((r) => r.id), ['att-b']);
  });
}
