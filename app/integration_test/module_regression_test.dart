import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yiyangnian/app.dart';
import 'package:yiyangnian/core/app_providers.dart';
import 'package:yiyangnian/core/config.dart';
import 'package:yiyangnian/core/data_cache.dart';
import 'package:yiyangnian/core/demo_credentials.dart';
import 'package:yiyangnian/core/network/supabase_http_client.dart';
import 'package:yiyangnian/core/supabase_auth_options.dart';
import 'package:yiyangnian/features/customer/customer_model.dart';
import 'package:yiyangnian/features/customer/customer_repository.dart';
import 'package:yiyangnian/features/storage/storage_model.dart';
import 'package:yiyangnian/features/storage/storage_repository.dart';
import 'package:yiyangnian/features/storage_options/storage_small_item_repository.dart';
import 'package:yiyangnian/features/storage_options/storage_big_item_repository.dart';
import 'package:yiyangnian/features/consumption/consumption_model.dart';
import 'package:yiyangnian/features/consumption/consumption_repository.dart';
import 'package:yiyangnian/features/inventory/inventory_models.dart';
import 'package:yiyangnian/features/inventory/inventory_purchase_repository.dart';
import 'package:yiyangnian/features/inventory/inventory_supp_in_repository.dart';
import 'package:yiyangnian/features/inventory/inventory_consumption_repository.dart';
import 'package:yiyangnian/features/tree/tree_data_provider.dart';

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  final limit = DateTime.now().add(const Duration(seconds: 60));
  while (!ready() && DateTime.now().isBefore(limit)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), true, reason: 'Module did not reach the expected state');
}

Future<T> pumping<T>(WidgetTester tester, Future<T> future) async {
  T? result;
  Object? error;
  StackTrace? stack;
  var done = false;
  future.then(
    (v) {
      result = v;
      done = true;
    },
    onError: (Object e, StackTrace st) {
      error = e;
      stack = st;
      done = true;
    },
  );
  await waitFor(tester, () => done);
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return result as T;
}

SupabaseClient demoClient({http.Client? transport}) => SupabaseClient(
  Config.supabaseUrl,
  Config.supabaseAnonKey,
  httpClient: transport ?? SupabaseHttpClient(),
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);
Future<void> login(SupabaseClient client) async {
  await client.auth.signInWithPassword(
    email: DemoCredentials.email,
    password: DemoCredentials.password,
  );
}

class MobileTransport extends http.BaseClient {
  final inner = SupabaseHttpClient();
  int reads = 0;
  bool blockLogout = false;
  bool failReads = false;
  bool failConsumptionReads = false;
  final held = Completer<http.StreamedResponse>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (blockLogout && request.url.path.endsWith('/logout')) return held.future;
    if (request.method == 'GET') {
      reads++;
      if (failReads ||
          (failConsumptionReads &&
              request.url.path.endsWith('/consumption_records')))
        return Future.value(
          http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'code': 'gateway_timeout',
                  'message': 'temporary test failure',
                }),
              ),
            ),
            504,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        );
    }
    return inner.send(request);
  }

  @override
  void close() {
    if (!held.isCompleted)
      held.complete(http.StreamedResponse(const Stream.empty(), 204));
    inner.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'demo modules, preload, offline logout and next login preserve phone owner session',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final original = prefs.getString(originalSessionKey);
      final transport = MobileTransport();
      final client = demoClient(transport: transport);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('颐养年回归测试'))),
      );
      try {
        await pumping(tester, login(client));
        expect(client.auth.currentUser?.email, DemoCredentials.email);
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
        await waitFor(
          tester,
          () =>
              find.text('刷新库存').evaluate().isNotEmpty &&
              find.byType(ListTile).evaluate().isNotEmpty,
        );
        debugPrint('REGRESSION_INVENTORY_HOME_READY');
        // Wait for the same background preload used by the shipped application.
        final context = tester.element(find.byType(NavigationBar));
        final tree = context.read<TreeDataProvider>();
        await waitFor(tester, () => tree.hasLoaded && !tree.loading);
        final before = transport.reads;
        final watch = Stopwatch()..start();
        await tester.tap(
          find
              .descendant(
                of: find.byType(NavigationBar),
                matching: find.text('客户信息一览'),
              )
              .first,
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(tree.error, isNull);
        expect(tree.customers, isNotEmpty);
        debugPrint(
          'REGRESSION_PRELOADED_CUSTOMERS elapsedMs=${watch.elapsedMilliseconds} newReads=${transport.reads - before}',
        );
        await tester.tap(
          find
              .descendant(
                of: find.byType(NavigationBar),
                matching: find.text('店铺数据分析'),
              )
              .first,
        );
        await waitFor(
          tester,
          () =>
              find.text('周期汇总').evaluate().isNotEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty,
        );
        expect(find.text('筛选条件'), findsOneWidget);
        debugPrint('REGRESSION_ANALYTICS_AND_CALENDAR_READY');
        final amountBefore = tester
            .widgetList<Text>(find.textContaining(RegExp(r'^¥')))
            .map((w) => w.data)
            .toList();
        transport.failConsumptionReads = true;
        await pumping(
          tester,
          tester
              .widget<RefreshIndicator>(find.byType(RefreshIndicator))
              .onRefresh(),
        );
        await waitFor(
          tester,
          () => find.textContaining('周期汇总加载失败').evaluate().isNotEmpty,
        );
        expect(
          tester
              .widgetList<Text>(find.textContaining(RegExp(r'^¥')))
              .map((w) => w.data)
              .toList(),
          amountBefore,
        );
        expect(find.textContaining('日历加载失败'), findsOneWidget);
        transport.failConsumptionReads = false;
        await tester.ensureVisible(find.text('重试周期汇总'));
        await tester.tap(find.text('重试周期汇总'));
        await waitFor(
          tester,
          () => find.textContaining('周期汇总加载失败').evaluate().isEmpty,
        );
        await tester.ensureVisible(find.text('重试日历'));
        await tester.tap(find.text('重试日历'));
        await waitFor(
          tester,
          () => find.textContaining('日历加载失败').evaluate().isEmpty,
        );
        debugPrint(
          'REGRESSION_ANALYTICS_PARTIAL_FAILURE_RETRIES_KEEP_AMOUNTS_PASS',
        );

        await tester.tap(
          find
              .descendant(
                of: find.byType(NavigationBar),
                matching: find.text('设置'),
              )
              .first,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('切换账号'), findsNothing);
        expect(find.text('当前版本'), findsOneWidget);
        transport.blockLogout = true;
        await tester.tap(find.text('退出登录'));
        await tester.pumpAndSettle();
        final logout = Stopwatch()..start();
        await tester.tap(find.text('确定'));
        await waitFor(
          tester,
          () => find.text('一键填入体验账号').evaluate().isNotEmpty,
        );
        expect(client.auth.currentSession, isNull);
        debugPrint(
          'REGRESSION_OFFLINE_LOGOUT elapsedMs=${logout.elapsedMilliseconds}',
        );
        await tester.tap(find.text('一键填入体验账号'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, '登录'));
        await waitFor(
          tester,
          () => find.byType(NavigationBar).evaluate().isNotEmpty,
        );
        expect(client.auth.currentUser?.email, DemoCredentials.email);
        expect(prefs.getString(originalSessionKey), original);
        expect(tester.takeException(), isNull);
        debugPrint('REGRESSION_NEXT_LOGIN_OWNER_PERSISTED_SESSION_PRESERVED');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await pumping(tester, client.dispose());
      }
    },
  );

  testWidgets('demo customer storage consumption CRUD and cascades', (
    tester,
  ) async {
    final client = demoClient();
    final name = '演示-回归-${DateTime.now().millisecondsSinceEpoch}';
    var currentName = name;
    final customer = CustomerRepository(client),
        storage = StorageRepository(client),
        consumption = ConsumptionRepository(client);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('储值消费回归测试'))),
    );
    try {
      await pumping(tester, login(client));
      expect(client.auth.currentUser?.email, DemoCredentials.email);
      final options = await pumping(
        tester,
        StorageSmallItemRepository(client).getAll(),
      );
      final categories = await pumping(
        tester,
        StorageBigItemRepository(client).getAll(),
      );
      final option = options.firstWhere(
        (o) => o.name.startsWith('演示-') && o.storageBigItemId != null,
      );
      final category = categories.firstWhere(
        (o) => o.id == option.storageBigItemId,
      );
      await pumping(tester, customer.create(CustomerModel(name: name)));
      final saved = await pumping(
        tester,
        storage.create(
          StorageRecordModel(
            id: 0,
            code: '',
            customerName: name,
            storageBigItems: [category.name],
            storageSmallItemIds: [option.id],
            amount: 1,
            totalCount: 3,
            storageDate: DateTime.now(),
            remark: '回归临时记录',
          ),
        ),
      );
      expect(
        (await pumping(tester, storage.getById(saved.id)))?.customerName,
        name,
      );
      final c = await pumping(
        tester,
        consumption.create(
          ConsumptionRecordModel(
            id: 0,
            code: '',
            consumptionDate: DateTime.now(),
            storageRecordId: saved.id,
            consumptionProjectIds: [option.id],
            remark: '回归临时消费',
          ),
        ),
      );
      expect(await pumping(tester, storage.getRemainingCount(saved.id)), 2);
      await pumping(
        tester,
        consumption.update(
          ConsumptionRecordModel(
            id: c.id,
            code: c.code,
            consumptionDate: c.consumptionDate,
            storageRecordId: saved.id,
            consumptionProjectIds: [option.id],
            remark: '回归修改消费',
          ),
        ),
      );
      expect(
        (await pumping(tester, consumption.getById(c.id)))?.remark,
        '回归修改消费',
      );
      await pumping(tester, consumption.delete(c.id));
      expect(await pumping(tester, storage.getRemainingCount(saved.id)), 3);
      final updated = await pumping(
        tester,
        storage.update(
          StorageRecordModel(
            id: saved.id,
            code: saved.code,
            customerName: name,
            storageBigItems: saved.storageBigItems,
            storageSmallItemIds: saved.storageSmallItemIds,
            amount: 2,
            totalCount: 3,
            storageDate: saved.storageDate,
            remark: '回归修改储值',
          ),
        ),
      );
      expect(updated.amount, 2);
      final copy = await pumping(
        tester,
        storage.create(
          StorageRecordModel(
            id: 0,
            code: '',
            customerName: name,
            storageBigItems: saved.storageBigItems,
            storageSmallItemIds: saved.storageSmallItemIds,
            amount: 1,
            totalCount: 1,
            storageDate: DateTime.now(),
          ),
        ),
      );
      expect(copy.code, isNot(saved.code));
      currentName = '$name-改';
      await pumping(
        tester,
        customer.update(name, CustomerModel(name: currentName)),
      );
      expect(
        (await pumping(tester, storage.getById(saved.id)))?.customerName,
        currentName,
      );
      await pumping(tester, storage.deleteCascade(copy.id));
      expect(await pumping(tester, storage.getById(copy.id)), null);
      debugPrint('REGRESSION_CUSTOMER_STORAGE_CONSUMPTION_CRUD_PASS');
    } catch (e) {
      if (e is PostgrestException)
        debugPrint(
          'REGRESSION_BACKEND_FAILURE code=${e.code} message=${e.message}',
        );
      rethrow;
    } finally {
      for (final fixtureName in {name, currentName}) {
        if (await pumping(tester, customer.getByName(fixtureName)) != null) {
          await pumping(tester, customer.deleteCascade(fixtureName));
        }
      }
      await pumping(tester, client.dispose());
    }
  });

  testWidgets(
    'demo inventory purchase supplementary in and outbound with audited cleanup',
    (tester) async {
      final client = demoClient();
      final marker = '演示-回归-${DateTime.now().millisecondsSinceEpoch}';
      final purchase = InventoryPurchaseRepository(client),
          supp = InventorySuppInRepository(client),
          outbound = InventoryConsumptionRepository(client);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('库存回归测试'))),
      );
      try {
        await pumping(tester, login(client));
        expect(client.auth.currentUser?.email, DemoCredentials.email);
        final options = await pumping(
          tester,
          StorageSmallItemRepository(client).getAll(),
        );
        final categories = await pumping(
          tester,
          StorageBigItemRepository(client).getAll(),
        );
        final option = options.firstWhere(
          (o) => o.name.startsWith('演示-') && o.storageBigItemId != null,
        );
        final category = categories.firstWhere(
          (o) => o.id == option.storageBigItemId,
        );
        final date = DateTime.now();
        final p = await pumping(
          tester,
          purchase.create(
            InventoryPurchaseRecordModel(
              id: 0,
              code: '',
              purchaseDate: date,
              storageBigItems: [category.name],
              storageSmallItemIds: [option.id],
              quantities: [2],
              remark: marker,
            ),
          ),
        );
        final changed = await pumping(
          tester,
          purchase.update(
            InventoryPurchaseRecordModel(
              id: p.id,
              code: p.code,
              purchaseDate: p.purchaseDate,
              occurredAt: p.occurredAt,
              storageBigItems: p.storageBigItems,
              storageSmallItemIds: p.storageSmallItemIds,
              quantities: [3],
              remark: marker,
            ),
          ),
        );
        expect(changed.quantities, [3]);
        final s = await pumping(
          tester,
          supp.create(
            InventorySuppInRecordModel(
              id: 0,
              supplementDate: date,
              storageSmallItemId: option.id,
              quantity: 1,
              remark: marker,
            ),
          ),
        );
        final o = await pumping(
          tester,
          outbound.create(
            InventoryConsumptionRecordModel(
              id: 0,
              consumptionDate: date,
              storageSmallItemId: option.id,
              quantity: 1,
              remark: marker,
            ),
          ),
        );
        expect((await pumping(tester, supp.getById(s.id)))?.quantity, 1);
        expect((await pumping(tester, outbound.getById(o.id)))?.quantity, 1);
        debugPrint('REGRESSION_INVENTORY_CRUD_PASS');
      } finally {
        // Exact fixture markers also cover a write whose response was lost.
        for (final table in [
          'inventory_consumption_records',
          'inventory_supplementary_in_records',
          'inventory_purchase_records',
        ]) {
          final rows = await pumping(
            tester,
            client.from(table).select('id,voided_at').eq('remark', marker),
          );
          for (final row in rows) {
            if (row['voided_at'] != null) continue;
            final id = row['id'] as int;
            if (table == 'inventory_consumption_records') {
              expect(
                (await pumping(
                  tester,
                  outbound.voidRecord(id, reason: '回归结束：$marker'),
                )).isVoided,
                true,
              );
            } else if (table == 'inventory_supplementary_in_records') {
              expect(
                (await pumping(
                  tester,
                  supp.voidRecord(id, reason: '回归结束：$marker'),
                )).isVoided,
                true,
              );
            } else {
              expect(
                (await pumping(
                  tester,
                  purchase.voidRecord(id, reason: '回归结束：$marker'),
                )).isVoided,
                true,
              );
            }
          }
        }
        await pumping(tester, client.dispose());
      }
    },
  );
}
