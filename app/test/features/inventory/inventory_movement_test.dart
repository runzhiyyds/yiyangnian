import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/features/inventory/inventory_models.dart';
import 'package:yiyangnian/features/inventory/inventory_movement.dart';
import 'package:yiyangnian/features/storage/storage_model.dart';

void main() {
  group('InventoryMovementLedger', () {
    test(
      'orders legacy same-day inbound before outbound and calculates balance',
      () {
        final date = DateTime(2026, 10, 10);
        final movements = InventoryMovementLedger.forItem(
          smallItemId: 7,
          purchases: [
            InventoryPurchaseRecordModel(
              id: 1,
              code: 'JH00001',
              purchaseDate: date,
              storageBigItems: const ['护理'],
              storageSmallItemIds: const [7],
              quantities: const [10],
            ),
          ],
          supplementaryIn: const [],
          outbound: [
            InventoryConsumptionRecordModel(
              id: 2,
              consumptionDate: date,
              storageSmallItemId: 7,
              quantity: 3,
            ),
          ],
        );

        expect(movements, hasLength(2));
        expect(movements.first.title, '手工出库');
        expect(movements.first.balanceAfter, 7);
        expect(movements.last.title, '进货入库');
        expect(movements.last.balanceAfter, 10);
      },
    );

    test('keeps original movement and adds a reverse movement when voided', () {
      final movements = InventoryMovementLedger.forItem(
        smallItemId: 7,
        purchases: [
          InventoryPurchaseRecordModel(
            id: 1,
            code: 'JH00001',
            purchaseDate: DateTime(2026, 10, 1),
            storageBigItems: const ['护理'],
            storageSmallItemIds: const [7],
            quantities: const [10],
            occurredAt: DateTime(2026, 10, 1, 9),
            voidedAt: DateTime(2026, 10, 3, 14),
            voidReason: '重复录入',
          ),
        ],
        supplementaryIn: const [],
        outbound: const [],
      );

      expect(movements, hasLength(2));
      expect(movements.first.title, '撤销进货入库');
      expect(movements.first.delta, -10);
      expect(movements.first.balanceAfter, 0);
      expect(movements.last.balanceAfter, 10);
      expect(movements.last.originalIsVoided, isTrue);
    });

    test('voiding outbound creates a positive reverse movement', () {
      final movements = InventoryMovementLedger.forItem(
        smallItemId: 7,
        purchases: [
          InventoryPurchaseRecordModel(
            id: 1,
            code: 'JH00001',
            purchaseDate: DateTime(2026, 10, 1),
            storageBigItems: const ['护理'],
            storageSmallItemIds: const [7],
            quantities: const [10],
          ),
        ],
        supplementaryIn: const [],
        outbound: [
          InventoryConsumptionRecordModel(
            id: 2,
            consumptionDate: DateTime(2026, 10, 2),
            storageSmallItemId: 7,
            quantity: 4,
            voidedAt: DateTime(2026, 10, 3, 10),
            voidReason: '客户取消',
          ),
        ],
      );

      expect(movements.first.title, '撤销手工出库');
      expect(movements.first.delta, 4);
      expect(movements.first.balanceAfter, 10);
    });

    test('exposes the customer storage linked to automatic outbound', () {
      final date = DateTime(2026, 10, 11);
      final storage = StorageRecordModel(
        id: 23,
        code: 'CZ00023',
        customerName: '王女士',
        storageBigItems: const ['颐养年'],
        storageSmallItemIds: const [7],
        amount: 980,
        totalCount: 10,
        storageDate: date,
      );
      final movements = InventoryMovementLedger.forItem(
        smallItemId: 7,
        purchases: const [],
        supplementaryIn: const [],
        outbound: [
          InventoryConsumptionRecordModel(
            id: 9,
            consumptionDate: date,
            storageSmallItemId: 7,
            quantity: 1,
            remark: '自动出库 · 王女士',
            sourceStorageRecordId: storage.id,
          ),
        ],
        sourceStorages: {storage.id: storage},
      );

      expect(movements.single.title, '储值自动出库');
      expect(movements.single.isAutomaticOutbound, isTrue);
      expect(movements.single.sourceStorageRecordId, storage.id);
      expect(movements.single.sourceStorageCode, 'CZ00023');
      expect(movements.single.sourceCustomerName, '王女士');
    });

    test(
      'recognizes legacy automatic outbound after its source was deleted',
      () {
        final movements = InventoryMovementLedger.forItem(
          smallItemId: 7,
          purchases: const [],
          supplementaryIn: const [],
          outbound: [
            InventoryConsumptionRecordModel(
              id: 10,
              consumptionDate: DateTime(2026, 10, 11),
              storageSmallItemId: 7,
              quantity: 1,
              remark: '自动出库 · 已删除客户',
            ),
          ],
        );

        expect(movements.single.title, '储值自动出库');
        expect(movements.single.isAutomaticOutbound, isTrue);
        expect(movements.single.sourceStorageRecordId, isNull);
      },
    );
  });
}
