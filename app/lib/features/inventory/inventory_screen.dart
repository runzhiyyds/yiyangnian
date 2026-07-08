import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/demo_mode.dart';
import '../../widgets/loading_placeholder.dart';
import '../../core/error_message.dart';
import '../../core/retry_helper.dart';
import '../auth/auth_service.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'inventory_consumption_repository.dart';
import 'inventory_models.dart';
import 'inventory_purchase_repository.dart';
import 'inventory_supp_in_repository.dart';

const _cacheKeyPrefix = 'inventory_summary';

const _otherBigItem = '其他';
const _hasStock = '有库存';
const _noStock = '无库存';

class _InventorySummary {
  final Map<int, int> balanceBySmallItem;
  final Map<int, String> smallItemNames;
  final Map<int, String> smallItemToBigItem;

  _InventorySummary({
    required this.balanceBySmallItem,
    required this.smallItemNames,
    required this.smallItemToBigItem,
  });
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  _InventorySummary? _summary;
  bool _loading = true;
  String? _error;
  bool _loadInProgress = false;
  late final DataRefreshNotifier _refreshNotifier;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _refreshNotifier = context.read<DataRefreshNotifier>();
    _refreshNotifier.addListener(_onDataChanged);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _load();
  }

  void _onDataChanged() {
    if (mounted) {
      context.read<DataCache>().remove(_summaryCacheKey(context));
      _load();
    }
  }

  String _summaryCacheKey(BuildContext context) {
    final email = context.read<AuthService>().user?.email;
    return '${_cacheKeyPrefix}_${DemoMode.cacheSuffix(email)}';
  }

  @override
  void dispose() {
    _refreshNotifier.removeListener(_onDataChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cache = context.read<DataCache>();
    final cacheKey = _summaryCacheKey(context);
    final cached = cache.get<_InventorySummary>(cacheKey);
    if (cached != null) {
      setState(() {
        _summary = cached;
        _loading = false;
        _error = null;
      });
      return;
    }
    if (_loadInProgress) return;
    _loadInProgress = true;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final purchaseRepo = context.read<InventoryPurchaseRepository>();
      final suppInRepo = context.read<InventorySuppInRepository>();
      final consumptionRepo = context.read<InventoryConsumptionRepository>();
      final smallItemRepo = context.read<StorageSmallItemRepository>();

      final results = await Future.wait([
        retryOnFailure(() => purchaseRepo.getAll()),
        retryOnFailure(() => suppInRepo.getAll()),
        retryOnFailure(() => consumptionRepo.getAll()),
        retryOnFailure(() => smallItemRepo.getAll()),
      ]);

      final purchases = results[0] as List<InventoryPurchaseRecordModel>;
      final allSuppIn = results[1] as List<InventorySuppInRecordModel>;
      final allConsumption = results[2] as List<InventoryConsumptionRecordModel>;
      final smallOptions = results[3] as List<StorageSmallItemOption>;
      final email = context.read<AuthService>().user?.email;

      final scoped = DemoMode.scopeInventoryRaw(
        email: email,
        purchases: purchases,
        suppIn: allSuppIn,
        consumptions: allConsumption,
        smallOptions: smallOptions,
      );
      final balanceBySmallItem = DemoMode.computeInventoryBalances(
        purchases: scoped.purchases,
        suppIn: scoped.suppIn,
        consumptions: scoped.consumptions,
        smallOptions: scoped.smallOptions,
      );
      final smallItemNames = Map<int, String>.from(scoped.smallItemNames);
      final smallItemToBigItem = <int, String>{};

      for (var p in scoped.purchases) {
        for (var i = 0;
            i < p.storageSmallItemIds.length &&
                i < p.storageBigItems.length &&
                i < p.quantities.length;
            i++) {
          final id = p.storageSmallItemIds[i];
          if (id <= 0 || !smallItemNames.containsKey(id)) continue;
          smallItemToBigItem[id] = p.storageBigItems[i];
        }
      }
      for (var id in balanceBySmallItem.keys) {
        if (!smallItemNames.containsKey(id)) continue;
        smallItemToBigItem.putIfAbsent(id, () => _otherBigItem);
      }

      final visibleBalances = {
        for (final e in balanceBySmallItem.entries)
          if (smallItemNames.containsKey(e.key)) e.key: e.value,
      };

      final summary = _InventorySummary(
        balanceBySmallItem: visibleBalances,
        smallItemNames: smallItemNames,
        smallItemToBigItem: smallItemToBigItem,
      );

      if (mounted) {
        cache.set(cacheKey, summary);
        setState(() {
          _summary = summary;
          _loading = false;
        });
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

  bool _matchesSearch(int smallItemId, String bigItemName) {
    if (_searchQuery.isEmpty) return true;
    final smallName = _summary!.smallItemNames[smallItemId] ?? '';
    return smallName.toLowerCase().contains(_searchQuery) ||
        bigItemName.toLowerCase().contains(_searchQuery);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: FullPageLoadingPlaceholder());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error!,
                style: TextStyle(color: Colors.red[800], height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _load,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final summary = _summary!;
    final hasAnyData = summary.balanceBySmallItem.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索大项、小项',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.settings_suggest_outlined),
              title: const Text('储值大项 / 小项管理'),
              subtitle: const Text('查看关联储值和消费，支持新增、改名与安全删除'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => context.push('/inventory/options'),
            ),
          ),
        ),
        Expanded(
          child: !hasAnyData
              ? _buildEmptyState()
              : DefaultTabController(
                  length: 2,
                  initialIndex: 0,
                  child: Column(
                    children: [
                      TabBar(
                        labelColor: Theme.of(context).colorScheme.primary,
                        tabs: const [
                          Tab(text: _hasStock),
                          Tab(text: _noStock),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildStockLevelContent(summary, true),
                            _buildStockLevelContent(summary, false),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildStockLevelContent(_InventorySummary summary, bool hasStock) {
    final items = summary.balanceBySmallItem.entries
        .where((e) => hasStock ? e.value > 0 : e.value <= 0)
        .where((e) =>
            _matchesSearch(e.key, summary.smallItemToBigItem[e.key] ?? ''))
        .toList();
    if (items.isEmpty) {
      return Center(
        child: Text(
          hasStock ? '暂无有库存商品' : '暂无无库存商品',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }
    items.sort((a, b) {
      final bigA = summary.smallItemToBigItem[a.key] ?? '';
      final bigB = summary.smallItemToBigItem[b.key] ?? '';
      final cmp = bigA.compareTo(bigB);
      if (cmp != 0) return cmp;
      final nameA = summary.smallItemNames[a.key] ?? '';
      final nameB = summary.smallItemNames[b.key] ?? '';
      return nameA.compareTo(nameB);
    });
    return _buildGroupedList(summary, items, hasStock);
  }

  Widget _buildGroupedList(
      _InventorySummary summary, List<MapEntry<int, int>> items, bool hasStock) {
    final groups = <String, List<MapEntry<int, int>>>{};
    for (var e in items) {
      final big = summary.smallItemToBigItem[e.key] ?? _otherBigItem;
      groups.putIfAbsent(big, () => []).add(e);
    }
    final bigOrder = groups.keys.toList()
      ..sort((a, b) {
        if (a == _otherBigItem) return 1;
        if (b == _otherBigItem) return -1;
        return a.compareTo(b);
      });

    return RefreshIndicator(
      onRefresh: () async {
        final cache = context.read<DataCache>();
        cache.remove('${_cacheKeyPrefix}_demo');
        cache.remove('${_cacheKeyPrefix}_prod');
        await _load();
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        itemCount: bigOrder.fold<int>(
            0, (sum, big) => sum + 1 + (groups[big]?.length ?? 0)),
        itemBuilder: (context, index) {
          var current = 0;
          for (var big in bigOrder) {
            final groupItems = groups[big] ?? [];
            final headerIndex = current;
            final itemStart = current + 1;
            final itemEnd = current + 1 + groupItems.length;

            if (index == headerIndex) {
              return Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  big,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              );
            }
            if (index >= itemStart && index < itemEnd) {
              final e = groupItems[index - itemStart];
              return _buildItemTile(summary, e, hasStock);
            }
            current = itemEnd;
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildItemTile(
      _InventorySummary summary, MapEntry<int, int> e, bool hasStock) {
    final smallName = summary.smallItemNames[e.key] ?? '小项 ${e.key}';
    final qty = e.value;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(smallName),
        subtitle: qty > 0
            ? Text('当前库存：$qty', style: TextStyle(color: Colors.grey[600]))
            : Text('库存不足', style: TextStyle(color: Colors.orange[700])),
        trailing: qty > 0
            ? Text(
                '$qty',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              )
            : null,
        onTap: () => context.push('/inventory/item/${e.key}'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: () async {
        final cache = context.read<DataCache>();
        cache.remove('${_cacheKeyPrefix}_demo');
        cache.remove('${_cacheKeyPrefix}_prod');
        await _load();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height - 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  '暂无库存',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '点击右上角添加进货',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
