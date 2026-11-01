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
import 'package:yiyangnian/features/customer/customer_repository.dart';
import 'package:yiyangnian/features/storage/storage_repository.dart';
import 'package:yiyangnian/features/consumption/consumption_repository.dart';
import 'package:yiyangnian/features/storage_options/storage_small_item_repository.dart';
import 'package:yiyangnian/features/tree/tree_data_provider.dart';
import 'package:yiyangnian/features/tree/tree_screen.dart';

class Account extends AuthService {
  User? value;
  @override
  User? get user => value;
  void set(String id) {
    value = User(
      id: id,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-10-13T00:00:00Z',
    );
  }
}

void main() {
  testWidgets(
    'reset blocks a late old account response; refresh failure keeps visible customers',
    (tester) async {
      final auth = Account()..set('A');
      final cache = DataCache();
      final tree = TreeDataProvider();
      final refresh = DataRefreshNotifier(cache);
      var name = '客户A';
      var fail = false;
      Completer<void>? hold;
      var reads = 0;
      late SupabaseClient client;
      await tester.runAsync(() async {
        client = SupabaseClient(
          'https://test.supabase.co',
          'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            final customer = request.url.path.endsWith('/customers');
            final snapshot = name;
            if (customer) {
              reads++;
              await hold?.future;
            }
            if (customer && fail)
              return http.Response(
                jsonEncode({'code': 'gateway_timeout', 'message': 'timeout'}),
                504,
                request: request,
              );
            return http.Response(
              jsonEncode(
                customer
                    ? [
                        {'name': snapshot},
                      ]
                    : [],
              ),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
      });
      late BuildContext context;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            Provider.value(value: cache),
            ChangeNotifierProvider.value(value: tree),
            ChangeNotifierProvider.value(value: refresh),
            Provider.value(value: CustomerRepository(client)),
            Provider.value(value: StorageRepository(client)),
            Provider.value(value: ConsumptionRepository(client)),
            Provider.value(value: StorageSmallItemRepository(client)),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) {
                context = ctx;
                return const TreeScreen();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('客户A'), findsOneWidget);
      hold = Completer<void>();
      final old = tree.load(context, forceRefresh: true);
      await tester.pump();
      expect(find.text('客户A'), findsOneWidget);
      auth.set('B');
      tree.reset();
      cache.clear();
      name = '客户B';
      final release = hold;
      hold = null;
      final next = tree.load(context);
      await tester.pumpAndSettle();
      await next;
      release.complete();
      await tester.pumpAndSettle();
      await old;
      expect(tree.customers.single.name, '客户B');
      expect(find.text('客户A'), findsNothing);
      fail = true;
      refresh.notifyDataChanged();
      await tester.pumpAndSettle();
      expect(find.text('客户B'), findsOneWidget);
      expect(find.textContaining('刷新失败'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
      expect(reads, greaterThanOrEqualTo(5));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(client.dispose);
      auth.dispose();
      tree.dispose();
      refresh.dispose();
    },
  );
}
