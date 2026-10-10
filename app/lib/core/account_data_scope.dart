import 'demo_credentials.dart';
import '../features/customer/customer_model.dart';
import '../features/storage/storage_model.dart';
import '../features/consumption/consumption_model.dart';
import '../features/inventory/inventory_models.dart';
import '../features/storage_options/storage_small_item_repository.dart';

/// 按登录账号隔离「演示域」与「正式域」数据视图。
///
/// - 体验账号 [DemoCredentials.email]：仅见「演示-」客户/商品关联数据
/// - 其他账号：仅见正式数据，隐藏全部演示数据
class AccountDataScope {
  AccountDataScope._();

  static const demoPrefix = '演示-';

  static bool isDemoUser(String? email) {
    if (email == null || email.isEmpty) return false;
    return email.trim().toLowerCase() == DemoCredentials.email.toLowerCase();
  }

  static bool isDemoScope(String? email) => isDemoUser(email);

  static String cacheSuffix(String? email) =>
      isDemoScope(email) ? 'demo' : 'prod';

  /// 当前账号是否应展示该条数据（演示域 vs 正式域）
  static bool includeForUser(String? email, bool isDemoData) =>
      isDemoScope(email) ? isDemoData : !isDemoData;

  static bool isDemoTagged(String? name) =>
      name != null && name.startsWith(demoPrefix);

  static bool isDemoRemark(String? remark) =>
      remark != null &&
      (remark.contains('演示') || remark.startsWith('自动出库 · 演示-'));

  static bool isDemoBusinessCode(String? code) {
    if (code == null || code.isEmpty) return false;
    return code.startsWith('CZ90') ||
        code.startsWith('XF90') ||
        code.startsWith('JH90');
  }

  // ---------- 实体判定 ----------

  static bool isDemoCustomer(CustomerModel c) => isDemoTagged(c.name);

  static bool isDemoStorage(StorageRecordModel s) =>
      isDemoTagged(s.customerName);

  static bool isDemoConsumption(ConsumptionRecordModel c) =>
      isDemoBusinessCode(c.code);

  static bool isDemoInventoryPurchase(
    InventoryPurchaseRecordModel p, {
    Map<int, String> smallItemNames = const {},
  }) {
    // 演示数据种子曾将全局进货编号序列推进到 900xx，因此正式账号后续
    // 新建的进货单也会是 JH90xxx。编号不是数据归属，必须优先以关联商品判断。
    if (p.storageSmallItemIds.isNotEmpty && smallItemNames.isNotEmpty) {
      final itemNames = p.storageSmallItemIds
          .map((id) => smallItemNames[id])
          .whereType<String>()
          .toList();
      if (itemNames.length == p.storageSmallItemIds.length) {
        return itemNames.every(isDemoTagged);
      }
    }

    // 只有历史记录无法解析关联商品时，才用备注/旧编号作兼容兜底。
    return isDemoRemark(p.remark) || isDemoBusinessCode(p.code);
  }

  static bool isDemoInventorySuppIn(
    InventorySuppInRecordModel r, {
    String? smallItemName,
  }) => isDemoRemark(r.remark) || isDemoTagged(smallItemName);

  static bool isDemoInventoryConsumption(
    InventoryConsumptionRecordModel r, {
    String? smallItemName,
  }) => isDemoRemark(r.remark) || isDemoTagged(smallItemName);

  static bool isDemoSmallItemOption(StorageSmallItemOption o) =>
      isDemoTagged(o.name);

  // ---------- 列表过滤 ----------

  static List<CustomerModel> filterCustomers(
    String? email,
    List<CustomerModel> customers,
  ) =>
      customers.where((c) => includeForUser(email, isDemoCustomer(c))).toList();

  static List<StorageRecordModel> filterStorages(
    String? email,
    List<StorageRecordModel> storages,
  ) => storages.where((s) => includeForUser(email, isDemoStorage(s))).toList();

  static List<ConsumptionRecordModel> filterConsumptions(
    String? email,
    List<ConsumptionRecordModel> consumptions,
    Map<int, StorageRecordModel> storageMap,
  ) => consumptions.where((c) {
    final storage = storageMap[c.storageRecordId];
    // 消费编号和进货编号一样来自全局序列；只要父储值记录存在，
    // 就应以父记录的客户归属为准。编号只用于无法找到父记录的历史兜底。
    final isDemo = storage != null
        ? isDemoStorage(storage)
        : isDemoConsumption(c);
    return includeForUser(email, isDemo);
  }).toList();

  static List<StorageSmallItemOption> filterSmallItemOptions(
    String? email,
    List<StorageSmallItemOption> options,
  ) => options
      .where((o) => includeForUser(email, isDemoSmallItemOption(o)))
      .toList();

  static Map<int, String> filterSmallItemNames(
    String? email,
    Map<int, String> names,
  ) => {
    for (final e in names.entries)
      if (includeForUser(email, isDemoTagged(e.value))) e.key: e.value,
  };

  static List<InventoryPurchaseRecordModel> filterInventoryPurchases(
    String? email,
    List<InventoryPurchaseRecordModel> purchases, {
    Map<int, String> smallItemNames = const {},
  }) => purchases
      .where(
        (p) => includeForUser(
          email,
          isDemoInventoryPurchase(p, smallItemNames: smallItemNames),
        ),
      )
      .toList();

  static List<InventorySuppInRecordModel> filterInventorySuppIn(
    String? email,
    List<InventorySuppInRecordModel> records,
    Map<int, String> smallItemNames,
  ) => records.where((r) {
    final isDemo = isDemoInventorySuppIn(
      r,
      smallItemName: smallItemNames[r.storageSmallItemId],
    );
    return includeForUser(email, isDemo);
  }).toList();

  static List<InventoryConsumptionRecordModel> filterInventoryConsumptions(
    String? email,
    List<InventoryConsumptionRecordModel> records,
    Map<int, String> smallItemNames,
  ) => records.where((r) {
    final isDemo = isDemoInventoryConsumption(
      r,
      smallItemName: smallItemNames[r.storageSmallItemId],
    );
    return includeForUser(email, isDemo);
  }).toList();

  /// 客户一览：按账号域过滤客户、储值、消费、小项名称
  static ({
    List<CustomerModel> customers,
    Map<String, List<StorageRecordModel>> storagesByCustomer,
    Map<int, List<ConsumptionRecordModel>> consumptionsByStorage,
    Map<int, String> smallItemNames,
  })
  filterTreeScope({
    required String? email,
    required List<CustomerModel> customers,
    required Map<String, List<StorageRecordModel>> storagesByCustomer,
    required Map<int, List<ConsumptionRecordModel>> consumptionsByStorage,
    required Map<int, String> smallItemNames,
  }) {
    final scopedCustomers = filterCustomers(email, customers);
    final scopedNames = scopedCustomers.map((c) => c.name).toSet();

    final scopedStorages = <String, List<StorageRecordModel>>{};
    for (final name in scopedNames) {
      final list = storagesByCustomer[name] ?? [];
      scopedStorages[name] = filterStorages(email, list);
    }

    final scopedStorageIds = scopedStorages.values
        .expand((l) => l.map((s) => s.id))
        .toSet();

    final scopedConsumptions = <int, List<ConsumptionRecordModel>>{};
    for (final id in scopedStorageIds) {
      scopedConsumptions[id] = consumptionsByStorage[id] ?? [];
    }

    final usedSmallIds = <int>{};
    for (final list in scopedStorages.values) {
      for (final s in list) {
        usedSmallIds.addAll(s.storageSmallItemIds);
      }
    }
    for (final list in scopedConsumptions.values) {
      for (final c in list) {
        usedSmallIds.addAll(c.consumptionProjectIds);
        final legacy = c.consumptionProjectId;
        if (legacy != null) usedSmallIds.add(legacy);
      }
    }

    final scopedSmallNames = {
      for (final e in smallItemNames.entries)
        if (includeForUser(email, isDemoTagged(e.value)) ||
            usedSmallIds.contains(e.key))
          e.key: e.value,
    };

    return (
      customers: scopedCustomers,
      storagesByCustomer: scopedStorages,
      consumptionsByStorage: scopedConsumptions,
      smallItemNames: scopedSmallNames,
    );
  }

  /// 库存原始数据按账号域过滤
  static ({
    List<InventoryPurchaseRecordModel> purchases,
    List<InventorySuppInRecordModel> suppIn,
    List<InventoryConsumptionRecordModel> consumptions,
    List<StorageSmallItemOption> smallOptions,
    Map<int, String> smallItemNames,
  })
  scopeInventoryRaw({
    required String? email,
    required List<InventoryPurchaseRecordModel> purchases,
    required List<InventorySuppInRecordModel> suppIn,
    required List<InventoryConsumptionRecordModel> consumptions,
    required List<StorageSmallItemOption> smallOptions,
  }) {
    final scopedSmallOptions = filterSmallItemOptions(email, smallOptions);
    final nameById = {for (final o in smallOptions) o.id: o.name};
    return (
      purchases: filterInventoryPurchases(
        email,
        purchases,
        smallItemNames: nameById,
      ),
      suppIn: filterInventorySuppIn(email, suppIn, nameById),
      consumptions: filterInventoryConsumptions(email, consumptions, nameById),
      smallOptions: scopedSmallOptions,
      smallItemNames: filterSmallItemNames(email, nameById),
    );
  }

  /// 根据已域隔离的库存数据计算各小项余额
  static Map<int, int> computeInventoryBalances({
    required List<InventoryPurchaseRecordModel> purchases,
    required List<InventorySuppInRecordModel> suppIn,
    required List<InventoryConsumptionRecordModel> consumptions,
    required Iterable<StorageSmallItemOption> smallOptions,
  }) {
    final balanceBySmallItem = <int, int>{};
    for (final o in smallOptions) {
      balanceBySmallItem[o.id] = 0;
    }
    for (final p in purchases) {
      for (final id in p.storageSmallItemIds) {
        balanceBySmallItem.putIfAbsent(id, () => 0);
      }
    }
    for (final r in suppIn) {
      balanceBySmallItem.putIfAbsent(r.storageSmallItemId, () => 0);
    }
    for (final r in consumptions) {
      balanceBySmallItem.putIfAbsent(r.storageSmallItemId, () => 0);
    }
    for (final p in purchases) {
      if (p.isVoided) continue;
      for (
        var i = 0;
        i < p.storageSmallItemIds.length &&
            i < p.storageBigItems.length &&
            i < p.quantities.length;
        i++
      ) {
        final id = p.storageSmallItemIds[i];
        if (id <= 0) continue;
        balanceBySmallItem[id] =
            (balanceBySmallItem[id] ?? 0) + p.quantities[i];
      }
    }
    for (final r in suppIn) {
      if (r.isVoided) continue;
      balanceBySmallItem[r.storageSmallItemId] =
          (balanceBySmallItem[r.storageSmallItemId] ?? 0) + r.quantity;
    }
    for (final r in consumptions) {
      if (r.isVoided) continue;
      balanceBySmallItem[r.storageSmallItemId] =
          (balanceBySmallItem[r.storageSmallItemId] ?? 0) - r.quantity;
    }
    return balanceBySmallItem;
  }

  static bool smallItemVisibleToUser(String? email, String? smallItemName) =>
      includeForUser(email, isDemoTagged(smallItemName));

  static String inventorySmallOptionsCacheKey(String? email) =>
      'inventory_small_options_${cacheSuffix(email)}';

  static String inventoryBigOptionsCacheKey(String? email) =>
      'inventory_big_options_${cacheSuffix(email)}';

  static String inventoryItemDetailCacheKey(String? email, int smallItemId) =>
      'inventory_item_detail_${smallItemId}_${cacheSuffix(email)}';
}

/// 兼容旧引用，逐步迁移至 [AccountDataScope]。
typedef DemoMode = AccountDataScope;
