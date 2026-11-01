import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yiyangnian/core/app_providers.dart';
import 'package:yiyangnian/core/data_cache.dart';
import 'package:yiyangnian/features/storage/storage_edit_screen.dart';

void main() {
  testWidgets('新建小项直接进货，取消后保留表单且可再次进货', (tester) async {
    late SupabaseClient client;
    final created = {'id': 55, 'name': '新商品', 'storage_big_item_id': 9};
    await tester.runAsync(() async {
      client = SupabaseClient(
        'https://test.supabase.co',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          Object result = [];
          if (request.url.path.endsWith('/storage_big_item_options')) {
            result = [
              {'id': 9, 'name': '系列甲'},
            ];
          }
          if (request.url.path.endsWith('/storage_small_item_options') &&
              request.method == 'POST') {
            result = created;
          }
          // 故意使列表保持旧快照，不包含刚创建的商品。
          return http.Response(
            jsonEncode(result),
            200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: buildAppProviders(DataCache(), client, enablePush: false),
        child: const MaterialApp(home: StorageEditScreen(customerName: '客户甲')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('系列甲'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加储值小项'));
    await tester.tap(find.text('添加储值小项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建储值小项'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '新商品',
    );
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('现在进货'));
    await tester.pumpAndSettle();
    final product = find.text('商品 1：新商品');
    await tester.scrollUntilVisible(
      product,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('系列甲 → 新商品 · 1 件'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('客户甲 · 新增储值'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('去进货'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('去进货'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      product,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(product, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(client.dispose);
  });
}
