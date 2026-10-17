import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/db/database.dart';
import 'package:thekedaar/core/db/enums.dart';
import 'package:thekedaar/core/seed/seed_service.dart';

Future<String> _readSeed(String name) =>
    File('assets/seed/$name.json').readAsString();

Future<Map<String, int>> _counts(AppDatabase db) async => {
      'units': (await db.select(db.units).get()).length,
      'roles': (await db.select(db.roles).get()).length,
      'categories': (await db.select(db.expenseCategories).get()).length,
      'items': (await db.select(db.itemMasters).get()).length,
      'templates': (await db.select(db.billTemplates).get()).length,
    };

void main() {
  late AppDatabase db;
  late SeedService seed;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    seed = SeedService(db, _readSeed);
  });

  tearDown(() => db.close());

  test('every trade seeds, and re-seeding adds nothing', () async {
    await seed.applyTrades(Trade.values);
    final first = await _counts(db);
    expect(first['units'], 19);
    expect(first['roles']!, greaterThan(20));
    expect(first['items']!, greaterThan(100));

    await seed.applyTrades(Trade.values);
    expect(await _counts(db), first);
  });

  test('one trade seeds only common data plus that trade', () async {
    await seed.applyTrades({Trade.painting});
    final roles = (await db.select(db.roles).get()).map((r) => r.name);
    expect(roles, containsAll(['Helper', 'Mistri', 'Painter']));
    expect(roles, isNot(contains('Electrician')));
  });

  test('admin renames survive adding another trade (TR-05)', () async {
    await seed.applyTrades({Trade.electrical});
    await (db.update(db.roles)
          ..where((r) => r.seedKey.equals(roleSeedKey('Helper'))))
        .write(const RolesCompanion(name: Value('Head Helper')));

    await seed.applyTrades({Trade.electrical, Trade.plumbing});

    final names = (await db.select(db.roles).get()).map((r) => r.name);
    expect(names, contains('Head Helper'));
    expect(names, isNot(contains('Helper')));
    expect(names, contains('Plumber'));
  });

  test('every template line points at a seeded item', () async {
    await seed.applyTrades(Trade.values);
    final itemKeys = {
      for (final item in await db.select(db.itemMasters).get()) item.seedKey,
    };
    for (final template in await db.select(db.billTemplates).get()) {
      final lines = jsonDecode(template.linesJson) as List;
      for (final line in lines) {
        expect(
          itemKeys,
          contains((line as Map)['itemSeedKey']),
          reason: 'template "${template.name}" line ${line['name']}',
        );
      }
    }
  });

  test('default terms are stored', () async {
    await seed.applyTrades({Trade.other});
    final terms = await (db.select(db.appMeta)
          ..where((m) => m.metaKey.equals('default_terms')))
        .getSingleOrNull();
    expect(terms, isNotNull);
    expect(terms!.metaValue, contains('advance'));
  });

  test('a personal user gets home categories, no contractor defaults',
      () async {
    await seed.applyFor(UserType.personal, const {});
    final counts = await _counts(db);
    expect(counts['units'], 19);
    expect(counts['roles'], 0);
    expect(counts['items'], 0);
    final categories =
        (await db.select(db.expenseCategories).get()).map((c) => c.name);
    expect(categories, containsAll(['Rent', 'Grocery / Ration', 'Other']));
    expect(categories, isNot(contains('Machine Rent')));
  });

  test('a shop gets staff roles, shop categories and shop terms', () async {
    await seed.applyFor(UserType.shop, const {});
    final roles = (await db.select(db.roles).get()).map((r) => r.name);
    expect(roles, containsAll(['Salesman', 'Cashier']));
    expect(roles, isNot(contains('Mistri')));
    final categories =
        (await db.select(db.expenseCategories).get()).map((c) => c.name);
    expect(categories, contains('Stock Purchase'));
    final items = (await db.select(db.itemMasters).get()).map((i) => i.name);
    expect(items, contains('Delivery charge'));
    expect(items, isNot(contains('Light point')));
    final terms = await (db.select(db.appMeta)
          ..where((m) => m.metaKey.equals('default_terms')))
        .getSingle();
    expect(terms.metaValue, contains('Goods once sold'));
  });

  test('a contractor seeds exactly like applyTrades', () async {
    await seed.applyFor(UserType.contractor, {Trade.painting});
    final roles = (await db.select(db.roles).get()).map((r) => r.name);
    expect(roles, containsAll(['Helper', 'Painter']));
  });

  test('an item name shared by trades has the same unit and kind', () {
    final seen = <String, String>{};
    for (final name in ['common', for (final t in Trade.values) t.seedFile]) {
      final pack = jsonDecode(File('assets/seed/$name.json').readAsStringSync())
          as Map<String, dynamic>;
      for (final raw in pack['items'] as List? ?? const []) {
        final item = raw as Map<String, dynamic>;
        final key = itemSeedKey(item['name'] as String);
        final signature = '${item['unit']}/${item['kind']}';
        final previous = seen.putIfAbsent(key, () => signature);
        expect(previous, signature, reason: '$key in $name.json');
      }
    }
  });
}
