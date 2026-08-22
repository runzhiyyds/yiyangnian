import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/core/account_data_scope.dart';
import 'package:yiyangnian/core/demo_credentials.dart';
import 'package:yiyangnian/features/consumption/consumption_model.dart';
import 'package:yiyangnian/features/inventory/inventory_models.dart';
import 'package:yiyangnian/features/storage/storage_model.dart';
import 'package:yiyangnian/features/storage_options/storage_small_item_repository.dart';

void main() {
  group('AccountDataScope inventory purchase ownership fallback', () {
    final demoPurchase = InventoryPurchaseRecordModel(
      id: 101,
      code: 'JH00101',
      purchaseDate: DateTime(2026, 8, 19),
      storageBigItems: const ['藏红方'],
      storageSmallItemIds: const [11],
      quantities: const [7],
    );
    final formalPurchase = InventoryPurchaseRecordModel(
      id: 102,
      code: 'JH00102',
      purchaseDate: DateTime(2026, 8, 19),
      storageBigItems: const ['藏红方'],
      storageSmallItemIds: const [22],
      quantities: const [5],
    );
    final options = [
      StorageSmallItemOption(id: 11, name: '演示-面部护理'),
      StorageSmallItemOption(id: 22, name: '面部护理'),
    ];

    test('keeps a newly generated JH code in the demo inventory scope', () {
      final scoped = AccountDataScope.scopeInventoryRaw(
        email: DemoCredentials.email,
        purchases: [demoPurchase, formalPurchase],
        suppIn: const [],
        consumptions: const [],
        smallOptions: options,
      );

      expect(scoped.purchases.map((record) => record.id), [101]);
      final balances = AccountDataScope.computeInventoryBalances(
        purchases: scoped.purchases,
        suppIn: scoped.suppIn,
        consumptions: scoped.consumptions,
        smallOptions: scoped.smallOptions,
      );
      expect(balances[11], 7);
    });

    test('does not leak the same demo purchase into a formal account', () {
      final scoped = AccountDataScope.scopeInventoryRaw(
        email: 'formal@example.com',
        purchases: [demoPurchase, formalPurchase],
        suppIn: const [],
        consumptions: const [],
        smallOptions: options,
      );

      expect(scoped.purchases.map((record) => record.id), [102]);
      expect(scoped.smallOptions.map((option) => option.id), [22]);
    });

    test('keeps a formal purchase even when the shared sequence uses JH90', () {
      final purchase = InventoryPurchaseRecordModel(
        id: 108,
        code: 'JH90020',
        purchaseDate: DateTime(2026, 8, 22),
        storageBigItems: const ['正式大项'],
        storageSmallItemIds: const [22],
        quantities: const [10],
      );

      final scoped = AccountDataScope.scopeInventoryRaw(
        email: 'formal@example.com',
        purchases: [purchase],
        suppIn: const [],
        consumptions: const [],
        smallOptions: options,
      );

      expect(scoped.purchases.map((record) => record.id), [108]);
      final balances = AccountDataScope.computeInventoryBalances(
        purchases: scoped.purchases,
        suppIn: scoped.suppIn,
        consumptions: scoped.consumptions,
        smallOptions: scoped.smallOptions,
      );
      expect(balances[22], 10);
    });

    test('still hides the JH90 formal purchase from the demo account', () {
      final purchase = InventoryPurchaseRecordModel(
        id: 108,
        code: 'JH90020',
        purchaseDate: DateTime(2026, 8, 22),
        storageBigItems: const ['正式大项'],
        storageSmallItemIds: const [22],
        quantities: const [10],
      );

      final scoped = AccountDataScope.scopeInventoryRaw(
        email: DemoCredentials.email,
        purchases: [demoPurchase, purchase],
        suppIn: const [],
        consumptions: const [],
        smallOptions: options,
      );

      expect(scoped.purchases.map((record) => record.id), [101]);
    });
  });

  group('AccountDataScope shared business-code sequences', () {
    final formalStorage = StorageRecordModel(
      id: 310,
      code: 'CZ90041',
      customerName: '正式客户',
      storageBigItems: const ['正式大项'],
      storageSmallItemIds: const [22],
      amount: 100,
      totalCount: 1,
      storageDate: DateTime(2026, 8, 22),
    );
    final demoStorage = StorageRecordModel(
      id: 311,
      code: 'CZ90042',
      customerName: '演示-客户',
      storageBigItems: const ['演示大项'],
      storageSmallItemIds: const [11],
      amount: 100,
      totalCount: 1,
      storageDate: DateTime(2026, 8, 22),
    );

    test('does not classify a formal storage by its CZ90 sequence number', () {
      expect(
        AccountDataScope.filterStorages('formal@example.com', [
          formalStorage,
          demoStorage,
        ]).map((record) => record.id),
        [310],
      );
      expect(
        AccountDataScope.filterStorages(DemoCredentials.email, [
          formalStorage,
          demoStorage,
        ]).map((record) => record.id),
        [311],
      );
    });

    test('uses the parent storage instead of an XF90 sequence number', () {
      final formalConsumption = ConsumptionRecordModel(
        id: 610,
        code: 'XF90006',
        consumptionDate: DateTime(2026, 8, 22),
        storageRecordId: formalStorage.id,
      );
      final demoConsumption = ConsumptionRecordModel(
        id: 611,
        code: 'XF90007',
        consumptionDate: DateTime(2026, 8, 22),
        storageRecordId: demoStorage.id,
      );
      final storageMap = {
        formalStorage.id: formalStorage,
        demoStorage.id: demoStorage,
      };

      expect(
        AccountDataScope.filterConsumptions('formal@example.com', [
          formalConsumption,
          demoConsumption,
        ], storageMap).map((record) => record.id),
        [610],
      );
      expect(
        AccountDataScope.filterConsumptions(DemoCredentials.email, [
          formalConsumption,
          demoConsumption,
        ], storageMap).map((record) => record.id),
        [611],
      );
    });
  });
}
