import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/core/data_cache.dart';

void main() {
  test(
    'consuming/expiring read snapshots does not invalidate pending business loads',
    () {
      final cache = DataCache();
      cache.set('snapshot', 1);
      cache.set('expired', 2, ttl: const Duration(seconds: -1));
      final revision = cache.revision;
      expect(cache.take<int>('snapshot'), 1);
      expect(cache.get<int>('snapshot'), null);
      expect(cache.get<int>('expired'), null);
      expect(cache.revision, revision);
      cache.remove('business');
      expect(cache.revision, greaterThan(revision));
    },
  );
  group('DataCache', () {
    test('get/set/remove', () {
      final cache = DataCache();
      expect(cache.get<String>('a'), isNull);
      cache.set('a', 'value');
      expect(cache.get<String>('a'), 'value');
      cache.remove('a');
      expect(cache.get<String>('a'), isNull);
    });

    test('get with wrong type returns null', () {
      final cache = DataCache();
      cache.set('a', 42);
      expect(cache.get<String>('a'), isNull);
      expect(cache.get<int>('a'), 42);
    });

    test('clear removes all', () {
      final cache = DataCache();
      cache.set('a', 1);
      cache.set('b', 2);
      cache.clear();
      expect(cache.get<int>('a'), isNull);
      expect(cache.get<int>('b'), isNull);
    });

    test('removeByPrefix', () {
      final cache = DataCache();
      cache.set('storage_1', 1);
      cache.set('storage_2', 2);
      cache.set('storage_list', 3);
      cache.set('other', 4);
      cache.removeByPrefix('storage_');
      expect(cache.get<int>('storage_1'), isNull);
      expect(cache.get<int>('storage_2'), isNull);
      expect(cache.get<int>('storage_list'), isNull);
      expect(cache.get<int>('other'), 4);
    });

    test('maxSize evicts oldest', () {
      final cache = DataCache(maxSize: 2);
      cache.set('a', 1);
      cache.set('b', 2);
      expect(cache.get<int>('a'), 1);
      cache.set('c', 3);
      expect(cache.get<int>('a'), isNull);
      expect(cache.get<int>('b'), 2);
      expect(cache.get<int>('c'), 3);
    });
  });
}
