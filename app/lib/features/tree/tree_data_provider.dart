import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../customer/customer_model.dart';
import '../customer/customer_repository.dart';
import '../storage/storage_model.dart';
import '../storage/storage_repository.dart';
import '../consumption/consumption_model.dart';
import '../consumption/consumption_repository.dart';
import '../storage_options/storage_small_item_repository.dart';
import '../../core/data_cache.dart';
import '../../core/repository_read_cache.dart';
import '../../core/demo_mode.dart';
import '../../core/error_message.dart';
import '../../core/retry_helper.dart';
import '../auth/auth_service.dart';

/// 客户信息一览缓存结构
class _TreeCacheData {
  _TreeCacheData({
    required this.customers,
    required this.storagesByCustomer,
    required this.consumptionsByStorage,
    required this.smallItemNames,
  });
  final List<CustomerModel> customers;
  final Map<String, List<StorageRecordModel>> storagesByCustomer;
  final Map<int, List<ConsumptionRecordModel>> consumptionsByStorage;
  final Map<int, String> smallItemNames;
}

/// 客户信息一览数据提供者，供启动页预加载与 TreeScreen 共用
class TreeDataProvider extends ChangeNotifier {
  List<CustomerModel> customers = [];
  Map<String, List<StorageRecordModel>> storagesByCustomer = {};
  Map<int, List<ConsumptionRecordModel>> consumptionsByStorage = {};
  Map<int, String> smallItemNames = {};
  bool loading = true;
  bool hasLoaded = false;
  String? error;

  /// 冷启动 / Supabase 唤醒时可能较慢；首页已改为少量聚合请求，略放宽避免误报超时
  static const _loadTimeout = Duration(seconds: 45);
  int _epoch = 0;
  bool _disposed = false;
  Future<void>? _pending;
  int? _pendingRevision;

  void _apply(_TreeCacheData data) {
    hasLoaded = true;
    customers = data.customers;
    storagesByCustomer = data.storagesByCustomer;
    consumptionsByStorage = data.consumptionsByStorage;
    smallItemNames = data.smallItemNames;
  }

  /// 切换账号时清空内存状态，避免短暂展示上一账号数据。
  void reset() {
    _epoch++;
    _pending = null;
    hasLoaded = false;
    customers = [];
    storagesByCustomer = {};
    consumptionsByStorage = {};
    smallItemNames = {};
    loading = true;
    error = null;
    notifyListeners();
  }

  Future<void> load(
    BuildContext context, {
    bool forceRefresh = false,
    bool invalidateReads = true,
  }) {
    final auth = context.read<AuthService>();
    final owner = auth.user?.id;
    final email = auth.user?.email;
    if (owner == null) return Future.value();
    final cache = context.read<DataCache>();
    final key = 'tree_data_$owner';
    if (!forceRefresh) {
      final cached = cache.get<_TreeCacheData>(key);
      if (cached != null) {
        _apply(cached);
        loading = false;
        error = null;
        notifyListeners();
        return Future.value();
      }
      if (_pending != null && _pendingRevision == cache.revision)
        return _pending!;
    } else if (invalidateReads) {
      context.read<RepositoryReadCache?>()?.clear();
    }
    final epoch = ++_epoch;
    final revision = cache.revision;
    bool current() => !_disposed && epoch == _epoch && auth.user?.id == owner;
    loading = true;
    error = null;
    notifyListeners();
    final request = _loadInternal(context);
    final pending = () async {
      try {
        final data = await request.timeout(_loadTimeout);
        if (!current() || cache.revision != revision) return;
        final scoped = DemoMode.filterTreeScope(
          email: email,
          customers: data.customers,
          storagesByCustomer: data.storagesByCustomer,
          consumptionsByStorage: data.consumptionsByStorage,
          smallItemNames: data.smallItemNames,
        );
        final result = _TreeCacheData(
          customers: scoped.customers,
          storagesByCustomer: scoped.storagesByCustomer,
          consumptionsByStorage: scoped.consumptionsByStorage,
          smallItemNames: scoped.smallItemNames,
        );
        _apply(result);
        cache.set(key, result, ttl: const Duration(seconds: 30));
      } catch (e) {
        if (current()) error = toUserFriendlyError(e);
      } finally {
        if (current()) {
          loading = false;
          _pending = null;
          notifyListeners();
        }
      }
    }();
    _pendingRevision = revision;
    _pending = pending;
    return pending;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }

  Future<_TreeCacheData> _loadInternal(BuildContext context) async {
    final customerRepo = context.read<CustomerRepository>();
    final storageRepo = context.read<StorageRepository>();
    final consumptionRepo = context.read<ConsumptionRepository>();
    final smallItemRepo = context.read<StorageSmallItemRepository>();

    return retryOnFailure(() async {
      final batch = await Future.wait([
        customerRepo.getAll(),
        storageRepo.getAll(),
        smallItemRepo.getAll(),
      ]);
      final customersList = batch[0] as List<CustomerModel>;
      final allStorages = batch[1] as List<StorageRecordModel>;
      final options = batch[2] as List<StorageSmallItemOption>;

      final storagesByCustomerMap = <String, List<StorageRecordModel>>{
        for (final c in customersList) c.name: [],
      };
      for (final s in allStorages) {
        storagesByCustomerMap.putIfAbsent(s.customerName, () => []).add(s);
      }
      for (final list in storagesByCustomerMap.values) {
        list.sort((a, b) => b.storageDate.compareTo(a.storageDate));
      }

      final consumptionsByStorageMap = <int, List<ConsumptionRecordModel>>{
        for (final s in allStorages) s.id: [],
      };
      if (allStorages.isNotEmpty) {
        final allConsumptions = await consumptionRepo.getByStorageIds(
          allStorages.map((s) => s.id),
        );
        for (final c in allConsumptions) {
          consumptionsByStorageMap
              .putIfAbsent(c.storageRecordId, () => [])
              .add(c);
        }
        for (final list in consumptionsByStorageMap.values) {
          list.sort((a, b) => b.consumptionDate.compareTo(a.consumptionDate));
        }
      }

      final nameMap = {for (var o in options) o.id: o.name};

      return _TreeCacheData(
        customers: customersList,
        storagesByCustomer: storagesByCustomerMap,
        consumptionsByStorage: consumptionsByStorageMap,
        smallItemNames: nameMap,
      );
    });
  }
}
