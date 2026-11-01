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
import 'package:yiyangnian/core/data_refresh.dart';
import 'package:yiyangnian/features/auth/auth_service.dart';
import 'package:yiyangnian/features/consumption/consumption_repository.dart';
import 'package:yiyangnian/features/storage/storage_list_screen.dart';
import 'package:yiyangnian/features/storage/storage_repository.dart';
import 'package:yiyangnian/features/storage_options/storage_small_item_repository.dart';

class _TestAuth extends AuthService {
  User? account;

  @override
  User? get user => account;

  void setAccount(String id) {
    account = User(
      id: id,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-10-19T00:00:00Z',
    );
    notifyListeners();
  }
}

void main() {
  testWidgets('储值列表批量读取消费次数，保持每单剩余次数正确', (tester) async {
    final paths = <String>[];
    var failCounts = false;
    late SupabaseClient client;
    await tester.runAsync(() async {
      client = SupabaseClient(
        'https://test.supabase.co',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (failCounts &&
              request.url.pathSegments.last == 'consumption_records') {
            return http.Response(
              jsonEncode({'code': 'gateway_timeout', 'message': 'timeout'}),
              504,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          final rows = switch (request.url.pathSegments.last) {
            'storage_records' => [
              for (var id = 1; id <= 3; id++)
                {
                  'id': id,
                  'code': 'CZ$id',
                  'customer_name': '客户$id',
                  'storage_big_items': <String>[],
                  'storage_small_item_ids': <int>[],
                  'amount': 100,
                  'total_count': 3,
                  'storage_date': '2026-10-19',
                },
            ],
            'consumption_records' => [
              {'id': 10, 'storage_record_id': 1},
              {'id': 11, 'storage_record_id': 1},
              {'id': 12, 'storage_record_id': 2},
            ],
            'storage_small_item_options' => <Map<String, Object?>>[],
            _ => throw StateError('Unexpected request: ${request.url.path}'),
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
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: buildAppProviders(DataCache(), client, enablePush: false),
        child: const MaterialApp(home: StorageListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(paths.length, 3);
    expect(
      paths.where((path) => path.endsWith('/consumption_records')).length,
      1,
    );
    expect(find.textContaining('剩余 1 次'), findsOneWidget);
    expect(find.textContaining('剩余 2 次'), findsOneWidget);
    expect(find.textContaining('剩余 3 次'), findsOneWidget);

    failCounts = true;
    tester
        .element(find.byType(StorageListScreen))
        .read<DataRefreshNotifier>()
        .invalidateStorage();
    await tester.pumpAndSettle();
    expect(find.textContaining('上次成功加载的储值记录'), findsOneWidget);
    expect(find.textContaining('剩余 1 次'), findsOneWidget);

    failCounts = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.textContaining('上次成功加载的储值记录'), findsNothing);
    expect(find.textContaining('剩余 1 次'), findsOneWidget);
  });

  test('超过单页的消费次数仍完整计数', () async {
    var pages = 0;
    final client = SupabaseClient(
      'https://test.supabase.co',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        pages++;
        final rows = pages == 1
            ? [
                for (var id = 1; id <= 500; id++)
                  {'id': id, 'storage_record_id': 7},
              ]
            : [
                {'id': 501, 'storage_record_id': 7},
              ];
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final counts = await ConsumptionRepository(
      client,
    ).getConsumedCountsByStorageIds([7]);
    expect(counts[7], 501);
    expect(pages, 2);
  });

  testWidgets('切换账号时旧请求不能回填储值列表', (tester) async {
    final firstRequest = Completer<void>();
    final auth = _TestAuth()..setAccount('account-a');
    final cache = DataCache();
    final refresh = DataRefreshNotifier(cache);
    var storageReads = 0;
    late SupabaseClient client;
    await tester.runAsync(() async {
      client = SupabaseClient(
        'https://test.supabase.co',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final table = request.url.pathSegments.last;
          if (table != 'storage_records') {
            return http.Response(
              '[]',
              200,
              request: request,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          storageReads++;
          if (storageReads == 1) await firstRequest.future;
          final id = storageReads;
          return http.Response(
            jsonEncode([
              {
                'id': id,
                'code': 'CZ$id',
                'customer_name': '客户$id',
                'storage_big_items': <String>[],
                'storage_small_item_ids': <int>[],
                'amount': 100,
                'total_count': 3,
                'storage_date': '2026-10-19',
              },
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
    });
    addTearDown(() async {
      await client.dispose();
      auth.dispose();
      refresh.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<DataCache>.value(value: cache),
          ChangeNotifierProvider<DataRefreshNotifier>.value(value: refresh),
          Provider.value(value: StorageRepository(client)),
          Provider.value(value: ConsumptionRepository(client)),
          Provider.value(value: StorageSmallItemRepository(client)),
        ],
        child: const MaterialApp(home: StorageListScreen()),
      ),
    );
    await tester.pump();
    auth.setAccount('account-b');
    firstRequest.complete();
    await tester.pumpAndSettle();
    expect(find.text('客户1'), findsNothing);
    expect(find.text('客户2'), findsOneWidget);
    expect(storageReads, 2);
  });
}
