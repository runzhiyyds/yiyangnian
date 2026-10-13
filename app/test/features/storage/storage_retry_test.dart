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
      final customer = find.byType(TextFormField).first;
      expect(tester.widget<TextFormField>(customer).controller?.text, '演示-回归');
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
      expect(tester.widget<TextFormField>(customer).controller?.text, '演示-回归');
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(client.dispose);
    },
  );
}
