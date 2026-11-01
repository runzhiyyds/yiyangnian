import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data_cache.dart';
import 'data_refresh.dart';
import 'repository_read_cache.dart';
import '../features/auth/auth_service.dart';
import '../features/consumption/consumption_repository.dart';
import '../features/customer/customer_repository.dart';
import '../features/storage/storage_repository.dart';
import '../features/storage_options/storage_big_item_repository.dart';
import '../features/storage_options/storage_small_item_repository.dart';
import '../features/inventory/inventory_purchase_repository.dart';
import '../features/inventory/inventory_consumption_repository.dart';
import '../features/inventory/inventory_supp_in_repository.dart';
import '../features/tree/tree_data_provider.dart';

/// 构建应用根 [Provider] 列表，集中依赖注册，便于 main 与测试复用。
List<SingleChildWidget> buildAppProviders(
  DataCache dataCache,
  SupabaseClient? client, {
  LocalStorage? sessionStorage,
  bool enablePush = true,
}) {
  final reads = RepositoryReadCache(() => client?.auth.currentUser?.id);
  final tree = client == null ? null : TreeDataProvider();
  return [
    Provider<DataCache>.value(value: dataCache),
    Provider<RepositoryReadCache>.value(value: reads),
    ChangeNotifierProvider(
      create: (_) => AuthService.withOptions(
        client,
        sessionStorage: sessionStorage,
        enablePush: enablePush,
        onAccountChanged: () {
          dataCache.clear();
          reads.clear();
          tree?.reset();
        },
      ),
    ),
    ChangeNotifierProvider(
      create: (_) => DataRefreshNotifier(dataCache, reads: reads),
    ),
    if (client != null) ...[
      Provider(create: (_) => CustomerRepository(client, readCache: reads)),
      Provider(create: (_) => StorageRepository(client, readCache: reads)),
      Provider(create: (_) => ConsumptionRepository(client, readCache: reads)),
      Provider(
        create: (_) => StorageBigItemRepository(client, readCache: reads),
      ),
      Provider(
        create: (_) => StorageSmallItemRepository(client, readCache: reads),
      ),
      Provider(
        create: (_) => InventoryPurchaseRepository(client, readCache: reads),
      ),
      Provider(
        create: (_) => InventoryConsumptionRepository(client, readCache: reads),
      ),
      Provider(
        create: (_) => InventorySuppInRepository(client, readCache: reads),
      ),
      ChangeNotifierProvider(create: (_) => tree!),
    ],
  ];
}
