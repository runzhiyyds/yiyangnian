import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:yiyangnian/features/auth/auth_service.dart';
import 'package:yiyangnian/features/settings/settings_screen.dart';

class LogoutAuth extends AuthService {
  int exits = 0;
  @override
  Future<void> signOut() async {
    exits++;
  }
}

void main() {
  testWidgets(
    'one logout entry, confirmation cancel and confirmed return to login',
    (tester) async {
      final auth = LogoutAuth();
      final router = GoRouter(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, __) => const Scaffold(body: SettingsScreen()),
          ),
          GoRoute(
            path: '/login',
            builder: (_, __) => const Scaffold(body: Text('登录页')),
          ),
        ],
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('切换账号'), findsNothing);
      expect(find.text('退出登录'), findsOneWidget);
      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(auth.exits, 0);
      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(auth.exits, 1);
      expect(find.text('登录页'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      auth.dispose();
    },
  );
}
