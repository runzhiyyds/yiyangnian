import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yiyangnian/core/data_cache.dart';
import 'package:yiyangnian/core/data_refresh.dart';
import 'package:yiyangnian/features/auth/auth_service.dart';
import 'package:yiyangnian/features/consumption/consumption_repository.dart';
import 'package:yiyangnian/features/inventory/inventory_options_screen.dart';
import 'package:yiyangnian/features/inventory/inventory_purchase_repository.dart';
import 'package:yiyangnian/features/inventory/inventory_supp_in_repository.dart';
import 'package:yiyangnian/features/inventory/inventory_consumption_repository.dart';
import 'package:yiyangnian/features/storage/storage_repository.dart';
import 'package:yiyangnian/features/storage_options/storage_big_item_repository.dart';
import 'package:yiyangnian/features/storage_options/storage_small_item_repository.dart';

class TestAuth extends AuthService {
  User? account;
  @override
  User? get user => account;
  void setAccount(String id) {
    account = User(
      id: id,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-10-13T00:00:00Z',
    );
    notifyListeners();
  }
}

class Fixture {
  bool fail = false;
  String name = '商品A';
  Completer<void>? hold;
  int smallReads = 0;
  final auth = TestAuth();
  final refresh = DataRefreshNotifier(DataCache());
  late final client = SupabaseClient(
    'https://test.supabase.co',
    'test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      final isSmall = request.url.path.endsWith('/storage_small_item_options');
      final itemName = name;
      if (isSmall) {
        smallReads++;
        await hold?.future;
        if (fail) {
          return http.Response(
            jsonEncode({'message': '连接服务超时，请稍后重试。', 'code': 'gateway_timeout'}),
            504,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
      }
      return http.Response(
        jsonEncode(
          isSmall
              ? [
                  {'id': 1, 'name': itemName, 'storage_big_item_id': null},
                ]
              : [],
        ),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );
  Widget get widget => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<DataRefreshNotifier>.value(value: refresh),
      Provider.value(value: StorageBigItemRepository(client)),
      Provider.value(value: StorageSmallItemRepository(client)),
      Provider.value(value: StorageRepository(client)),
      Provider.value(value: ConsumptionRepository(client)),
      Provider.value(value: InventoryPurchaseRepository(client)),
      Provider.value(value: InventorySuppInRepository(client)),
      Provider.value(value: InventoryConsumptionRepository(client)),
    ],
    child: const MaterialApp(home: InventoryOptionsScreen()),
  );
  Future<void> dispose() async {
    await client.dispose();
    auth.dispose();
    refresh.dispose();
  }
}

void main() {
  testWidgets('first failure can retry without duplicate reads', (
    tester,
  ) async {
    final f = Fixture()..fail = true;
    await tester.runAsync(() async {
      f.client;
    });
    addTearDown(() => tester.runAsync(f.dispose));
    await tester.pumpWidget(f.widget);
    await tester.pumpAndSettle();
    expect(find.textContaining('服务响应超时'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
    f.fail = false;
    await tester.tap(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('商品A'), findsOneWidget);
    expect(find.textContaining('服务响应超时'), findsNothing);
    expect(f.smallReads, 2);
  });
  testWidgets('failed refresh keeps inventory and search; retry recovers', (
    tester,
  ) async {
    final f = Fixture();
    await tester.runAsync(() async {
      f.client;
    });
    addTearDown(() => tester.runAsync(f.dispose));
    await tester.pumpWidget(f.widget);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '商品');
    f.fail = true;
    await tester.tap(find.text('刷新库存'));
    await tester.pumpAndSettle();
    expect(find.text('商品A'), findsOneWidget);
    expect(find.textContaining('上次成功加载的库存'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '商品',
    );
    f.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('商品A'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '商品',
    );
  });
  testWidgets('invalidation during refresh queues one new read', (
    tester,
  ) async {
    final f = Fixture();
    await tester.runAsync(() async {
      f.client;
    });
    addTearDown(() => tester.runAsync(f.dispose));
    await tester.pumpWidget(f.widget);
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    f.hold = gate;
    await tester.tap(find.text('刷新库存'));
    await tester.pump();
    expect(find.text('商品A'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    f.refresh.invalidateInventory();
    f.refresh.invalidateInventory();
    f.hold = null;
    gate.complete();
    await tester.pumpAndSettle();
    expect(f.smallReads, 3);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets('old account response cannot populate the new account', (
    tester,
  ) async {
    final f = Fixture();
    await tester.runAsync(() async {
      f.client;
    });
    addTearDown(() => tester.runAsync(f.dispose));
    f.auth.setAccount('account-a');
    final gate = Completer<void>();
    f.hold = gate;
    await tester.pumpWidget(f.widget);
    await tester.pump();
    f.auth.setAccount('account-b');
    f.name = '商品B';
    f.hold = null;
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('商品A'), findsNothing);
    expect(find.text('商品B'), findsOneWidget);
    expect(f.smallReads, 2);
  });
}
