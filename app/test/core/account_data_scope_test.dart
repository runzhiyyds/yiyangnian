import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/core/account_data_scope.dart';
import 'package:yiyangnian/core/demo_credentials.dart';
import 'package:yiyangnian/features/inventory/inventory_models.dart';
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
  });
}
