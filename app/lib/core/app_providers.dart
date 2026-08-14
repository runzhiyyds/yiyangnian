import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data_cache.dart';
import 'data_refresh.dart';
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
  SupabaseClient? client,
) {
  return [
    Provider<DataCache>.value(value: dataCache),
    ChangeNotifierProvider(create: (_) => AuthService(client)),
    ChangeNotifierProvider(create: (_) => DataRefreshNotifier(dataCache)),
    if (client != null) ...[
      Provider(create: (_) => CustomerRepository(client)),
      Provider(create: (_) => StorageRepository(client)),
      Provider(create: (_) => ConsumptionRepository(client)),
      Provider(create: (_) => StorageBigItemRepository(client)),
      Provider(create: (_) => StorageSmallItemRepository(client)),
      Provider(create: (_) => InventoryPurchaseRepository(client)),
      Provider(create: (_) => InventoryConsumptionRepository(client)),
      Provider(create: (_) => InventorySuppInRepository(client)),
      ChangeNotifierProvider(create: (_) => TreeDataProvider()),
    ],
  ];
}
