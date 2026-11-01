import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yiyangnian/app.dart';
import 'package:yiyangnian/core/app_providers.dart';
import 'package:yiyangnian/core/config.dart';
import 'package:yiyangnian/core/data_cache.dart';
import 'package:yiyangnian/core/network/supabase_http_client.dart';
import 'package:yiyangnian/core/supabase_auth_options.dart';
import 'package:yiyangnian/features/storage_options/storage_small_item_repository.dart';

/// Inject only a read failure; successful requests use the real mobile gateway.
class ReadFaultClient extends http.BaseClient {
  final inner = SupabaseHttpClient();
  bool failSmallItems = true;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (failSmallItems &&
        request.method == 'GET' &&
        request.url.path.endsWith('/storage_small_item_options')) {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({'message': '连接服务超时，请稍后重试。', 'code': 'gateway_timeout'}),
          ),
        ),
        504,
        request: request,
        reasonPhrase: 'Gateway Timeout',
        headers: {'content-type': 'application/json'},
      );
    }
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), true, reason: 'Inventory state was not reached');
}

Future<T> pumpFuture<T>(WidgetTester tester, Future<T> future) async {
  bool done = false;
  T? value;
  Object? error;
  StackTrace? stack;
  future.then(
    (result) {
      value = result;
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
  return value as T;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'inventory read failure retries on mobile and preserves existing content',
    (tester) async {
      await Supabase.initialize(
        url: Config.supabaseUrl,
        anonKey: Config.supabaseAnonKey,
        httpClient: SupabaseHttpClient(),
        authOptions: supabaseAuthOptions(Config.supabaseUrl),
      );
      final original = Supabase.instance.client;
      expect(original.auth.currentSession, isNotNull);
      // Let REST refresh an expired persisted session, without substituting an account.
      await pumpFuture(tester, StorageSmallItemRepository(original).getAll());
      final session = original.auth.currentSession!;
      final fault = ReadFaultClient();
      final client = SupabaseClient(
        Config.supabaseUrl,
        Config.supabaseAnonKey,
        httpClient: fault,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      // Memory-only copy; never sign it out, which would revoke the owner's session.
      await client.auth.setInitialSession(jsonEncode(session.toJson()));
      try {
        await tester.pumpWidget(
          MultiProvider(
            providers: buildAppProviders(DataCache(), client),
            child: const YiyangnianApp(),
          ),
        );
        await waitFor(
          tester,
          () => find.textContaining('服务响应超时').evaluate().isNotEmpty,
        );
        expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
        debugPrint('INVENTORY_FIRST_FAILURE_RETRY_VISIBLE');
        fault.failSmallItems = false;
        await tester.tap(find.text('重试'));
        await waitFor(
          tester,
          () =>
              find.text('刷新库存').evaluate().isNotEmpty &&
              find.byType(ListTile).evaluate().isNotEmpty,
        );
        final firstTitle =
            tester.widget<ListTile>(find.byType(ListTile).first).title! as Text;
        final itemName = firstTitle.data!;
        expect(find.text('重试'), findsNothing);
        debugPrint('INVENTORY_REAL_MOBILE_READ_RECOVERED');
        fault.failSmallItems = true;
        await tester.tap(find.text('刷新库存'));
        await waitFor(
          tester,
          () => find.byType(MaterialBanner).evaluate().isNotEmpty,
        );
        expect(find.text(itemName), findsOneWidget);
        expect(find.textContaining('上次成功加载的库存'), findsOneWidget);
        fault.failSmallItems = false;
        await tester.tap(find.text('重试'));
        await waitFor(
          tester,
          () =>
              find.byType(MaterialBanner).evaluate().isEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        expect(find.text(itemName), findsOneWidget);
        expect(original.auth.currentUser?.id, session.user.id);
        expect(tester.takeException(), isNull);
        debugPrint(
          'INVENTORY_REFRESH_FAILURE_RETRY_RECOVERED_ACCOUNT_PRESERVED',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpFuture(tester, client.dispose());
      }
    },
  );
}
