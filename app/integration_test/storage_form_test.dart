import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:yiyangnian/app.dart';
import 'package:yiyangnian/core/app_providers.dart';
import 'package:yiyangnian/core/data_cache.dart';
import 'package:yiyangnian/core/demo_mode.dart';
import 'package:yiyangnian/features/customer/customer_model.dart';
import 'package:yiyangnian/features/customer/customer_detail_screen.dart';
import 'package:yiyangnian/features/customer/customer_repository.dart';
import 'package:yiyangnian/features/storage/storage_edit_screen.dart';
import 'package:yiyangnian/features/storage/storage_repository.dart';
import 'package:yiyangnian/features/storage_options/storage_big_item_repository.dart';
import 'package:yiyangnian/features/storage_options/storage_small_item_repository.dart';
import 'package:yiyangnian/features/inventory/inventory_models.dart';
import 'package:yiyangnian/features/inventory/inventory_purchase_repository.dart';
import 'package:yiyangnian/features/inventory/inventory_supp_in_repository.dart';
import 'package:yiyangnian/features/inventory/inventory_consumption_repository.dart';
import 'module_regression_test.dart' show demoClient, login, pumping, waitFor;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real demo storage form computes formula and saves once with linked outbound',
    (tester) async {
      final client = demoClient();
      final name = '演示-表单回归-${DateTime.now().millisecondsSinceEpoch}';
      final customer = CustomerRepository(client);
      final storage = StorageRepository(client);
      final supp = InventorySuppInRepository(client);
      final outbound = InventoryConsumptionRepository(client);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('储值表单回归'))),
      );
      try {
        await pumping(tester, login(client));
        final options = await pumping(
          tester,
          StorageSmallItemRepository(client).getAll(),
        );
        final categories = await pumping(
          tester,
          StorageBigItemRepository(client).getAll(),
        );
        final item = options.firstWhere(
          (o) => o.name.startsWith('演示-') && o.storageBigItemId != null,
        );
        final category = categories.firstWhere(
          (o) => o.id == item.storageBigItemId,
        );
        final balances = DemoMode.computeInventoryBalances(
          purchases: await pumping(
            tester,
            InventoryPurchaseRepository(client).getAll(),
          ),
          suppIn: await pumping(tester, supp.getAll()),
          consumptions: await pumping(tester, outbound.getAll()),
          smallOptions: options,
        );
        final quantity = (2 - (balances[item.id] ?? 0))
            .clamp(1, 1000000)
            .toInt();
        await pumping(
          tester,
          supp.create(
            InventorySuppInRecordModel(
              id: 0,
              supplementDate: DateTime.now(),
              storageSmallItemId: item.id,
              quantity: quantity,
              remark: name,
            ),
          ),
        );
        await pumping(tester, customer.create(CustomerModel(name: name)));
        await tester.pumpWidget(
          MultiProvider(
            providers: buildAppProviders(
              DataCache(),
              client,
              enablePush: false,
            ),
            child: const YiyangnianApp(),
          ),
        );
        await waitFor(tester, () => find.text('刷新库存').evaluate().isNotEmpty);
        final context = tester.element(find.byType(NavigationBar));
        unawaited(
          GoRouter.of(
            context,
          ).push<void>('/storage/new', extra: {'customer': name}),
        );
        await waitFor(
          tester,
          () =>
              find
                  .widgetWithText(ChoiceChip, category.name)
                  .evaluate()
                  .isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        await tester.tap(find.widgetWithText(ChoiceChip, category.name));
        await tester.pump();
        await tester.ensureVisible(find.text('添加储值小项'));
        await tester.tap(find.text('添加储值小项'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(item.name));
        await tester.pump();
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        Finder field(String label) => find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label,
        );
        await tester.ensureVisible(field('储值金额（元）'));
        await tester.enterText(field('储值金额（元）'), '2*0.5=');
        expect(
          tester.widget<TextField>(field('储值金额（元）')).controller?.text,
          '1',
        );
        await tester.ensureVisible(field('总储值次数'));
        await tester.enterText(field('总储值次数'), '2');
        await tester.ensureVisible(field('备注'));
        await tester.enterText(field('备注'), name);
        await tester.tap(find.widgetWithText(TextButton, '保存'));
        // The second touch occurs before the first validation read completes.
        await tester.tap(find.widgetWithText(TextButton, '保存'));
        await waitFor(
          tester,
          () => find.byType(StorageEditScreen).evaluate().isEmpty,
        );
        final saved = await pumping(tester, storage.getByCustomer(name));
        expect(saved.length, 1);
        expect(saved.single.amount, 1);
        expect(saved.single.totalCount, 2);
        final linked = await pumping(
          tester,
          client
              .from('inventory_consumption_records')
              .select()
              .eq('source_storage_record_id', saved.single.id),
        );
        expect(linked.length, 1);
        expect(linked.single['quantity'], 1);
        expect(linked.single['storage_small_item_id'], item.id);
        expect(tester.takeException(), isNull);
        debugPrint('REGRESSION_REAL_STORAGE_FORM_AND_AUTO_OUTBOUND_PASS');
        unawaited(
          GoRouter.of(context).push<void>('/customer/detail', extra: name),
        );
        await waitFor(
          tester,
          () => find.text('累计储值').evaluate().isNotEmpty,
        );
        expect(find.text('¥1.00'), findsAtLeastNWidgets(1));
        GoRouter.of(tester.element(find.byType(CustomerDetailScreen))).pop();
        await waitFor(
          tester,
          () => find.byType(CustomerDetailScreen).evaluate().isEmpty,
        );
        unawaited(
          GoRouter.of(context).push<void>('/storage/${saved.single.id}'),
        );
        await waitFor(
          tester,
          () => find.textContaining('剩余次数').evaluate().isNotEmpty,
        );
        expect(find.text('2'), findsAtLeastNWidgets(1));
        expect(tester.takeException(), isNull);
        debugPrint('REGRESSION_CUSTOMER_AND_STORAGE_DETAILS_REAL_MOBILE_PASS');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        // Detach active outbound FK before voiding audit rows; only exact fixtures.
        if (await pumping(tester, customer.getByName(name)) != null)
          await pumping(tester, customer.deleteCascade(name));
        final outs = await pumping(
          tester,
          client
              .from('inventory_consumption_records')
              .select('id,voided_at')
              .eq('remark', '自动出库 · $name'),
        );
        for (final row in outs) {
          if (row['voided_at'] == null)
            await pumping(
              tester,
              outbound.voidRecord(row['id'] as int, reason: '表单回归结束：$name'),
            );
        }
        final ins = await pumping(
          tester,
          client
              .from('inventory_supplementary_in_records')
              .select('id,voided_at')
              .eq('remark', name),
        );
        for (final row in ins) {
          if (row['voided_at'] == null)
            await pumping(
              tester,
              supp.voidRecord(row['id'] as int, reason: '表单回归结束：$name'),
            );
        }
        await pumping(tester, client.dispose());
      }
    },
  );
}
