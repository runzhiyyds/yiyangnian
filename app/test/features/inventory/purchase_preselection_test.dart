import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yiyangnian/core/app_providers.dart';
import 'package:yiyangnian/core/data_cache.dart';
import 'package:yiyangnian/features/inventory/inventory_purchase_edit_screen.dart';
import 'package:yiyangnian/features/storage_options/storage_big_item_repository.dart';
import 'package:yiyangnian/features/storage_options/storage_small_item_repository.dart';

void main() {
  testWidgets('新建商品尚未出现在列表时，进货仍预选正确商品', (tester) async {
    late SupabaseClient client;
    await tester.runAsync(() async {
      client = SupabaseClient(
        'https://test.supabase.co',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path.endsWith('/storage_big_item_options')
                  ? [
                      {'id': 1, 'name': '旧大项'},
                    ]
                  : <dynamic>[],
            ),
            200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: buildAppProviders(DataCache(), client, enablePush: false),
        child: MaterialApp(
          home: InventoryPurchaseEditScreen(
            initialSmallItemOption: StorageSmallItemOption(
              id: 55,
              name: '刚创建的小项',
              storageBigItemId: 9,
            ),
            initialBigItemOption: StorageBigItemOption(id: 9, name: '新大项'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final product = find.text('商品 1：刚创建的小项');
    await tester.scrollUntilVisible(
      product,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(product, findsOneWidget);
    expect(find.text('新大项 → 刚创建的小项 · 1 件'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(client.dispose);
  });
}
