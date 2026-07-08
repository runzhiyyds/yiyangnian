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
  String? error;

  /// 冷启动 / Supabase 唤醒时可能较慢；首页已改为少量聚合请求，略放宽避免误报超时
  static const _loadTimeout = Duration(seconds: 45);
  static const _cacheKeyTree = 'tree_data';
  static const _cacheKeyTreeDemo = 'tree_data_demo';

  String _treeCacheKey(BuildContext context) {
    final email = context.read<AuthService>().user?.email;
    return DemoMode.isDemoScope(email)
        ? _cacheKeyTreeDemo
        : '${_cacheKeyTree}_${DemoMode.cacheSuffix(email)}';
  }

  void _applyAccountScopeIfNeeded(BuildContext context) {
    final email = context.read<AuthService>().user?.email;
    final filtered = DemoMode.filterTreeScope(
      email: email,
      customers: customers,
      storagesByCustomer: storagesByCustomer,
      consumptionsByStorage: consumptionsByStorage,
      smallItemNames: smallItemNames,
    );
    customers = filtered.customers;
    storagesByCustomer = filtered.storagesByCustomer;
    consumptionsByStorage = filtered.consumptionsByStorage;
    smallItemNames = filtered.smallItemNames;
  }

  /// 切换账号时清空内存状态，避免短暂展示上一账号数据。
  void reset() {
    customers = [];
    storagesByCustomer = {};
    consumptionsByStorage = {};
    smallItemNames = {};
    loading = true;
    error = null;
    notifyListeners();
  }

  bool _loadInProgress = false;
  Completer<void>? _loadCompleter;

  Future<void> load(BuildContext context, {bool forceRefresh = false}) async {
    final cache = context.read<DataCache>();
    final cacheKey = _treeCacheKey(context);
    if (!forceRefresh) {
      final cached = cache.get<_TreeCacheData>(cacheKey);
      if (cached != null) {
        customers = cached.customers;
        storagesByCustomer = cached.storagesByCustomer;
        consumptionsByStorage = cached.consumptionsByStorage;
        smallItemNames = cached.smallItemNames;
        loading = false;
        error = null;
        notifyListeners();
        return;
      }
    }

    if (_loadInProgress) {
      await _loadCompleter?.future;
      return;
    }
    _loadInProgress = true;
    _loadCompleter = Completer<void>();
    loading = true;
    error = null;
    notifyListeners();

    try {
      await _loadInternal(context).timeout(
        _loadTimeout,
        onTimeout: () => throw TimeoutException('加载超时，请检查网络后重试'),
      );
      _applyAccountScopeIfNeeded(context);
      cache.set(
        cacheKey,
        _TreeCacheData(
          customers: customers,
          storagesByCustomer: storagesByCustomer,
          consumptionsByStorage: consumptionsByStorage,
          smallItemNames: smallItemNames,
        ),
      );
      loading = false;
      error = null;
    } catch (e) {
      loading = false;
      error = toUserFriendlyError(e);
    } finally {
      _loadInProgress = false;
      _loadCompleter?.complete();
      _loadCompleter = null;
    }
    notifyListeners();
  }

  Future<void> _loadInternal(BuildContext context) async {
    final customerRepo = context.read<CustomerRepository>();
    final storageRepo = context.read<StorageRepository>();
    final consumptionRepo = context.read<ConsumptionRepository>();
    final smallItemRepo = context.read<StorageSmallItemRepository>();

    await retryOnFailure(() async {
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
        final allConsumptions =
            await consumptionRepo.getByStorageIds(allStorages.map((s) => s.id));
        for (final c in allConsumptions) {
          consumptionsByStorageMap.putIfAbsent(c.storageRecordId, () => []).add(c);
        }
        for (final list in consumptionsByStorageMap.values) {
          list.sort((a, b) => b.consumptionDate.compareTo(a.consumptionDate));
        }
      }

      final nameMap = {for (var o in options) o.id: o.name};

      customers = customersList;
      storagesByCustomer = storagesByCustomerMap;
      consumptionsByStorage = consumptionsByStorageMap;
      smallItemNames = nameMap;
    });
  }
}
