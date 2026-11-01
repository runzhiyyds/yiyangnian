import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/features/inventory/inventory_models.dart';

void main() {
  group('InventoryPurchaseRecordModel item alignment', () {
    test('keeps every product in an aligned multi-product purchase', () {
      final record = InventoryPurchaseRecordModel.fromJson({
        'id': 7,
        'code': 'JH00007',
        'purchase_date': '2026-08-15',
        'storage_big_items': ['藏红方', '颐养年'],
        'storage_small_item_ids': [11, 22],
        'quantities': [3, 5],
        'total_amount': 1280,
      });

      expect(record.hasAlignedItems, isTrue);
      expect(record.itemCount, 2);
      expect(record.toJson()['storage_big_items'], ['藏红方', '颐养年']);
      expect(record.toJson()['storage_small_item_ids'], [11, 22]);
      expect(record.toJson()['quantities'], [3, 5]);
    });

    test('marks a legacy mismatched purchase as unsafe to edit', () {
      final record = InventoryPurchaseRecordModel.fromJson({
        'id': 8,
        'code': 'JH00008',
        'purchase_date': '2026-08-15',
        'storage_big_items': ['藏红方', '颐养年'],
        'storage_small_item_ids': [11],
        'quantities': [3, 5],
      });

      expect(record.hasAlignedItems, isFalse);
      expect(record.itemCount, 0);
    });
  });
}
