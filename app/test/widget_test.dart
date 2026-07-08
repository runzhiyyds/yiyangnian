import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:yiyangnian/app.dart';
import 'package:yiyangnian/core/app_providers.dart';
import 'package:yiyangnian/core/data_cache.dart';

void main() {
  testWidgets('App loads with full provider set', (WidgetTester tester) async {
    final cache = DataCache(maxSize: 200);
    await tester.pumpWidget(
      MultiProvider(
        providers: buildAppProviders(cache, null),
        child: const YiyangnianApp(),
      ),
    );
    await tester.pumpAndSettle();
  });
}
