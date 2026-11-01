import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yiyangnian/app.dart';
import 'package:yiyangnian/core/app_providers.dart';
import 'package:yiyangnian/core/config.dart';
import 'package:yiyangnian/core/data_cache.dart';
import 'package:yiyangnian/core/network/supabase_http_client.dart';
import 'package:yiyangnian/core/supabase_auth_options.dart';
import 'package:yiyangnian/features/auth/auth_service.dart';
import 'package:yiyangnian/features/auth/login_screen.dart';
import 'package:yiyangnian/features/home/main_shell.dart';
import 'package:yiyangnian/features/customer/customer_repository.dart';
import 'package:yiyangnian/features/storage/storage_repository.dart';
import 'package:yiyangnian/features/consumption/consumption_repository.dart';
import 'package:yiyangnian/features/inventory/inventory_purchase_repository.dart';
import 'package:yiyangnian/features/inventory/inventory_supp_in_repository.dart';
import 'package:yiyangnian/features/inventory/inventory_consumption_repository.dart';
import 'package:yiyangnian/main.dart' as app;

const email = String.fromEnvironment('NETWORK_TEST_EMAIL');
const password = String.fromEnvironment('NETWORK_TEST_PASSWORD');
const expectOldSession = bool.fromEnvironment('NETWORK_EXPECT_OLD_SESSION');

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 35));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    ready(),
    true,
    reason: 'Expected state was not reached before deadline',
  );
}

Future<T> driveFuture<T>(WidgetTester tester, Future<T> future) async {
  var complete = false;
  T? result;
  Object? error;
  StackTrace? stack;
  future.then(
    (value) {
      result = value;
      complete = true;
    },
    onError: (Object e, StackTrace st) {
      error = e;
      stack = st;
      complete = true;
    },
  );
  await waitFor(tester, () => complete);
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return result as T;
}

Future<void> readCoreTables(SupabaseClient client) async {
  // Use actual repository queries, sorting and DTO parsing instead of a shadow
  // schema in the test. These methods do not create, edit or void records.
  debugPrint("GATEWAY_READ_CUSTOMERS");
  await CustomerRepository(client).getAll();
  debugPrint("GATEWAY_READ_STORAGES");
  final storages = await StorageRepository(client).getAll();
  await ConsumptionRepository(
    client,
  ).getByStorageIds(storages.map((record) => record.id));
  debugPrint("GATEWAY_READ_INVENTORY");
  await InventoryPurchaseRepository(client).getAll();
  await InventorySuppInRepository(client).getAll();
  await InventoryConsumptionRepository(client).getAll();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('gateway restores the app account and opens core pages', (
    tester,
  ) async {
    expect(Uri.parse(Config.supabaseUrl).host, gatewayHost);
    final originalErrorBuilder = ErrorWidget.builder;
    final frameworkErrorHandler = FlutterError.onError;
    app.main();
    FlutterError.onError = frameworkErrorHandler;
    try {
      await waitFor(
        tester,
        () =>
            find.byType(MainShell).evaluate().isNotEmpty ||
            find.byType(LoginScreen).evaluate().isNotEmpty,
      );
      debugPrint("GATEWAY_APP_READY");
      final client = Supabase.instance.client;
      if (expectOldSession) {
        expect(client.auth.currentSession != null, true);
      }
      if (client.auth.currentSession != null) {
        // REST's SDK token provider refreshes an expired restored session first.
        // Calling auth.getUser directly before that refresh can send the old JWT.
        await driveFuture(tester, readCoreTables(client));
        final user = await driveFuture(tester, client.auth.getUser());
        expect(user.user?.id == client.auth.currentUser?.id, true);
        for (final label in ['客户信息一览', '店铺数据分析', '设置', '库存管理']) {
          await tester.tap(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text(label),
            ),
          );
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(MainShell), findsOneWidget);
          expect(find.textContaining('操作未完成'), findsNothing);
          expect(find.textContaining('暂时无法连接服务'), findsNothing);
        }
      }
      expect(tester.takeException(), isNull);
    } finally {
      ErrorWidget.builder = originalErrorBuilder;
    }
  });

  testWidgets(
    'password login and authenticated reads use the gateway',
    (tester) async {
      // Memory-only client avoids replacing the phone owner's stored session.
      final client = SupabaseClient(
        Config.supabaseUrl,
        Config.supabaseAnonKey,
        httpClient: SupabaseHttpClient(),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      try {
        await tester.pumpWidget(
          MultiProvider(
            providers: buildAppProviders(DataCache(maxSize: 200), client),
            child: const YiyangnianApp(),
          ),
        );
        await waitFor(
          tester,
          () => find.byType(LoginScreen).evaluate().isNotEmpty,
        );
        await tester.enterText(find.byType(TextFormField).at(0), email);
        await tester.enterText(find.byType(TextFormField).at(1), password);
        final login = find.widgetWithText(FilledButton, '登录');
        await tester.ensureVisible(login);
        final watch = Stopwatch()..start();
        await tester.tap(login);
        await waitFor(tester, () => client.auth.currentSession != null);
        watch.stop();
        debugPrint('YIYANGNIAN_GATEWAY_LOGIN_MS=${watch.elapsedMilliseconds}');
        await waitFor(
          tester,
          () => find.byType(MainShell).evaluate().isNotEmpty,
        );
        final context = tester.element(find.byType(MainShell));
        expect(context.read<AuthService>().isLoggedIn, true);
        await tester.runAsync(() async {
          await readCoreTables(client);
          final missing =
              '__gateway_validation_${DateTime.now().microsecondsSinceEpoch}__';
          final rows = await client
              .from('customers')
              .update({'name': missing})
              .eq('name', missing)
              .select('name');
          expect(rows, isEmpty);
          try {
            await client.rpc('gateway_validation_missing_function', params: {});
            fail('Missing RPC must return an upstream error');
          } on PostgrestException catch (error) {
            expect(error.code, 'PGRST202');
          }
          final userId = client.auth.currentUser!.id;
          final refreshed = await client.auth.refreshSession();
          expect(refreshed.user?.id == userId, true);
          await client.auth.signOut(scope: SignOutScope.local);
        });
        if (expectOldSession) {
          expect(Supabase.instance.client.auth.currentSession != null, true);
        }
        expect(tester.takeException(), isNull);
      } finally {
        if (client.auth.currentSession != null) {
          await driveFuture(
            tester,
            client.auth.signOut(scope: SignOutScope.local),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await driveFuture(tester, client.dispose());
      }
    },
    skip: email.isEmpty || password.isEmpty,
  );
}
