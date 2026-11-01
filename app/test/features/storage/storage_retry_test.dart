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
  testWidgets('一次新建可保留多笔独立储值草稿', (tester) async {
    late SupabaseClient client;
    await tester.runAsync(() async {
      client = SupabaseClient(
        'https://test.supabase.co',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          final rows = path.endsWith('/storage_big_item_options')
              ? [
                  {'id': 1, 'name': '大项甲'},
                ]
              : path.endsWith('/storage_small_item_options')
              ? [
                  {'id': 2, 'name': '小项甲', 'storage_big_item_id': 1},
                ]
              : path.endsWith('/inventory_supplementary_in_records')
              ? [
                  {
                    'id': 1,
                    'supplement_date': '2026-10-01',
                    'storage_small_item_id': 2,
                    'quantity': 10,
                  },
                ]
              : [];
          return http.Response(
            jsonEncode(rows),
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
    await tester.tap(find.text('大项甲'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加储值小项'));
    await tester.tap(find.text('添加储值小项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小项甲'));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    final amount = find.widgetWithText(TextFormField, '储值金额（元）');
    await tester.scrollUntilVisible(
      amount,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(amount, '888');
    await tester.scrollUntilVisible(
      find.text('再加一笔储值'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('再加一笔储值'));
    await tester.pumpAndSettle();
    expect(find.text('保存全部（2笔）'), findsOneWidget);
    await tester.tap(find.text('第 1 笔'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      amount,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<TextFormField>(amount).controller!.text, '888');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(client.dispose);
  });

  testWidgets(
    'option failure offers retry and preserves entered storage form',
    (tester) async {
      var fail = true;
      var writes = 0;
      late SupabaseClient client;
      await tester.runAsync(() async {
        client = SupabaseClient(
          'https://test.supabase.co',
          'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            if (request.method != 'GET') writes++;
            if (fail &&
                request.url.path.endsWith('/storage_small_item_options')) {
              return http.Response(
                jsonEncode({'code': 'gateway_timeout', 'message': 'timeout'}),
                504,
                request: request,
              );
            }
            return http.Response('[]', 200, request: request);
          }),
        );
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: buildAppProviders(DataCache(), client, enablePush: false),
          child: const MaterialApp(
            home: StorageEditScreen(customerName: '演示-回归'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('重新加载'), findsOneWidget);
      expect(find.text('演示-回归 · 新增储值'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
            .onPressed,
        isNull,
      );
      fail = false;
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      expect(find.text('重新加载'), findsNothing);
      expect(find.text('演示-回归 · 新增储值'), findsOneWidget);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(client.dispose);
    },
  );
}
