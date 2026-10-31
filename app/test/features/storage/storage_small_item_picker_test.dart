import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/features/storage/storage_small_item_picker.dart';
import 'package:yiyangnian/features/storage_options/storage_small_item_repository.dart';

void main() {
  testWidgets('零库存小项不可选且可原地去进货', (tester) async {
    var added = false;
    var restocked = false;
    final option = StorageSmallItemOption(
      id: 8,
      name: '肩颈',
      storageBigItemId: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StorageSmallItemPicker(
            options: [option],
            remainingStockBySmallItemId: const {8: 0},
            selectedIds: const [],
            onAdd: (_) => added = true,
            onRemove: (_) {},
            onCreateNew: (_) async => null,
            onRestock: (_) async => restocked = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('添加储值小项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('肩颈'));
    await tester.pump();
    expect(added, isFalse);
    expect(find.text('当前库存为 0，请先进货再选择'), findsOneWidget);

    await tester.tap(find.text('去进货'));
    await tester.pumpAndSettle();
    expect(restocked, isTrue);
    expect(added, isFalse);
  });
}
