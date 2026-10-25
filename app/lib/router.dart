import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/config.dart';
import 'core/route_params.dart';
import 'features/auth/auth_service.dart';
import 'features/auth/login_screen.dart';
import 'features/home/main_shell.dart';
import 'features/splash/splash_screen.dart';
import 'features/tree/tree_screen.dart';
import 'features/analytics/store_analytics_screen.dart';
import 'features/customer/customer_detail_screen.dart';
import 'features/customer/customer_edit_screen.dart';
import 'features/storage/storage_edit_screen.dart';
import 'features/storage/storage_detail_screen.dart';
import 'features/consumption/consumption_edit_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/inventory/inventory_options_screen.dart';
import 'features/inventory/inventory_purchase_edit_screen.dart';
import 'features/inventory/inventory_item_detail_screen.dart';
import 'features/inventory/inventory_linked_storages_screen.dart';
import 'features/inventory/inventory_supp_in_edit_screen.dart';
import 'features/inventory/inventory_supp_out_edit_screen.dart';

class AppRouter {
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();

  static GoRouter create(AuthService auth) => GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (!Config.isBackendConfigured) {
        return loc == '/splash' ? null : '/splash';
      }
      if (loc == '/splash') return null;
      // 已在本进程内登录后访问登录页时直接进入首页
      if (auth.isLoggedIn && loc == '/login') return '/home/inventory';
      // 未登录：仅允许启动页与登录页
      if (!auth.isLoggedIn) {
        if (loc == '/login') return null;
        return '/login';
      }
      if (loc == '/home' || loc == '/') return '/home/inventory';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/home', redirect: (_, __) => '/home/inventory'),
      GoRoute(path: '/', redirect: (_, __) => '/home/inventory'),
      GoRoute(
        path: '/customer/new',
        builder: (context, state) {
          final p = CustomerNewParams.fromState(state);
          return CustomerEditScreen(
            templateName: p.templateName,
            initialName: p.initialName,
          );
        },
      ),
      GoRoute(
        path: '/customer/detail',
        builder: (context, state) {
          final p = CustomerDetailParams.fromState(state);
          if (p == null) return const _InvalidParamRedirect(to: '/home/tree');
          return CustomerDetailScreen(customerName: p.customerName);
        },
      ),
      GoRoute(
        path: '/customer/edit',
        builder: (context, state) {
          final p = CustomerEditParams.fromState(state);
          if (p == null) return const _InvalidParamRedirect(to: '/home/tree');
          return CustomerEditScreen(customerName: p.customerName);
        },
      ),
      GoRoute(
        path: '/storage/new',
        builder: (context, state) {
          final p = StorageNewParams.fromState(state);
          return StorageEditScreen(
            customerName: p.customerName,
            copyFromId: p.copyFromId,
          );
        },
      ),
      GoRoute(
        path: '/storage/:id',
        builder: (context, state) {
          final p = StorageDetailParams.fromState(state);
          if (p == null)
            return const _InvalidParamRedirect(to: '/home/storage');
          return StorageDetailScreen(storageId: p.storageId);
        },
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) {
              final p = StorageDetailParams.fromState(state);
              if (p == null)
                return const _InvalidParamRedirect(to: '/home/storage');
              return StorageEditScreen(storageId: p.storageId);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/consumption/new',
        builder: (context, state) {
          final p = ConsumptionNewParams.fromState(state);
          return ConsumptionEditScreen(storageId: p.storageId);
        },
      ),
      GoRoute(
        path: '/consumption/:id/edit',
        builder: (context, state) {
          final p = ConsumptionEditParams.fromState(state);
          if (p == null || p.consumptionId == null)
            return const _InvalidParamRedirect(to: '/home/tree');
          return ConsumptionEditScreen(consumptionId: p.consumptionId);
        },
      ),
      GoRoute(
        path: '/inventory/options',
        builder: (context, state) => const InventoryOptionsScreen(),
      ),
      GoRoute(
        path: '/inventory/purchase/new',
        builder: (_, __) => const InventoryPurchaseEditScreen(),
      ),
      GoRoute(
        path: '/inventory/purchase/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null)
            return const _InvalidParamRedirect(to: '/home/inventory');
          return InventoryPurchaseEditScreen(
            purchaseId: id,
            initialReadOnly: true,
          );
        },
      ),
      GoRoute(
        path: '/inventory/purchase/:id/edit',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null)
            return const _InvalidParamRedirect(to: '/home/inventory');
          // 兼容旧链接，但所有已有进货单必须先进入浏览态。
          return InventoryPurchaseEditScreen(
            purchaseId: id,
            initialReadOnly: true,
          );
        },
      ),
      GoRoute(
        path: '/inventory/item/:smallItemId/storages',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['smallItemId'] ?? '');
          if (id == null) {
            return const _InvalidParamRedirect(to: '/home/inventory');
          }
          return InventoryLinkedStoragesScreen(
            smallItemId: id,
            initialSmallItemName: state.uri.queryParameters['name'],
          );
        },
      ),
      GoRoute(
        path: '/inventory/item/:smallItemId',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['smallItemId'] ?? '');
          if (id == null)
            return const _InvalidParamRedirect(to: '/home/inventory');
          return InventoryItemDetailScreen(smallItemId: id);
        },
      ),
      GoRoute(
        path: '/inventory/supp-in/new',
        builder: (context, state) {
          final itemStr = state.uri.queryParameters['item'];
          final itemId = itemStr != null ? int.tryParse(itemStr) : null;
          final itemName = state.uri.queryParameters['name'];
          return InventorySuppInEditScreen(
            initialSmallItemId: itemId,
            initialSmallItemName: itemName,
          );
        },
      ),
      GoRoute(
        path: '/inventory/supp-in/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null)
            return const _InvalidParamRedirect(to: '/home/inventory');
          return InventorySuppInEditScreen(recordId: id, initialReadOnly: true);
        },
      ),
      GoRoute(
        path: '/inventory/supp-in/:id/edit',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null)
            return const _InvalidParamRedirect(to: '/home/inventory');
          return InventorySuppInEditScreen(recordId: id, initialReadOnly: true);
        },
      ),
      GoRoute(
        path: '/inventory/supp-out/new',
        builder: (context, state) {
          final itemStr = state.uri.queryParameters['item'];
          final itemId = itemStr != null ? int.tryParse(itemStr) : null;
          final itemName = state.uri.queryParameters['name'];
          return InventorySuppOutEditScreen(
            initialSmallItemId: itemId,
            initialSmallItemName: itemName,
          );
        },
      ),
      GoRoute(
        path: '/inventory/supp-out/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null)
            return const _InvalidParamRedirect(to: '/home/inventory');
          return InventorySuppOutEditScreen(
            recordId: id,
            initialReadOnly: true,
          );
        },
      ),
      GoRoute(
        path: '/inventory/supp-out/:id/edit',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null)
            return const _InvalidParamRedirect(to: '/home/inventory');
          return InventorySuppOutEditScreen(
            recordId: id,
            initialReadOnly: true,
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/inventory',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: InventoryOptionsScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/tree',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: TreeScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/storage',
                pageBuilder: (context, state) {
                  final scrollTo = state.uri.queryParameters['scrollTo'];
                  return NoTransitionPage(
                    child: StoreAnalyticsScreen(scrollTo: scrollTo),
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/settings',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: SettingsScreen()),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// 路径参数非法时展示占位并重定向到安全页
class _InvalidParamRedirect extends StatefulWidget {
  const _InvalidParamRedirect({required this.to});

  final String to;

  @override
  State<_InvalidParamRedirect> createState() => _InvalidParamRedirectState();
}

class _InvalidParamRedirectState extends State<_InvalidParamRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(widget.to);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
