import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lunar/lunar.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/date_range_helper.dart';
import '../../core/demo_mode.dart';
import '../../core/error_message.dart';
import '../../core/lunar_helper.dart';
import '../../core/retry_helper.dart';
import '../../widgets/loading_placeholder.dart';
import '../auth/auth_service.dart';
import '../consumption/consumption_model.dart';
import '../consumption/consumption_repository.dart';
import '../customer/customer_model.dart';
import '../customer/customer_repository.dart';
import '../inventory/inventory_models.dart';
import '../inventory/inventory_purchase_repository.dart';
import '../storage/storage_model.dart';
import '../storage/storage_repository.dart';
import '../storage_options/storage_big_item_repository.dart';
import '../storage_options/storage_small_item_repository.dart';

/// 分析用日期范围缓存 key：start_end 格式
String _rangeCacheKey(DateTime start, DateTime end) =>
    '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}_'
    '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';

class _CachedSummary {
  final double total;
  final int count;
  final Map<String, int> bigCounts;
  final Map<String, int> smallCounts;
  /// 贡献该汇总金额的储值记录，用于下钻
  final List<StorageRecordModel> contributingStorages;
  /// 按储值大项分组的消费记录，用于下钻
  final Map<String, List<ConsumptionRecordModel>> bigItemConsumptions;
  /// 按储值小项分组的消费记录，用于下钻
  final Map<String, List<ConsumptionRecordModel>> smallItemConsumptions;
  _CachedSummary({
    required this.total,
    required this.count,
    required this.bigCounts,
    required this.smallCounts,
    this.contributingStorages = const [],
    this.bigItemConsumptions = const {},
    this.smallItemConsumptions = const {},
  });
}

/// 某周期的汇总：全部 + 按储值大项分别汇总
class _PeriodSummaryData {
  final _CachedSummary all;
  final Map<String, _CachedSummary> byBigItem;
  /// 本周期全部进货单。进货金额按整单记录，不能可靠拆分到储值大项。
  final List<InventoryPurchaseRecordModel> purchases;
  /// 消费记录对应的储值，用于下钻展示客户名
  final Map<int, StorageRecordModel> consumptionStorageMap;
  /// 小项 ID 到名称，用于下钻展示
  final Map<int, String> consumptionSmallNames;
  _PeriodSummaryData({
    required this.all,
    required this.byBigItem,
    this.purchases = const [],
    this.consumptionStorageMap = const {},
    this.consumptionSmallNames = const {},
  });
}

// 仅保留月看板，不再使用周看板

class _CachedCalendarData {
  final Map<String, List<ConsumptionRecordModel>> byDay;
  final Map<int, StorageRecordModel> storageMap;
  final Map<int, String> smallNames;
  _CachedCalendarData({
    required this.byDay,
    required this.storageMap,
    required this.smallNames,
  });
}

/// 启动页预加载的店铺分析数据，供 [StoreAnalyticsScreen] 首次进入时直接使用
class _AnalyticsPreloadResult {
  _AnalyticsPreloadResult({
    required this.customers,
    required this.depositByCustomer,
    required this.birthdayThisWeek,
    required this.birthdayThisMonth,
    required this.allBigItemNamesFromRepo,
    required this.periodSummary,
    required this.periodSummaryCacheKey,
    required this.calendarData,
    required this.calendarCacheKey,
    required this.analyticsRangeStart,
    required this.analyticsRangeEnd,
    required this.calendarSelectedMonth,
  });
  final List<CustomerModel> customers;
  final Map<String, double> depositByCustomer;
  final List<CustomerModel> birthdayThisWeek;
  final List<CustomerModel> birthdayThisMonth;
  final List<String> allBigItemNamesFromRepo;
  final _PeriodSummaryData periodSummary;
  final String periodSummaryCacheKey;
  final _CachedCalendarData calendarData;
  final String calendarCacheKey;
  final DateTime analyticsRangeStart;
  final DateTime analyticsRangeEnd;
  final DateTime calendarSelectedMonth;
}

const String _kAnalyticsPreloadCacheKey = 'analytics_preload';

/// 供启动页调用：并行预加载首页与店铺分析数据，避免进入分析页时二次等待
Future<void> preloadStoreAnalyticsData(BuildContext context) async {
  final customerRepo = context.read<CustomerRepository>();
  final storageRepo = context.read<StorageRepository>();
  final consumptionRepo = context.read<ConsumptionRepository>();
  final purchaseRepo = context.read<InventoryPurchaseRepository>();
  final bigItemRepo = context.read<StorageBigItemRepository>();
  final smallItemRepo = context.read<StorageSmallItemRepository>();
  final cache = context.read<DataCache>();

  try {
    final (weekStart, weekEnd) = DateRangeHelper.thisWeek();
    final monthStart = DateTime(weekStart.year, weekStart.month, 1);
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);

    final email = context.read<AuthService>().user?.email;
    final customers = await retryOnFailure(() => customerRepo.getAll());
    final scopedCustomers = DemoMode.filterCustomers(email, customers);
    final bigOptions = await bigItemRepo.getAll();
    final allBigItemNamesFromRepo = bigOptions.map((o) => o.name).toList();

    final deposits = await Future.wait(
      scopedCustomers.map((c) => customerRepo.getTotalDeposit(c.name)),
    );
    final depositByCustomer = {
      for (var i = 0; i < scopedCustomers.length; i++)
        scopedCustomers[i].name: deposits[i],
    };
    final sorted = scopedCustomers.toList()
      ..sort((a, b) =>
          (depositByCustomer[b.name] ?? 0).compareTo(depositByCustomer[a.name] ?? 0));

    var consumptionsWeek = await consumptionRepo.getByDateRange(weekStart, weekEnd);
    var consumptionsMonth = await consumptionRepo.getByDateRange(monthStart, monthEnd);

    final storageIdsWeek = consumptionsWeek.map((c) => c.storageRecordId).toSet().toList();
    final storageIdsMonth = consumptionsMonth.map((c) => c.storageRecordId).toSet().toList();
    final allStorageIds = {...storageIdsWeek, ...storageIdsMonth}.toList();
    final storageMap = <int, StorageRecordModel>{};
    for (final id in allStorageIds) {
      final s = await storageRepo.getById(id);
      if (s != null) storageMap[id] = s;
    }
    final smallOptions = await smallItemRepo.getAll();
    var smallIdToName = {for (var o in smallOptions) o.id: o.name};

    consumptionsWeek =
        DemoMode.filterConsumptions(email, consumptionsWeek, storageMap);
    consumptionsMonth =
        DemoMode.filterConsumptions(email, consumptionsMonth, storageMap);
    storageMap.removeWhere(
        (_, s) => !DemoMode.includeForUser(email, DemoMode.isDemoStorage(s)));
    smallIdToName = DemoMode.filterSmallItemNames(email, smallIdToName);

    var storagesInRangeWeek =
        await storageRepo.getByStorageDateRange(weekStart, weekEnd);
    storagesInRangeWeek = DemoMode.filterStorages(email, storagesInRangeWeek);
    var purchasesInRangeWeek =
        await purchaseRepo.getByDateRange(weekStart, weekEnd);
    purchasesInRangeWeek =
        DemoMode.filterInventoryPurchases(email, purchasesInRangeWeek);
    final periodSummary = _buildPeriodSummaryFromConsumptions(
      weekStart, weekEnd, consumptionsWeek, storageMap, smallIdToName,
      storagesInRangeWeek, purchasesInRangeWeek,
    );
    final periodSummaryCacheKey = _rangeCacheKey(weekStart, weekEnd);

    final calendarData = _buildCalendarDataFromConsumptions(
      monthStart, monthEnd, consumptionsMonth, storageMap, smallIdToName,
    );
    final calendarCacheKey = 'month_${monthStart.year}-${monthStart.month.toString().padLeft(2, '0')}';

    final now = DateTime.now();
    final weekStartDt = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final weekEndDt = weekStartDt.add(const Duration(days: 6));
    final monthStartDt = DateTime(now.year, now.month, 1);
    final monthEndDt = DateTime(now.year, now.month + 1, 0);
    final lunarYear = _getLunarYear(now);
    final birthdayThisWeek = <CustomerModel>[];
    final birthdayThisMonth = <CustomerModel>[];
    for (final c in sorted) {
      DateTime? checkDate;
      if (c.solarBirthday != null) {
        checkDate = DateTime(now.year, c.solarBirthday!.month, c.solarBirthday!.day);
      } else if (c.lunarBirthday != null) {
        final parsed = _parseLunarBirthdayForPreload(c.lunarBirthday!);
        if (parsed != null) {
          final solar = LunarHelper.lunarToSolar(lunarYear, parsed.$1, parsed.$2);
          checkDate = solar;
        }
      }
      if (checkDate != null) {
        if (!checkDate.isBefore(weekStartDt) && !checkDate.isAfter(weekEndDt)) birthdayThisWeek.add(c);
        if (!checkDate.isBefore(monthStartDt) && !checkDate.isAfter(monthEndDt)) birthdayThisMonth.add(c);
      }
    }

    cache.set(
      _kAnalyticsPreloadCacheKey,
      _AnalyticsPreloadResult(
        customers: sorted,
        depositByCustomer: depositByCustomer,
        birthdayThisWeek: birthdayThisWeek,
        birthdayThisMonth: birthdayThisMonth,
        allBigItemNamesFromRepo: allBigItemNamesFromRepo,
        periodSummary: periodSummary,
        periodSummaryCacheKey: periodSummaryCacheKey,
        calendarData: calendarData,
        calendarCacheKey: calendarCacheKey,
        analyticsRangeStart: weekStart,
        analyticsRangeEnd: weekEnd,
        calendarSelectedMonth: monthStart,
      ),
    );
  } catch (e) {
    debugPrint('preloadStoreAnalyticsData failed: $e');
    cache.set('analytics_preload_failed', true);
    // 预加载失败不影响进入首页，分析页进入时会提示并支持重试
  }
}

int _getLunarYear(DateTime d) {
  try {
    return Solar.fromDate(d).getLunar().getYear();
  } catch (_) {
    return d.year;
  }
}

(int, int)? _parseLunarBirthdayForPreload(String s) {
  final re = RegExp(r'(\d{1,4})年(?:闰)?(\d{1,2})月(\d{1,2})日');
  final m = re.firstMatch(s);
  if (m == null) return null;
  final month = int.tryParse(m.group(2) ?? '');
  final day = int.tryParse(m.group(3) ?? '');
  if (month == null || day == null) return null;
  return (month, day);
}

/// [storagesInRange] 储值时间在本周期内的储值记录，用于金额汇总；若为空则金额为 0
_PeriodSummaryData _buildPeriodSummaryFromConsumptions(
  DateTime start,
  DateTime end,
  List<ConsumptionRecordModel> consumptions,
  Map<int, StorageRecordModel> storageMap,
  Map<int, String> smallIdToName,
  List<StorageRecordModel> storagesInRange,
  List<InventoryPurchaseRecordModel> purchasesInRange,
) {
  final double totalAll = storagesInRange.fold<double>(0, (sum, s) => sum + s.amount);
  final bigCountsAll = <String, int>{};
  final smallCountsAll = <String, int>{};
  final bigItemConsumptionsAll = <String, List<ConsumptionRecordModel>>{};
  final smallItemConsumptionsAll = <String, List<ConsumptionRecordModel>>{};
  for (final c in consumptions) {
    final storage = storageMap[c.storageRecordId];
    if (storage != null) {
      if (storage.storageBigItems.isEmpty) {
        const other = '其他';
        bigCountsAll[other] = (bigCountsAll[other] ?? 0) + 1;
        bigItemConsumptionsAll.putIfAbsent(other, () => []).add(c);
      } else {
        for (final name in storage.storageBigItems) {
          if (name.isNotEmpty) {
            bigCountsAll[name] = (bigCountsAll[name] ?? 0) + 1;
            bigItemConsumptionsAll.putIfAbsent(name, () => []).add(c);
          }
        }
      }
    }
    final ids = c.consumptionProjectIds.isNotEmpty
        ? c.consumptionProjectIds
        : (c.consumptionProjectId != null ? [c.consumptionProjectId!] : <int>[]);
    if (ids.isEmpty) {
      const smallName = '未分类';
      smallCountsAll[smallName] = (smallCountsAll[smallName] ?? 0) + 1;
      smallItemConsumptionsAll.putIfAbsent(smallName, () => []).add(c);
    } else {
      for (final id in ids) {
        final smallName = smallIdToName[id] ?? '未分类';
        smallCountsAll[smallName] = (smallCountsAll[smallName] ?? 0) + 1;
        smallItemConsumptionsAll.putIfAbsent(smallName, () => []).add(c);
      }
    }
  }
  final bigSortedAll = Map.fromEntries(
    bigCountsAll.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );
  final smallSortedAll = Map.fromEntries(
    smallCountsAll.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );
  final summaryAll = _CachedSummary(
    total: totalAll,
    count: consumptions.length,
    bigCounts: bigSortedAll,
    smallCounts: smallSortedAll,
    contributingStorages: storagesInRange,
    bigItemConsumptions: bigItemConsumptionsAll,
    smallItemConsumptions: smallItemConsumptionsAll,
  );
  final byBigItem = <String, _CachedSummary>{};
  final bigNamesForAmount = <String>{};
  for (final s in storagesInRange) {
    if (s.storageBigItems.isEmpty) {
      bigNamesForAmount.add('其他');
    } else {
      for (final n in s.storageBigItems) {
        if (n.isNotEmpty) bigNamesForAmount.add(n);
      }
    }
  }
  final allBigNames = <String>{...bigSortedAll.keys, ...bigNamesForAmount};
  for (final bigName in allBigNames) {
    final storagesForBig = bigName == '其他'
        ? storagesInRange.where((s) => s.storageBigItems.isEmpty).toList()
        : storagesInRange.where((s) => s.storageBigItems.contains(bigName)).toList();
    final amountTotal = storagesForBig
        .fold<double>(0, (sum, s) => sum + s.amount);
    final subset = consumptions.where((c) {
      final s = storageMap[c.storageRecordId];
      if (s == null) return false;
      return bigName == '其他'
          ? s.storageBigItems.isEmpty
          : s.storageBigItems.contains(bigName);
    }).toList();
    final bigCounts = <String, int>{};
    final smallCounts = <String, int>{};
    for (final c in subset) {
      final storage = storageMap[c.storageRecordId];
      if (storage != null) {
        for (final n in storage.storageBigItems) {
          if (n.isNotEmpty) bigCounts[n] = (bigCounts[n] ?? 0) + 1;
        }
      }
      final ids = c.consumptionProjectIds.isNotEmpty
          ? c.consumptionProjectIds
          : (c.consumptionProjectId != null ? [c.consumptionProjectId!] : <int>[]);
      if (ids.isEmpty) {
        const smallName = '未分类';
        smallCounts[smallName] = (smallCounts[smallName] ?? 0) + 1;
      } else {
        for (final id in ids) {
          final smallName = smallIdToName[id] ?? '未分类';
          smallCounts[smallName] = (smallCounts[smallName] ?? 0) + 1;
        }
      }
    }
        final bigItemConsums = <String, List<ConsumptionRecordModel>>{};
    for (final c in subset) {
      final st = storageMap[c.storageRecordId];
      if (st != null) {
        if (st.storageBigItems.isEmpty) {
          bigItemConsums.putIfAbsent('其他', () => []).add(c);
        } else {
          for (final n in st.storageBigItems) {
            if (n.isNotEmpty) bigItemConsums.putIfAbsent(n, () => []).add(c);
          }
        }
      }
    }
    final smallItemConsums = <String, List<ConsumptionRecordModel>>{};
    for (final c in subset) {
      final ids = c.consumptionProjectIds.isNotEmpty
          ? c.consumptionProjectIds
          : (c.consumptionProjectId != null ? [c.consumptionProjectId!] : <int>[]);
      if (ids.isEmpty) {
        smallItemConsums.putIfAbsent('未分类', () => []).add(c);
      } else {
        for (final id in ids) {
          final sn = smallIdToName[id] ?? '未分类';
          smallItemConsums.putIfAbsent(sn, () => []).add(c);
        }
      }
    }
    final bigS = Map.fromEntries(bigCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
    final smallS = Map.fromEntries(smallCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
    byBigItem[bigName] = _CachedSummary(
      total: amountTotal,
      count: subset.length,
      bigCounts: bigS,
      smallCounts: smallS,
      contributingStorages: storagesForBig,
      bigItemConsumptions: bigItemConsums,
      smallItemConsumptions: smallItemConsums,
    );
  }
  return _PeriodSummaryData(
    all: summaryAll,
    byBigItem: byBigItem,
    purchases: purchasesInRange,
    consumptionStorageMap: storageMap,
    consumptionSmallNames: smallIdToName,
  );
}

String _dayKeyForPreload(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

_CachedCalendarData _buildCalendarDataFromConsumptions(
  DateTime monthStart,
  DateTime monthEnd,
  List<ConsumptionRecordModel> consumptions,
  Map<int, StorageRecordModel> storageMap,
  Map<int, String> smallNames,
) {
  final byDay = <String, List<ConsumptionRecordModel>>{};
  for (final c in consumptions) {
    final key = _dayKeyForPreload(c.consumptionDate);
    byDay.putIfAbsent(key, () => []).add(c);
  }
  for (final list in byDay.values) {
    list.sort((a, b) => a.consumptionDate.compareTo(b.consumptionDate));
  }
  return _CachedCalendarData(
    byDay: byDay,
    storageMap: storageMap,
    smallNames: smallNames,
  );
}

class StoreAnalyticsScreen extends StatefulWidget {
  const StoreAnalyticsScreen({super.key, this.scrollTo});

  /// 推送点击后传入，用于定位滚动：birthday=近期生日提醒，top=顶部
  final String? scrollTo;

  @override
  State<StoreAnalyticsScreen> createState() => _StoreAnalyticsScreenState();
}

class _StoreAnalyticsScreenState extends State<StoreAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<CustomerModel> _customers = [];
  Map<String, double> _depositByCustomer = {};
  List<CustomerModel> _birthdayThisWeek = [];
  List<CustomerModel> _birthdayThisMonth = [];
  bool _loading = true;
  String? _error;
  bool _loadInProgress = false;
  bool _rankingExpanded = false;
  late final DataRefreshNotifier _refreshNotifier;

  /// 分析用时间范围（用户选择或快捷，默认本周）
  late DateTime _analyticsRangeStart;
  late DateTime _analyticsRangeEnd;
  /// 储值大项筛选：null = 全部，非空 = 该大项
  String? _selectedBigItemFilter;
  /// 按储值大项筛选项：全部 + 本周期出现的大项 + 系统配置中其余大项（保证始终展示所有枚举）
  List<String> _bigItemFilterOptions = [];
  /// 系统配置的储值大项名称列表（在 _load 时拉取，用于补全 _bigItemFilterOptions）
  List<String> _allBigItemNamesFromRepo = [];
  double _consumptionTotal = 0;
  int _consumptionCount = 0;
  double _purchaseTotal = 0;
  List<InventoryPurchaseRecordModel> _purchaseRecords = [];
  Map<String, int> _bigItemCounts = {};
  Map<String, int> _smallItemCounts = {};
  bool _analyticsLoading = false;
  /// 贡献储值金额汇总的储值记录，用于下钻
  List<StorageRecordModel> _contributingStorages = [];
  /// 按储值大项/小项分组的消费记录，用于下钻
  Map<String, List<ConsumptionRecordModel>> _bigItemConsumptions = {};
  Map<String, List<ConsumptionRecordModel>> _smallItemConsumptions = {};
  Map<int, StorageRecordModel> _consumptionStorageMap = {};
  Map<int, String> _consumptionSmallNames = {};

  /// 内存缓存：key 为 _rangeCacheKey(start,end)，切换回相同范围时直接使用
  final Map<String, _PeriodSummaryData> _summaryCache = {};
  /// 日历数据缓存：key 如 "week_2025-02-17" / "month_2025-02"
  final Map<String, _CachedCalendarData> _calendarCache = {};

  /// 月看板当前选择的月份（仅用 year/month）
  DateTime _calendarSelectedMonth = DateTime.now();
  bool _calendarLoading = false;
  Map<String, List<ConsumptionRecordModel>> _calendarByDay = {};
  Map<int, StorageRecordModel> _calendarStorageMap = {};
  Map<int, String> _calendarSmallNames = {};
  DateTime _calendarRangeStart = DateTime.now();
  DateTime _calendarRangeEnd = DateTime.now();

  bool _lastRouteCurrent = false;
  /// 从储值/消费详情返回时置为 true，避免被误判为「切换 TAB」而刷新导致滚动乱跳
  bool _returningFromDrillDown = false;
  /// 在非当前页时收到 notifyDataChanged，延后到重新成为当前页或下拉刷新时再刷新
  bool _pendingRefreshFromNotify = false;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _birthdaySectionKey = GlobalKey();
  bool _scrollHandled = false;

  @override
  void initState() {
    super.initState();
    final (s, e) = DateRangeHelper.thisWeek();
    _analyticsRangeStart = s;
    _analyticsRangeEnd = e;
    _tabController = TabController(length: 2, vsync: this);
    _refreshNotifier = context.read<DataRefreshNotifier>();
    _refreshNotifier.addListener(_onDataChanged);
    _load();
  }

  void _onDataChanged() {
    if (!mounted) return;
    // 若当前不在本页（例如用户在储值/消费详情页点了保存），不立即 _load()，避免日历被清空导致位置错乱；延后到重新成为当前页或下拉刷新时再刷新
    if (ModalRoute.of(context)?.isCurrent != true) {
      setState(() => _pendingRefreshFromNotify = true);
      return;
    }
    _load();
  }

  (DateTime, DateTime) _normalizeRange(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return (s, e);
  }

  void _setPresetRange(String preset) {
    final (s, e) = switch (preset) {
      '本周' => DateRangeHelper.thisWeek(),
      '本月' => DateRangeHelper.thisMonth(),
      '本季度' => DateRangeHelper.thisQuarter(),
      '本年' => DateRangeHelper.thisYear(),
      _ => (DateRangeHelper.thisWeek().$1, DateRangeHelper.thisWeek().$2),
    };
    setState(() {
      _analyticsRangeStart = s;
      _analyticsRangeEnd = e;
      _analyticsLoading = true;
    });
    _loadConsumptionAnalytics();
  }

  /// 判断当前选中范围是否匹配指定预设
  bool _isPresetSelected(String preset) {
    final (s, e) = switch (preset) {
      '本周' => DateRangeHelper.thisWeek(),
      '本月' => DateRangeHelper.thisMonth(),
      '本季度' => DateRangeHelper.thisQuarter(),
      '本年' => DateRangeHelper.thisYear(),
      _ => (DateRangeHelper.thisWeek().$1, DateRangeHelper.thisWeek().$2),
    };
    final (ns, ne) = _normalizeRange(s, e);
    final (cs, ce) = _normalizeRange(_analyticsRangeStart, _analyticsRangeEnd);
    return ns == cs && ne == ce;
  }

  void _applySummaryFromCache(_PeriodSummaryData data) {
    if (_selectedBigItemFilter != null && !data.byBigItem.containsKey(_selectedBigItemFilter)) {
      _selectedBigItemFilter = null;
    }
    final summary = _selectedBigItemFilter == null
        ? data.all
        : (data.byBigItem[_selectedBigItemFilter] ?? _CachedSummary(total: 0, count: 0, bigCounts: {}, smallCounts: {}));
    _consumptionTotal = summary.total;
    _consumptionCount = summary.count;
    _purchaseRecords = List.from(data.purchases);
    _purchaseTotal = _purchaseRecords.fold<double>(
      0,
      (sum, purchase) => sum + purchase.totalAmount,
    );
    _bigItemCounts = Map.from(summary.bigCounts);
    _smallItemCounts = Map.from(summary.smallCounts);
    _contributingStorages = summary.contributingStorages;
    _bigItemConsumptions = Map.from(summary.bigItemConsumptions);
    _smallItemConsumptions = Map.from(summary.smallItemConsumptions);
    _consumptionStorageMap = Map.from(data.consumptionStorageMap);
    _consumptionSmallNames = Map.from(data.consumptionSmallNames);
    final fromData = data.byBigItem.keys.toList();
    final restFromRepo = _allBigItemNamesFromRepo.where((n) => !data.byBigItem.containsKey(n)).toList();
    _bigItemFilterOptions = ['全部', '其他', ...fromData.where((n) => n != '其他'), ...restFromRepo];
  }

  Future<void> _loadConsumptionAnalytics() async {
    if (!mounted) return;
    final (start, end) = _normalizeRange(_analyticsRangeStart, _analyticsRangeEnd);
    final cacheKey = _rangeCacheKey(start, end);
    final cached = _summaryCache[cacheKey];
    if (cached != null) {
      setState(() {
        _applySummaryFromCache(cached);
        _analyticsLoading = false;
      });
      return;
    }

    final consumptionRepo = context.read<ConsumptionRepository>();
    final storageRepo = context.read<StorageRepository>();
    final smallItemRepo = context.read<StorageSmallItemRepository>();
    final purchaseRepo = context.read<InventoryPurchaseRepository>();

    try {
      var consumptions = await consumptionRepo.getByDateRange(start, end);
      final storageIds = consumptions.map((c) => c.storageRecordId).toSet().toList();
      final storageMap = <int, StorageRecordModel>{};
      for (final id in storageIds) {
        final s = await storageRepo.getById(id);
        if (s != null) storageMap[id] = s;
      }
      final smallOptions = await smallItemRepo.getAll();
      var smallIdToName = {for (var o in smallOptions) o.id: o.name};
      final email = context.read<AuthService>().user?.email;

      consumptions =
          DemoMode.filterConsumptions(email, consumptions, storageMap);
      storageMap.removeWhere(
          (_, s) => !DemoMode.includeForUser(email, DemoMode.isDemoStorage(s)));
      smallIdToName = DemoMode.filterSmallItemNames(email, smallIdToName);

      // 储值金额按「储值时间在本周期内」的储值记录统计
      var storagesInRange = await storageRepo.getByStorageDateRange(start, end);
      storagesInRange = DemoMode.filterStorages(email, storagesInRange);
      var purchasesInRange = await purchaseRepo.getByDateRange(start, end);
      purchasesInRange =
          DemoMode.filterInventoryPurchases(email, purchasesInRange);
      final double totalAll = storagesInRange.fold<double>(0, (sum, s) => sum + s.amount);

      final bigCountsAll = <String, int>{};
      final smallCountsAll = <String, int>{};
      final bigItemConsumptionsAll = <String, List<ConsumptionRecordModel>>{};
      final smallItemConsumptionsAll = <String, List<ConsumptionRecordModel>>{};
      for (final c in consumptions) {
        final storage = storageMap[c.storageRecordId];
        if (storage != null) {
          if (storage.storageBigItems.isEmpty) {
            const other = '其他';
            bigCountsAll[other] = (bigCountsAll[other] ?? 0) + 1;
            bigItemConsumptionsAll.putIfAbsent(other, () => []).add(c);
          } else {
            for (final name in storage.storageBigItems) {
              if (name.isNotEmpty) {
                bigCountsAll[name] = (bigCountsAll[name] ?? 0) + 1;
                bigItemConsumptionsAll.putIfAbsent(name, () => []).add(c);
              }
            }
          }
        }
        final ids = c.consumptionProjectIds.isNotEmpty
            ? c.consumptionProjectIds
            : (c.consumptionProjectId != null ? [c.consumptionProjectId!] : <int>[]);
        if (ids.isEmpty) {
          const smallName = '未分类';
          smallCountsAll[smallName] = (smallCountsAll[smallName] ?? 0) + 1;
          smallItemConsumptionsAll.putIfAbsent(smallName, () => []).add(c);
        } else {
          for (final id in ids) {
            final smallName = smallIdToName[id] ?? '未分类';
            smallCountsAll[smallName] = (smallCountsAll[smallName] ?? 0) + 1;
            smallItemConsumptionsAll.putIfAbsent(smallName, () => []).add(c);
          }
        }
      }

      final bigSortedAll = Map.fromEntries(
        bigCountsAll.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );
      final smallSortedAll = Map.fromEntries(
        smallCountsAll.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );
      final summaryAll = _CachedSummary(
        total: totalAll,
        count: consumptions.length,
        bigCounts: bigSortedAll,
        smallCounts: smallSortedAll,
        contributingStorages: storagesInRange,
        bigItemConsumptions: bigItemConsumptionsAll,
        smallItemConsumptions: smallItemConsumptionsAll,
      );

      // 按储值大项：金额取「储值时间在本周期内且属于该大项」的储值记录加总，笔数/次数仍按本周期消费；无大项归为【其他】
      final byBigItem = <String, _CachedSummary>{};
      final bigNamesForAmount = <String>{};
      for (final s in storagesInRange) {
        if (s.storageBigItems.isEmpty) {
          bigNamesForAmount.add('其他');
        } else {
          for (final n in s.storageBigItems) {
            if (n.isNotEmpty) bigNamesForAmount.add(n);
          }
        }
      }
      final allBigNames = <String>{...bigSortedAll.keys, ...bigNamesForAmount};
      for (final bigName in allBigNames) {
        final storagesForBig = bigName == '其他'
            ? storagesInRange.where((s) => s.storageBigItems.isEmpty).toList()
            : storagesInRange.where((s) => s.storageBigItems.contains(bigName)).toList();
        final amountTotal = storagesForBig
            .fold<double>(0, (sum, s) => sum + s.amount);
        final subset = consumptions.where((c) {
          final s = storageMap[c.storageRecordId];
          if (s == null) return false;
          return bigName == '其他'
              ? s.storageBigItems.isEmpty
              : s.storageBigItems.contains(bigName);
        }).toList();
        final bigCounts = <String, int>{};
        final smallCounts = <String, int>{};
        for (final c in subset) {
          final storage = storageMap[c.storageRecordId];
          if (storage != null) {
            for (final n in storage.storageBigItems) {
              if (n.isNotEmpty) bigCounts[n] = (bigCounts[n] ?? 0) + 1;
            }
          }
          final ids = c.consumptionProjectIds.isNotEmpty
              ? c.consumptionProjectIds
              : (c.consumptionProjectId != null ? [c.consumptionProjectId!] : <int>[]);
          if (ids.isEmpty) {
            const smallName = '未分类';
            smallCounts[smallName] = (smallCounts[smallName] ?? 0) + 1;
          } else {
            for (final id in ids) {
              final smallName = smallIdToName[id] ?? '未分类';
              smallCounts[smallName] = (smallCounts[smallName] ?? 0) + 1;
            }
          }
        }
        final bigItemConsums = <String, List<ConsumptionRecordModel>>{};
        for (final c in subset) {
          final st = storageMap[c.storageRecordId];
          if (st != null) {
            if (st.storageBigItems.isEmpty) {
              bigItemConsums.putIfAbsent('其他', () => []).add(c);
            } else {
              for (final n in st.storageBigItems) {
                if (n.isNotEmpty) bigItemConsums.putIfAbsent(n, () => []).add(c);
              }
            }
          }
        }
        final smallItemConsums = <String, List<ConsumptionRecordModel>>{};
        for (final c in subset) {
          final ids = c.consumptionProjectIds.isNotEmpty
              ? c.consumptionProjectIds
              : (c.consumptionProjectId != null ? [c.consumptionProjectId!] : <int>[]);
          if (ids.isEmpty) {
            smallItemConsums.putIfAbsent('未分类', () => []).add(c);
          } else {
            for (final id in ids) {
              final sn = smallIdToName[id] ?? '未分类';
              smallItemConsums.putIfAbsent(sn, () => []).add(c);
            }
          }
        }
        final bigS = Map.fromEntries(bigCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
        final smallS = Map.fromEntries(smallCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
        byBigItem[bigName] = _CachedSummary(
          total: amountTotal,
          count: subset.length,
          bigCounts: bigS,
          smallCounts: smallS,
          contributingStorages: storagesForBig,
          bigItemConsumptions: bigItemConsums,
          smallItemConsumptions: smallItemConsums,
        );
      }

      if (mounted) {
        final periodData = _PeriodSummaryData(
          all: summaryAll,
          byBigItem: byBigItem,
          purchases: purchasesInRange,
          consumptionStorageMap: storageMap,
          consumptionSmallNames: smallIdToName,
        );
        _summaryCache[cacheKey] = periodData;
        setState(() {
          _applySummaryFromCache(periodData);
          _analyticsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _consumptionTotal = 0;
          _consumptionCount = 0;
          _purchaseTotal = 0;
          _purchaseRecords = [];
          _bigItemCounts = {};
          _smallItemCounts = {};
          _contributingStorages = [];
          _bigItemConsumptions = {};
          _smallItemConsumptions = {};
          _consumptionStorageMap = {};
          _consumptionSmallNames = {};
          _bigItemFilterOptions = ['全部', '其他', ..._allBigItemNamesFromRepo];
          _analyticsLoading = false;
        });
      }
    }
  }

  void _showAmountDrillDown(BuildContext context) {
    if (_contributingStorages.isEmpty) return;
    _returningFromDrillDown = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '储值贡献明细',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '共 ${_contributingStorages.length} 条储值记录',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _contributingStorages.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final s = _contributingStorages[i];
                  final bigStr = s.storageBigItems.isEmpty ? '-' : s.storageBigItems.join('、');
                  return ListTile(
                    title: Text(s.customerName),
                    subtitle: Text(
                      '$bigStr · ${s.storageDate.year}-${s.storageDate.month.toString().padLeft(2, '0')}-${s.storageDate.day.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: Text(
                      '¥${s.amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _returningFromDrillDown = true);
                      context.push('/storage/${s.id}');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      // 仅当用户关闭 sheet 未导航时重置；若已 push 到详情页，保持 true 以便返回时不刷新
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        _returningFromDrillDown = false;
      }
    });
  }

  void _showPurchaseDrillDown(BuildContext context) {
    if (_purchaseRecords.isEmpty) return;
    _returningFromDrillDown = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('进货金额明细', style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '共 ${_purchaseRecords.length} 笔进货 · 合计 ¥${_purchaseTotal.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _purchaseRecords.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final purchase = _purchaseRecords[i];
                  final date = purchase.purchaseDate;
                  final bigItems = purchase.storageBigItems
                      .where((name) => name.isNotEmpty)
                      .toSet()
                      .join('、');
                  final quantity = purchase.quantities.fold<int>(
                    0,
                    (sum, item) => sum + item,
                  );
                  return ListTile(
                    title: Text(purchase.code),
                    subtitle: Text(
                      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
                      '${bigItems.isEmpty ? '' : ' · $bigItems'}'
                      '${quantity > 0 ? ' · $quantity 件' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: Text(
                      '¥${purchase.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() => _returningFromDrillDown = true);
                        this.context.push('/inventory/purchase/${purchase.id}/edit');
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      if (mounted && ModalRoute.of(this.context)?.isCurrent == true) {
        _returningFromDrillDown = false;
      }
    });
  }

  void _showConsumptionDrillDown(
    BuildContext context,
    String itemName,
    List<ConsumptionRecordModel> consumptions,
    bool isBigItem,
  ) {
    if (consumptions.isEmpty) return;
    _returningFromDrillDown = true;
    final title = isBigItem ? '储值大项【$itemName】消费明细' : '储值小项【$itemName】消费明细';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '共 ${consumptions.length} 笔消费',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: consumptions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final c = consumptions[i];
                  final storage = _consumptionStorageMap[c.storageRecordId];
                  final customerName = storage?.customerName ?? '-';
                  final ids = c.consumptionProjectIds.isNotEmpty
                      ? c.consumptionProjectIds
                      : (c.consumptionProjectId != null ? [c.consumptionProjectId!] : <int>[]);
                  final projectLabels = ids
                      .map((id) => _consumptionSmallNames[id] ?? '')
                      .where((n) => n.isNotEmpty)
                      .toList();
                  final projectStr = projectLabels.isNotEmpty ? projectLabels.join('、') : '消费';
                  return ListTile(
                    title: Text(customerName),
                    subtitle: Text(
                      '${c.consumptionDate.year}-${c.consumptionDate.month.toString().padLeft(2, '0')}-${c.consumptionDate.day.toString().padLeft(2, '0')} · $projectStr',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: const Icon(Icons.arrow_forward, size: 18),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _returningFromDrillDown = true);
                      context.push('/consumption/${c.id}/edit');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        _returningFromDrillDown = false;
      }
    });
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadCalendarData() async {
    if (!mounted) return;
    final start = DateTime(_calendarSelectedMonth.year, _calendarSelectedMonth.month, 1);
    final end = DateTime(_calendarSelectedMonth.year, _calendarSelectedMonth.month + 1, 0);
    final cacheKey = 'month_${start.year}-${start.month.toString().padLeft(2, '0')}';
    final cached = _calendarCache[cacheKey];
    if (cached != null) {
      setState(() {
        _calendarByDay = Map.from(cached.byDay);
        _calendarStorageMap = Map.from(cached.storageMap);
        _calendarSmallNames = Map.from(cached.smallNames);
        _calendarRangeStart = start;
        _calendarRangeEnd = end;
        _calendarLoading = false;
      });
      return;
    }

    setState(() => _calendarLoading = true);
    try {
      final consumptionRepo = context.read<ConsumptionRepository>();
      final storageRepo = context.read<StorageRepository>();
      final smallItemRepo = context.read<StorageSmallItemRepository>();
      var consumptions = await consumptionRepo.getByDateRange(start, end);
      final storageIds = consumptions.map((c) => c.storageRecordId).toSet().toList();
      final storageMap = <int, StorageRecordModel>{};
      for (final id in storageIds) {
        final s = await storageRepo.getById(id);
        if (s != null) storageMap[id] = s;
      }
      final smallOptions = await smallItemRepo.getAll();
      var smallNames = {for (var o in smallOptions) o.id: o.name};
      final email = context.read<AuthService>().user?.email;

      consumptions =
          DemoMode.filterConsumptions(email, consumptions, storageMap);
      storageMap.removeWhere(
          (_, s) => !DemoMode.includeForUser(email, DemoMode.isDemoStorage(s)));
      smallNames = DemoMode.filterSmallItemNames(email, smallNames);

      final byDay = <String, List<ConsumptionRecordModel>>{};
      for (final c in consumptions) {
        final key = _dayKey(c.consumptionDate);
        byDay.putIfAbsent(key, () => []).add(c);
      }
      for (final list in byDay.values) {
        list.sort((a, b) => a.consumptionDate.compareTo(b.consumptionDate));
      }

      if (mounted) {
        _calendarCache[cacheKey] = _CachedCalendarData(
          byDay: Map.from(byDay),
          storageMap: Map.from(storageMap),
          smallNames: Map.from(smallNames),
        );
        setState(() {
          _calendarByDay = byDay;
          _calendarStorageMap = storageMap;
          _calendarSmallNames = smallNames;
          _calendarRangeStart = start;
          _calendarRangeEnd = end;
          _calendarLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _calendarByDay = {};
          _calendarStorageMap = {};
          _calendarSmallNames = {};
          _calendarLoading = false;
        });
      }
    }
  }

  void _showDayDetailSheet(String dayKey, List<ConsumptionRecordModel> list) {
    final storageMap = _calendarStorageMap;
    final smallNames = _calendarSmallNames;
    final byStorage = <int, List<ConsumptionRecordModel>>{};
    for (final c in list) {
      byStorage.putIfAbsent(c.storageRecordId, () => []).add(c);
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) {
          final entries = byStorage.entries.toList();
          final children = <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '$dayKey 储值·消费',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
          ];

          for (final entry in entries) {
            final storageId = entry.key;
            final consumptions = entry.value;
            final storage = storageMap[storageId];
            final customerName = storage?.customerName ?? '-';
            final bigStr = storage?.storageBigItems.join('、') ?? '';
            final smallStr = (storage?.storageSmallItemIds
                    .map((id) => smallNames[id] ?? id.toString())
                    .join('、') ??
                '');

            children.add(
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ExpansionTile(
                  leading: const Icon(Icons.account_balance_wallet),
                  title: Text(
                    customerName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    [if (bigStr.isNotEmpty) bigStr, if (smallStr.isNotEmpty) smallStr]
                        .join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    '¥${storage?.amount.toStringAsFixed(0) ?? '-'} · ${consumptions.length}笔',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    textAlign: TextAlign.end,
                  ),
                  controlAffinity: ListTileControlAffinity.trailing,
                  children: [
                    ListTile(
                      dense: true,
                      title: const Text('查看储值详情', style: TextStyle(fontSize: 13)),
                      trailing: const Icon(Icons.arrow_forward, size: 18),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() => _returningFromDrillDown = true);
                          context.push('/storage/$storageId');
                        });
                      },
                    ),
                    ...consumptions.map((c) {
                      final ids = c.consumptionProjectIds.isNotEmpty
                          ? c.consumptionProjectIds
                          : (c.consumptionProjectId != null
                              ? [c.consumptionProjectId!]
                              : <int>[]);
                      final names = ids
                          .map((id) => smallNames[id] ?? '')
                          .where((n) => n.isNotEmpty)
                          .toList();
                      final projectLabel =
                          names.isNotEmpty ? names.join(' - ') : '';
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.receipt_long, size: 20),
                        title: Text(
                          projectLabel.isNotEmpty ? projectLabel : '消费',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: (c.remark ?? '').isNotEmpty
                            ? Text(
                                c.remark!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              )
                            : null,
                        trailing: const Icon(Icons.arrow_forward, size: 18),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() => _returningFromDrillDown = true);
                            context.push('/consumption/${c.id}/edit');
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
            );
          }

          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: 16),
            children: children,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _refreshNotifier.removeListener(_onDataChanged);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final cache = context.read<DataCache>();
    final preload = cache.get<_AnalyticsPreloadResult>(_kAnalyticsPreloadCacheKey);
    if (preload != null) {
      cache.remove(_kAnalyticsPreloadCacheKey);
      _summaryCache[preload.periodSummaryCacheKey] = preload.periodSummary;
      _calendarCache[preload.calendarCacheKey] = preload.calendarData;
      _analyticsRangeStart = preload.analyticsRangeStart;
      _analyticsRangeEnd = preload.analyticsRangeEnd;
      _calendarSelectedMonth = preload.calendarSelectedMonth;
      _customers = preload.customers;
      _depositByCustomer = preload.depositByCustomer;
      _birthdayThisWeek = preload.birthdayThisWeek;
      _birthdayThisMonth = preload.birthdayThisMonth;
      _allBigItemNamesFromRepo = preload.allBigItemNamesFromRepo;
      _applySummaryFromCache(preload.periodSummary);
      _calendarByDay = Map.from(preload.calendarData.byDay);
      _calendarStorageMap = Map.from(preload.calendarData.storageMap);
      _calendarSmallNames = Map.from(preload.calendarData.smallNames);
      _calendarRangeStart = preload.calendarSelectedMonth;
      _calendarRangeEnd = DateTime(preload.calendarSelectedMonth.year, preload.calendarSelectedMonth.month + 1, 0);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
          _analyticsLoading = false;
          _calendarLoading = false;
        });
      }
      return;
    }
    // 预加载失败时提示用户并支持手动重试
    final preloadFailed = cache.get<bool>('analytics_preload_failed') == true;
    if (preloadFailed) {
      cache.remove('analytics_preload_failed');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '预加载失败，请点击重试';
        });
      }
      return;
    }
    if (_loadInProgress) return;
    _loadInProgress = true;

    _summaryCache.clear();
    _calendarCache.clear();
    final customerRepo = context.read<CustomerRepository>();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final bigItemRepo = context.read<StorageBigItemRepository>();
      final email = context.read<AuthService>().user?.email;
      var customers =
          DemoMode.filterCustomers(email, await retryOnFailure(() => customerRepo.getAll()));
      final bigOptions = await bigItemRepo.getAll();
      final deposits = await Future.wait(
        customers.map((c) => customerRepo.getTotalDeposit(c.name)),
      );
      final depositByCustomer = {
        for (var i = 0; i < customers.length; i++) customers[i].name: deposits[i],
      };
      final sorted = customers.toList()
        ..sort((a, b) =>
            (depositByCustomer[b.name] ?? 0).compareTo(depositByCustomer[a.name] ?? 0));

      final now = DateTime.now();
      final weekStart = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 0);

      final birthdayThisWeek = <CustomerModel>[];
      final birthdayThisMonth = <CustomerModel>[];

      final lunarYear = _getCurrentLunarYear();
      for (final c in customers) {
        DateTime? checkDate;
        if (c.solarBirthday != null) {
          checkDate = DateTime(now.year, c.solarBirthday!.month, c.solarBirthday!.day);
        } else if (c.lunarBirthday != null) {
          final parsed = _parseLunarBirthday(c.lunarBirthday!);
          if (parsed != null) {
            final solar = LunarHelper.lunarToSolar(lunarYear, parsed.$1, parsed.$2);
            checkDate = solar;
          }
        }
        if (checkDate != null) {
          if (_isInRange(checkDate, weekStart, weekEnd)) {
            birthdayThisWeek.add(c);
          }
          if (_isInRange(checkDate, monthStart, monthEnd)) {
            birthdayThisMonth.add(c);
          }
        }
      }

      if (mounted) {
        setState(() {
          _customers = sorted;
          _depositByCustomer = depositByCustomer;
          _birthdayThisWeek = birthdayThisWeek;
          _birthdayThisMonth = birthdayThisMonth;
          _allBigItemNamesFromRepo = bigOptions.map((o) => o.name).toList();
          _loading = false;
        });
        await _loadConsumptionAnalytics();
        await _loadCalendarData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = toUserFriendlyError(e);
          _loading = false;
        });
      }
    } finally {
      _loadInProgress = false;
    }
  }

  int _getCurrentLunarYear() {
    try {
      final lunar = Solar.fromDate(DateTime.now()).getLunar();
      return lunar.getYear();
    } catch (_) {
      return DateTime.now().year;
    }
  }

  (int, int)? _parseLunarBirthday(String s) {
    final re = RegExp(r'(\d{1,4})年(?:闰)?(\d{1,2})月(\d{1,2})日');
    final m = re.firstMatch(s);
    if (m == null) return null;
    final month = int.tryParse(m.group(2) ?? '');
    final day = int.tryParse(m.group(3) ?? '');
    if (month == null || day == null) return null;
    return (month, day);
  }

  bool _isInRange(DateTime d, DateTime start, DateTime end) {
    final md = DateTime(DateTime.now().year, d.month, d.day);
    return !md.isBefore(start) && !md.isAfter(end);
  }

  /// 切换到本 TAB 时：有缓存则直接复用，无缓存才加载（避免下钻返回或切 TAB 时重复刷新）
  void _refreshWhenTabVisible() {
    if (!mounted) return;
    final cacheKey = _rangeCacheKey(_analyticsRangeStart, _analyticsRangeEnd);
    final cached = _summaryCache[cacheKey];
    if (cached != null) {
      setState(() {
        _applySummaryFromCache(cached);
        _analyticsLoading = false;
      });
      return;
    }
    setState(() => _analyticsLoading = true);
    _loadConsumptionAnalytics();
  }

  @override
  Widget build(BuildContext context) {
    final routeCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (routeCurrent && !_lastRouteCurrent) {
      _lastRouteCurrent = true;
      if (_returningFromDrillDown) {
        _returningFromDrillDown = false;
        // 下钻返回：不刷新，保持日历看板位置
      } else if (_pendingRefreshFromNotify) {
        _pendingRefreshFromNotify = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _lastRouteCurrent && !_returningFromDrillDown) _refreshWhenTabVisible();
        });
      }
    } else if (!routeCurrent) {
      _lastRouteCurrent = false;
    }

    if (_loading) {
      return const Center(child: FullPageLoadingPlaceholder());
    }
    _scrollToTargetIfNeeded();
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('周期汇总', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            // 第一级：全部 / 储值大项A / 储值大项B …
            Text('按储值大项', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: _selectedBigItemFilter == null,
                  onSelected: (_) {
                    if (_selectedBigItemFilter == null) return;
                    setState(() {
                      _selectedBigItemFilter = null;
                      final data = _summaryCache[_rangeCacheKey(_analyticsRangeStart, _analyticsRangeEnd)];
                      if (data != null) _applySummaryFromCache(data);
                    });
                  },
                ),
                ..._bigItemFilterOptions.where((s) => s != '全部').map((name) {
                  final cacheKey = _rangeCacheKey(_analyticsRangeStart, _analyticsRangeEnd);
                  final cached = _summaryCache[cacheKey];
                  final hasRecords = cached?.byBigItem.containsKey(name) ?? false;
                  if (!hasRecords) {
                    return ChoiceChip(
                      label: Text(name, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      selected: false,
                      side: BorderSide(color: Colors.grey[400]!),
                      backgroundColor: Colors.grey[200],
                      disabledColor: Colors.grey[200],
                      onSelected: (_) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('暂无该大项的记录')),
                        );
                      },
                    );
                  }
                  return ChoiceChip(
                    label: Text(name),
                    selected: _selectedBigItemFilter == name,
                    onSelected: (_) {
                      if (_selectedBigItemFilter == name) return;
                      setState(() {
                        _selectedBigItemFilter = name;
                        final data = _summaryCache[_rangeCacheKey(_analyticsRangeStart, _analyticsRangeEnd)];
                        if (data != null) _applySummaryFromCache(data);
                      });
                    },
                  );
                }),
              ],
            ),
            const SizedBox(height: 12),
            Text('时间范围', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month, size: 20),
                    label: Text(
                      '${_analyticsRangeStart.month}/${_analyticsRangeStart.day} - ${_analyticsRangeEnd.month}/${_analyticsRangeEnd.day}',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(now.year - 2),
                        lastDate: DateTime(now.year + 1),
                        initialDateRange: DateTimeRange(
                          start: _analyticsRangeStart,
                          end: _analyticsRangeEnd,
                        ),
                        helpText: '选择统计开始与结束日期',
                      );
                      if (picked == null || !mounted) return;
                      final (s, e) = _normalizeRange(picked.start, picked.end);
                      setState(() {
                        _analyticsRangeStart = s;
                        _analyticsRangeEnd = e;
                        _analyticsLoading = true;
                      });
                      _loadConsumptionAnalytics();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(selected: _isPresetSelected('本周'), label: const Text('本周'), onSelected: (_) => _setPresetRange('本周')),
                ChoiceChip(selected: _isPresetSelected('本月'), label: const Text('本月'), onSelected: (_) => _setPresetRange('本月')),
                ChoiceChip(selected: _isPresetSelected('本季度'), label: const Text('本季度'), onSelected: (_) => _setPresetRange('本季度')),
                ChoiceChip(selected: _isPresetSelected('本年'), label: const Text('本年'), onSelected: (_) => _setPresetRange('本年')),
              ],
            ),
            const SizedBox(height: 16),
            // 第三级：经营金额（储值、进货）+ 大项/小项消费次数
            Card(
              child: InkWell(
                onTap: _analyticsLoading || _contributingStorages.isEmpty
                    ? null
                    : () => _showAmountDrillDown(context),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '储值金额汇总',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (!_analyticsLoading && _contributingStorages.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _analyticsLoading
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                            )
                          : Text(
                              '¥${_consumptionTotal.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                      if (!_analyticsLoading)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _selectedBigItemFilter == null
                                ? '储值时间在本周期内的储值记录金额加总'
                                : '储值时间在本周期内且属【$_selectedBigItemFilter】的储值记录金额加总',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: InkWell(
                onTap: _analyticsLoading || _purchaseRecords.isEmpty
                    ? null
                    : () => _showPurchaseDrillDown(context),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('总进货', style: Theme.of(context).textTheme.titleMedium),
                          if (!_analyticsLoading && _purchaseRecords.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _analyticsLoading
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                            )
                          : Text(
                              '¥${_purchaseTotal.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.secondary,
                                  ),
                            ),
                      if (!_analyticsLoading)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${_purchaseRecords.length} 笔进货 · 按进货日期统计；补充入库无金额不计入，不受储值大项筛选影响',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '储值大项 · 消费次数',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _analyticsLoading
                        ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                        : _bigItemCounts.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('暂无', style: TextStyle(color: Colors.grey)),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _bigItemCounts.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final e = _bigItemCounts.entries.elementAt(i);
                              final consumptions = _bigItemConsumptions[e.key] ?? [];
                              return ListTile(
                                dense: true,
                                title: Text(e.key),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${e.value} 次',
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                    if (consumptions.isNotEmpty)
                                      Icon(Icons.chevron_right, size: 20, color: Colors.grey[600]),
                                  ],
                                ),
                                onTap: consumptions.isEmpty
                                    ? null
                                    : () => _showConsumptionDrillDown(context, e.key, consumptions, true),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '储值小项 · 消费次数',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _analyticsLoading
                        ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                        : _smallItemCounts.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('暂无', style: TextStyle(color: Colors.grey)),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _smallItemCounts.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final e = _smallItemCounts.entries.elementAt(i);
                              final consumptions = _smallItemConsumptions[e.key] ?? [];
                              return ListTile(
                                dense: true,
                                title: Text(e.key),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${e.value} 次',
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                    if (consumptions.isNotEmpty)
                                      Icon(Icons.chevron_right, size: 20, color: Colors.grey[600]),
                                  ],
                                ),
                                onTap: consumptions.isEmpty
                                    ? null
                                    : () => _showConsumptionDrillDown(context, e.key, consumptions, false),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('日历看板', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const SizedBox(height: 12),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      setState(() {
                        _calendarSelectedMonth = DateTime(
                          _calendarSelectedMonth.year,
                          _calendarSelectedMonth.month - 1,
                        );
                      });
                      _loadCalendarData();
                    },
                  ),
                  InkWell(
                    onTap: () async {
                      final result = await showDialog<DateTime>(
                        context: context,
                        builder: (ctx) => _MonthYearPickerDialog(
                          initialYear: _calendarSelectedMonth.year,
                          initialMonth: _calendarSelectedMonth.month,
                        ),
                      );
                      if (result == null || !mounted) return;
                      setState(() {
                        _calendarSelectedMonth = result;
                      });
                      _loadCalendarData();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_calendarSelectedMonth.year}年${_calendarSelectedMonth.month}月',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.calendar_today, size: 18, color: Colors.grey[600]),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      setState(() {
                        _calendarSelectedMonth = DateTime(
                          _calendarSelectedMonth.year,
                          _calendarSelectedMonth.month + 1,
                        );
                      });
                      _loadCalendarData();
                    },
                  ),
                ],
              ),
            const SizedBox(height: 12),
            _calendarLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _MonthCalendarGrid(
                        rangeStart: _calendarRangeStart,
                        rangeEnd: _calendarRangeEnd,
                        byDay: _calendarByDay,
                        storageMap: _calendarStorageMap,
                        smallNames: _calendarSmallNames,
                        onDayTap: _showDayDetailSheet,
                      ),
            const SizedBox(height: 24),
            Text('储值用户排行', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: _customers.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('暂无数据', style: TextStyle(color: Colors.grey[600])),
                            const SizedBox(height: 4),
                            Text(
                              '有客户储值后将在此显示排行',
                              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...List.generate(
                          _rankingExpanded ? _customers.length : _customers.length.clamp(0, 5),
                          (i) {
                            final c = _customers[i];
                            final amount = _depositByCustomer[c.name] ?? 0;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: CircleAvatar(child: Text('${i + 1}')),
                                  title: Text(c.name),
                                  subtitle: c.phone != null && c.phone!.isNotEmpty
                                      ? Text(c.phone!, style: TextStyle(fontSize: 12, color: Colors.grey[600]))
                                      : null,
                                  trailing: Text(
                                    '¥${amount.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  onTap: () => context.push('/customer/detail', extra: c.name),
                                ),
                                if (i < (_rankingExpanded ? _customers.length : 5) - 1)
                                  const Divider(height: 1),
                              ],
                            );
                          },
                        ),
                        if (_customers.length > 5)
                          InkWell(
                            onTap: () => setState(() => _rankingExpanded = !_rankingExpanded),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _rankingExpanded ? '收起' : '展开全部 (${_customers.length}人)',
                                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                                  ),
                                  Icon(
                                    _rankingExpanded ? Icons.expand_less : Icons.expand_more,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            KeyedSubtree(
              key: _birthdaySectionKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('近期生日提醒', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                        TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: '本周'),
                      Tab(text: '本月'),
                    ],
                  ),
                  SizedBox(
                    height: 280,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _BirthdayList(
                          customers: _birthdayThisWeek,
                          onTap: (c) => context.push('/customer/detail', extra: c.name),
                        ),
                        _BirthdayList(
                          customers: _birthdayThisMonth,
                          onTap: (c) => context.push('/customer/detail', extra: c.name),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToTargetIfNeeded() {
    if (_scrollHandled || widget.scrollTo == null || !mounted) return;
    final scrollTo = widget.scrollTo!;
    _scrollHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (scrollTo == 'top') {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else if (scrollTo == 'birthday') {
        final context = _birthdaySectionKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.1,
          );
        }
      }
    });
  }
}

String _dayKeyFromDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _MonthCalendarGrid extends StatelessWidget {
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final Map<String, List<ConsumptionRecordModel>> byDay;
  final Map<int, StorageRecordModel> storageMap;
  final Map<int, String> smallNames;
  final void Function(String dayKey, List<ConsumptionRecordModel> list) onDayTap;

  const _MonthCalendarGrid({
    required this.rangeStart,
    required this.rangeEnd,
    required this.byDay,
    required this.storageMap,
    required this.smallNames,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final firstWeekday = rangeStart.weekday;
    final daysInMonth = rangeEnd.day;
    final leadingEmpty = firstWeekday - 1;
    final totalCells = leadingEmpty + daysInMonth;
    final rowCount = (totalCells / 7).ceil();
    const weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

    final columnChildren = <Widget>[
      Row(
        children: List.generate(7, (int i) {
          return Expanded(
            child: Center(
              child: Text(
                weekLabels[i],
                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 8),
    ];

    for (var r = 0; r < rowCount; r++) {
      final cells = <Widget>[];
      for (var c = 0; c < 7; c++) {
        final cellIndex = r * 7 + c;
        if (cellIndex < leadingEmpty) {
          cells.add(Expanded(child: SizedBox(height: 52)));
          continue;
        }
        final day = cellIndex - leadingEmpty + 1;
        if (day > daysInMonth) {
          cells.add(Expanded(child: SizedBox(height: 52)));
          continue;
        }
        final d = DateTime(rangeStart.year, rangeStart.month, day);
        final key = _dayKeyFromDate(d);
        final list = byDay[key] ?? [];
        cells.add(Expanded(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: InkWell(
              onTap: list.isEmpty ? null : () => onDayTap(key, list),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 48,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$day', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    if (list.isNotEmpty)
                      Text('${list.length}笔', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
              ),
            ),
          ),
        ));
      }
      columnChildren.add(Row(children: cells));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: columnChildren,
        ),
      ),
    );
  }
}

class _BirthdayList extends StatelessWidget {
  final List<CustomerModel> customers;
  final void Function(CustomerModel) onTap;

  const _BirthdayList({required this.customers, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (customers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('暂无生日提醒', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(
              '有客户填写生日后将在此显示',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: customers.length,
      itemBuilder: (context, i) {
        final c = customers[i];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.cake)),
          title: Text(c.name),
          subtitle: Text(
            c.solarBirthday != null
                ? '公历 ${c.solarBirthday!.month}月${c.solarBirthday!.day}日'
                : (c.lunarBirthday ?? ''),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          trailing: const Icon(Icons.arrow_forward),
          onTap: () => onTap(c),
        );
      },
    );
  }
}

/// 仅选择年、月的弹窗（不选日）
class _MonthYearPickerDialog extends StatefulWidget {
  final int initialYear;
  final int initialMonth;

  const _MonthYearPickerDialog({
    required this.initialYear,
    required this.initialMonth,
  });

  @override
  State<_MonthYearPickerDialog> createState() => _MonthYearPickerDialogState();
}

class _MonthYearPickerDialogState extends State<_MonthYearPickerDialog> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
    _month = widget.initialMonth;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = List.generate(now.year + 2 - (now.year - 5), (i) => now.year - 5 + i);
    return AlertDialog(
      title: const Text('选择年月'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('年：'),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _year,
                  items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y年'))).toList(),
                  onChanged: (v) => setState(() => _year = v ?? _year),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('月：'),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _month,
                  items: List.generate(12, (i) => i + 1)
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m月'))).toList(),
                  onChanged: (v) => setState(() => _month = v ?? _month),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(DateTime(_year, _month)),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
