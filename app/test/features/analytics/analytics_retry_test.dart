import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yiyangnian/core/app_providers.dart';
import 'package:yiyangnian/core/data_cache.dart';
import 'package:yiyangnian/features/analytics/store_analytics_screen.dart';

void main() {
  testWidgets(
    'period and calendar failures retain last data with separate retries',
    (tester) async {
      var fail = false;
      late SupabaseClient client;
      await tester.runAsync(() async {
        client = SupabaseClient(
          'https://test.supabase.co',
          'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            final table = request.url.path.split('/').last;
            if (fail && table == 'consumption_records')
              return http.Response(
                jsonEncode({'code': 'gateway_timeout', 'message': 'timeout'}),
                504,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            final date = DateTime.now().toIso8601String().split('T').first;
            final rows = switch (table) {
              'customers' => [
                {'name': '客户A'},
              ],
              'storage_big_item_options' => [
                {'id': 1, 'name': '分类A'},
              ],
              'storage_small_item_options' => [
                {'id': 1, 'name': '商品A', 'storage_big_item_id': 1},
              ],
              'storage_records' => [
                {
                  'id': 1,
                  'code': 'CZ1',
                  'customer_name': '客户A',
                  'storage_big_items': ['分类A'],
                  'storage_small_item_ids': [1],
                  'amount': 10,
                  'total_count': 1,
                  'storage_date': date,
                },
              ],
              _ => [],
            };
            return http.Response(
              jsonEncode(rows),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: buildAppProviders(DataCache(), client, enablePush: false),
          child: const MaterialApp(home: Scaffold(body: StoreAnalyticsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('¥10.00'), findsOneWidget);
      fail = true;
      final refreshing = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      await refreshing;
      expect(find.text('¥10.00'), findsOneWidget);
      expect(find.textContaining('周期汇总加载失败'), findsOneWidget);
      // Calendar is farther down the lazy scroll view; bring its retry into view.
      await tester.ensureVisible(find.text('重试日历'));
      await tester.pump();
      expect(find.textContaining('日历加载失败'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('重试日历'));
      await tester.pumpAndSettle();
      expect(find.textContaining('日历加载失败'), findsNothing);
      await tester.ensureVisible(find.text('重试周期汇总'));
      await tester.tap(find.text('重试周期汇总'));
      await tester.pumpAndSettle();
      expect(find.textContaining('周期汇总加载失败'), findsNothing);
      expect(find.text('¥10.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(client.dispose);
    },
  );
}
