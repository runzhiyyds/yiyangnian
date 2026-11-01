import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/core/repository_read_cache.dart';
import 'package:yiyangnian/core/data_cache.dart';
import 'package:yiyangnian/core/data_refresh.dart';

void main() {
  test(
    'shares concurrent reads, copies results, expires and separates query keys',
    () async {
      var now = DateTime(2026, 10, 13);
      var reads = 0;
      final cache = RepositoryReadCache(() => 'A', clock: () => now);
      final pending = Completer<List<int>>();
      final first = cache.read('today', () {
        reads++;
        return pending.future;
      });
      final second = cache.read('today', () {
        reads++;
        return Future.value([99]);
      });
      pending.complete([1]);
      (await first).clear();
      expect(await second, [1]);
      expect(await cache.read('today', () async => [99]), [1]);
      expect(reads, 1);
      expect(await cache.read('tomorrow', () async => [2]), [2]);
      now = now.add(const Duration(seconds: 31));
      expect(await cache.read('today', () async => [3]), [3]);
    },
  );
  test(
    'invalidation and account changes cannot resurrect stale responses',
    () async {
      var owner = 'A';
      final cache = RepositoryReadCache(() => owner);
      final old = Completer<List<int>>();
      final first = cache.read('items', () => old.future);
      cache.clear();
      expect(await cache.read('items', () async => [2]), [2]);
      old.complete([1]);
      await first;
      expect(await cache.read('items', () async => [99]), [2]);
      owner = 'B';
      expect(await cache.read('items', () async => [3]), [3]);
      owner = 'A';
      expect(await cache.read('items', () async => [99]), [2]);
    },
  );
  test('errors are not cached and anonymous reads are never shared', () async {
    final cache = RepositoryReadCache(() => 'A');
    await expectLater(
      cache.read<int>('items', () async => throw StateError('offline')),
      throwsStateError,
    );
    expect(await cache.read('items', () async => [1]), [1]);
    final anonymous = RepositoryReadCache(() => null);
    expect(await anonymous.read('items', () async => [1]), [1]);
    expect(await anonymous.read('items', () async => [2]), [2]);
  });
  test(
    'one business change emits one refresh and invalidates reads/preloads',
    () async {
      final pages = DataCache();
      pages.set('analytics_preload_A_2026-10-13', 1);
      pages.set('tree_data_A', 1);
      final reads = RepositoryReadCache(() => 'A');
      await reads.read('items', () async => [1]);
      final refresh = DataRefreshNotifier(pages, reads: reads);
      var notifications = 0;
      refresh.addListener(() => notifications++);
      refresh.invalidateStorageConsumptionAndInventory();
      expect(notifications, 1);
      expect(pages.get<int>('tree_data_A'), null);
      expect(pages.get<int>('analytics_preload_A_2026-10-13'), null);
      expect(await reads.read('items', () async => [2]), [2]);
      pages.set('storage_detail_1', 'old customer name');
      pages.set('inventory_item_detail_1', 'old linked name');
      refresh.invalidateCustomerAndTree();
      expect(notifications, 2);
      expect(pages.get<Object>('storage_detail_1'), null);
      expect(pages.get<Object>('inventory_item_detail_1'), null);
      refresh.dispose();
    },
  );
}
