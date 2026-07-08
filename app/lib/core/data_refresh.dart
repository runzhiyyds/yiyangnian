import 'package:flutter/foundation.dart';

import 'data_cache.dart';

/// 全局数据变更通知，用于各页面实时刷新。
/// 支持按模块失效以减少全量清空带来的重复请求，或 [notifyDataChanged] 全量清空。
class DataRefreshNotifier extends ChangeNotifier {
  DataRefreshNotifier(this._cache);

  final DataCache _cache;

  /// 全量清空缓存并通知（与原有行为一致）。
  void notifyDataChanged() {
    _cache.clear();
    notifyListeners();
  }

  /// 仅失效树/首页相关缓存。
  void invalidateTree() {
    _cache.remove('tree_data');
    _cache.remove('tree_data_demo');
    _cache.remove('tree_data_prod');
    notifyListeners();
  }

  /// 仅失效储值相关缓存（列表、详情、storage_*）。
  void invalidateStorage() {
    _cache.remove('storage_list');
    _cache.remove('storage_list_demo');
    _cache.remove('storage_list_prod');
    _cache.removeByPrefix('storage_detail_');
    _cache.removeByPrefix('storage_');
    notifyListeners();
  }

  /// 仅失效客户相关缓存。
  void invalidateCustomer() {
    _cache.removeByPrefix('customer_detail_');
    _cache.removeByPrefix('customer_');
    _cache.removeByPrefix('storages_template_');
    notifyListeners();
  }

  /// 仅失效消费相关缓存。
  void invalidateConsumption() {
    _cache.removeByPrefix('consumption_');
    notifyListeners();
  }

  /// 仅失效分析页预加载缓存。
  void invalidateAnalytics() {
    _cache.remove('analytics_preload');
    notifyListeners();
  }

  /// 储值或消费变更时：失效储值、消费、树、分析预加载。
  void invalidateStorageAndConsumption() {
    invalidateStorage();
    invalidateConsumption();
    invalidateCustomer();
    invalidateTree();
    invalidateAnalytics();
  }

  /// 储值/消费变更且影响库存（如新建储值自动出库）时一并失效库存缓存。
  void invalidateStorageConsumptionAndInventory() {
    invalidateStorageAndConsumption();
    invalidateInventory();
  }

  /// 客户变更时：失效客户、树、分析预加载。
  void invalidateCustomerAndTree() {
    invalidateCustomer();
    invalidateTree();
    invalidateAnalytics();
  }

  /// 仅失效储值选项缓存（大项/小项列表），用于新增选项后。
  void invalidateStorageOptions() {
    _cache.remove('small_item_options');
    _cache.remove('big_item_options');
    _cache.removeByPrefix('inventory_big_options_');
    _cache.removeByPrefix('inventory_small_options_');
    _cache.remove('inventory_big_options');
    _cache.remove('inventory_small_options');
    notifyListeners();
  }

  /// 仅失效库存相关缓存。
  void invalidateInventory() {
    _cache.removeByPrefix('inventory_');
    notifyListeners();
  }
}
