import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yiyangnian/core/app_providers.dart';
import 'package:yiyangnian/core/data_cache.dart';
import 'package:yiyangnian/features/customer/customer_detail_screen.dart';
import 'package:yiyangnian/features/customer/customer_edit_screen.dart';
import 'package:yiyangnian/features/storage/storage_detail_screen.dart';

Map<String, dynamic> store(int id, int amount, int total) => {
  'id': id,
  'code': 'CZ$id',
  'customer_name': '客户A',
  'storage_big_items': ['大项'],
  'storage_small_item_ids': [1],
  'amount': amount,
  'total_count': total,
  'storage_date': '2026-10-13',
};
Future<SupabaseClient> fixture(
  WidgetTester tester,
  List<String> queries, {
  Completer<void>? hold,
  String phone = '111',
}) async {
  late SupabaseClient client;
  await tester.runAsync(() async {
    client = SupabaseClient(
      'https://test.supabase.co',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        final table = r.url.path.split('/').last;
        queries.add(table);
        if (table == 'customers') await hold?.future;
        Object rows = switch (table) {
          'customers' => {'name': '客户A', 'phone': phone},
          'storage_records' =>
            r.url.queryParameters.containsKey('id')
                ? store(1, 10, 3)
                : [store(1, 10, 3), store(2, 20, 2)],
          'consumption_records' => [
            {
              'id': 1,
              'code': 'XF1',
              'storage_record_id': 1,
              'consumption_date': '2026-10-13',
              'consumption_project_ids': [1],
            },
          ],
          _ => [],
        };
        return http.Response(
          jsonEncode(rows),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  return client;
}

Widget screen(DataCache cache, SupabaseClient client, Widget child) =>
    MultiProvider(
      providers: buildAppProviders(cache, client, enablePush: false),
      child: MaterialApp(home: child),
    );
void main() {
  testWidgets(
    'customer detail batches consumers and preserves deposit and remaining definition',
    (tester) async {
      final queries = <String>[];
      final client = await fixture(tester, queries);
      await tester.pumpWidget(
        screen(
          DataCache(),
          client,
          const CustomerDetailScreen(customerName: '客户A'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('¥30.00'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(queries.where((q) => q == 'consumption_records').length, 1);
      expect(queries.length, 4);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(client.dispose);
    },
  );
  testWidgets(
    'storage detail reads each source once and keeps remaining count',
    (tester) async {
      final queries = <String>[];
      final client = await fixture(tester, queries);
      await tester.pumpWidget(
        screen(DataCache(), client, const StorageDetailScreen(storageId: 1)),
      );
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      expect(queries.where((q) => q == 'storage_records').length, 1);
      expect(queries.where((q) => q == 'consumption_records').length, 1);
      expect(queries.length, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(client.dispose);
    },
  );
  testWidgets(
    'a closed old customer editor cannot repopulate account-cleared cache',
    (tester) async {
      final cache = DataCache();
      final hold = Completer<void>();
      final client = await fixture(tester, [], hold: hold);
      await tester.pumpWidget(
        screen(cache, client, const CustomerEditScreen(customerName: '客户A')),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      cache.clear();
      hold.complete();
      await tester.pumpAndSettle();
      expect(cache.get<Object>('customer_客户A'), null);
      expect(tester.takeException(), isNull);
      await tester.runAsync(client.dispose);
    },
  );
}
