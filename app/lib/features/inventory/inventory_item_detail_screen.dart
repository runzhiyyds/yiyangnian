import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/demo_mode.dart';
import '../../core/error_message.dart';
import '../../core/retry_helper.dart';
import '../../widgets/loading_placeholder.dart';
import '../auth/auth_service.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'inventory_consumption_repository.dart';
import 'inventory_models.dart';
import 'inventory_movement.dart';
import 'inventory_purchase_repository.dart';
import 'inventory_supp_in_repository.dart';
import 'widgets/inventory_movement_timeline.dart';

class InventoryItemDetailScreen extends StatefulWidget {
  const InventoryItemDetailScreen({super.key, required this.smallItemId});

  final int smallItemId;

  @override
  State<InventoryItemDetailScreen> createState() =>
      _InventoryItemDetailScreenState();
}

class _InventoryItemDetailScreenState extends State<InventoryItemDetailScreen> {
  String _smallItemName = '';
  int _currentBalance = 0;
  List<InventoryMovement> _movements = const [];
  InventoryMovementFilter _filter = InventoryMovementFilter.all;
  bool _loading = true;
  String? _error;
  bool _loadInProgress = false;
  late final DataRefreshNotifier _refreshNotifier;

  @override
  void initState() {
    super.initState();
    _refreshNotifier = context.read<DataRefreshNotifier>();
    _refreshNotifier.addListener(_onDataChanged);
    _load();
  }

  void _onDataChanged() {
    if (!mounted) return;
    context.read<DataCache>().remove(_cacheKey(context));
    _load();
  }

  @override
  void dispose() {
    _refreshNotifier.removeListener(_onDataChanged);
    super.dispose();
  }

  String _cacheKey(BuildContext context) {
    final email = context.read<AuthService>().user?.email;
    return DemoMode.inventoryItemDetailCacheKey(email, widget.smallItemId);
  }

  Future<void> _load() async {
    final cache = context.read<DataCache>();
    final cacheKey = _cacheKey(context);
    final cached = cache.get<_ItemDetailCache>(cacheKey);
    if (cached != null) {
      setState(() {
        _smallItemName = cached.name;
        _currentBalance = cached.balance;
        _movements = cached.movements;
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
        retryOnFailure(() => suppInRepo.getBySmallItemId(widget.smallItemId)),
        retryOnFailure(
          () => consumptionRepo.getBySmallItemId(widget.smallItemId),
        ),
        retryOnFailure(() => smallItemRepo.getAll()),
      ]);
      if (!mounted) return;

      final purchases = results[0] as List<InventoryPurchaseRecordModel>;
      final supplementaryIn = results[1] as List<InventorySuppInRecordModel>;
      final outbound = results[2] as List<InventoryConsumptionRecordModel>;
      final smallOptions = results[3] as List<StorageSmallItemOption>;
      final email = context.read<AuthService>().user?.email;
      final name = smallOptions
          .firstWhere(
            (option) => option.id == widget.smallItemId,
            orElse: () => StorageSmallItemOption(
              id: widget.smallItemId,
              name: '小项${widget.smallItemId}',
            ),
          )
          .name;

      if (!DemoMode.smallItemVisibleToUser(email, name)) {
        setState(() {
          _smallItemName = name;
          _currentBalance = 0;
          _movements = const [];
          _loading = false;
          _error = '当前账号无法查看该小项数据';
        });
        return;
      }

      final scoped = DemoMode.scopeInventoryRaw(
        email: email,
        purchases: purchases,
        suppIn: supplementaryIn,
        consumptions: outbound,
        smallOptions: smallOptions,
      );
      final movements = InventoryMovementLedger.forItem(
        smallItemId: widget.smallItemId,
        purchases: scoped.purchases,
        supplementaryIn: scoped.suppIn,
        outbound: scoped.consumptions,
      );
      final balance = movements.isEmpty ? 0 : movements.first.balanceAfter;
      final cachedData = _ItemDetailCache(
        name: name,
        balance: balance,
        movements: movements,
      );
      cache.set(cacheKey, cachedData);
      setState(() {
        _smallItemName = name;
        _currentBalance = balance;
        _movements = movements;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = toUserFriendlyError(error);
          _loading = false;
        });
      }
    } finally {
      _loadInProgress = false;
    }
  }

  List<InventoryMovement> get _visibleMovements => switch (_filter) {
    InventoryMovementFilter.all => _movements,
    InventoryMovementFilter.inbound =>
      _movements.where((movement) => movement.delta > 0).toList(),
    InventoryMovementFilter.outbound =>
      _movements.where((movement) => movement.delta < 0).toList(),
  };

  Future<void> _openMovement(InventoryMovement movement) async {
    await context.push(movement.route);
    if (!mounted) return;
    context.read<DataCache>().remove(_cacheKey(context));
    context.read<DataRefreshNotifier>().invalidateInventory();
    await _load();
  }

  Future<void> _openNew(String path) async {
    final uri = Uri(
      path: path,
      queryParameters: {
        'item': widget.smallItemId.toString(),
        'name': _smallItemName,
      },
    );
    await context.push(uri.toString());
    if (!mounted) return;
    context.read<DataCache>().remove(_cacheKey(context));
    context.read<DataRefreshNotifier>().invalidateInventory();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: FullPageLoadingPlaceholder()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_smallItemName.isEmpty ? '库存详情' : _smallItemName),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_smallItemName),
        actions: [
          IconButton(
            tooltip: '补充入库',
            onPressed: () => _openNew('/inventory/supp-in/new'),
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: '出库',
            onPressed: () => _openNew('/inventory/supp-out/new'),
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<DataCache>().remove(_cacheKey(context));
          await _load();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前库存',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '由全部有效库存变化计算',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Text(
                      '$_currentBalance件',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '库存变化记录',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${_visibleMovements.length}条',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                _filterChip('全部', InventoryMovementFilter.all),
                _filterChip('增加', InventoryMovementFilter.inbound),
                _filterChip('减少', InventoryMovementFilter.outbound),
              ],
            ),
            const SizedBox(height: 10),
            InventoryMovementTimeline(
              movements: _visibleMovements,
              onTap: _openMovement,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, InventoryMovementFilter value) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }
}

class _ItemDetailCache {
  const _ItemDetailCache({
    required this.name,
    required this.balance,
    required this.movements,
  });

  final String name;
  final int balance;
  final List<InventoryMovement> movements;
}
