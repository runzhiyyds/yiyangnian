import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:yiyangnian/app.dart';
import 'package:yiyangnian/core/app_providers.dart';
import 'package:yiyangnian/core/data_cache.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches and shows splash or home', (tester) async {
    final cache = DataCache(maxSize: 200);
    await tester.pumpWidget(
      MultiProvider(
        providers: buildAppProviders(cache, null),
        child: const YiyangnianApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 15));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
