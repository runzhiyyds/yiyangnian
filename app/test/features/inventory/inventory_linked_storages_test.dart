import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/features/inventory/widgets/inventory_linked_storages.dart';
import 'package:yiyangnian/features/storage/storage_model.dart';

void main() {
  testWidgets('shows linked storage details and opens the selected record', (
    tester,
  ) async {
    StorageRecordModel? opened;
    final storage = StorageRecordModel(
      id: 23,
      code: 'CZ00023',
      customerName: '王女士',
      storageBigItems: const ['颐养年'],
      storageSmallItemIds: const [7],
      amount: 980,
      totalCount: 10,
      storageDate: DateTime(2026, 10, 11),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryLinkedStorages(
            storages: [storage],
            onTap: (value) => opened = value,
          ),
        ),
      ),
    );

    expect(find.text('关联储值'), findsOneWidget);
    expect(find.text('1条'), findsOneWidget);
    expect(find.text('王女士'), findsOneWidget);
    expect(find.textContaining('CZ00023'), findsOneWidget);
    expect(find.textContaining('¥980'), findsOneWidget);

    await tester.tap(find.text('王女士'));
    expect(opened?.id, 23);
  });

  testWidgets('makes an empty linked-storage state explicit', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryLinkedStorages(storages: const [], onTap: (_) {}),
        ),
      ),
    );

    expect(find.text('0条'), findsOneWidget);
    expect(find.text('暂无关联储值'), findsOneWidget);
  });

  testWidgets(
    'compact entry exposes the query capability without a flat list',
    (tester) async {
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryLinkedStoragesEntry(
              count: 12,
              onTap: () => opened = true,
            ),
          ),
        ),
      );

      expect(find.text('关联储值'), findsOneWidget);
      expect(find.text('共 12 条，点击查询'), findsOneWidget);
      expect(find.text('王女士'), findsNothing);

      await tester.tap(find.text('关联储值'));
      expect(opened, isTrue);
    },
  );
}
