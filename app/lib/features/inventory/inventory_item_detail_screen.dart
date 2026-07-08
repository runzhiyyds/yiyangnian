import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/error_message.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_placeholder.dart';
import '../../core/retry_helper.dart';
import '../../core/demo_mode.dart';
import '../auth/auth_service.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'inventory_consumption_repository.dart';
import 'inventory_models.dart';
import 'inventory_purchase_repository.dart';
import 'inventory_supp_in_repository.dart';

/// 入库记录来源：进货单 或 补充入库
enum _InRecordSource { purchase, suppIn }

class _InRecord {
  _InRecordSource source;
  dynamic data; // InventoryPurchaseRecordModel 或 InventorySuppInRecordModel
  int smallItemId;
  int quantity;
  DateTime date;
  String? displayTitle;
  String? remark;

  _InRecord({
    required this.source,
    required this.data,
    required this.smallItemId,
    required this.quantity,
    required this.date,
    this.displayTitle,
    this.remark,
  });
}

class InventoryItemDetailScreen extends StatefulWidget {
  const InventoryItemDetailScreen({
    super.key,
    required this.smallItemId,
  });

  final int smallItemId;

  @override
  State<InventoryItemDetailScreen> createState() =>
      _InventoryItemDetailScreenState();
}

class _InventoryItemDetailScreenState extends State<InventoryItemDetailScreen> {
  String _smallItemName = '';
  int _currentBalance = 0;
  List<_InRecord> _inRecords = [];
  List<InventoryConsumptionRecordModel> _outRecords = [];
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
    if (mounted) _load();
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
        _inRecords = cached.inRecords;
        _outRecords = cached.outRecords;
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
        retryOnFailure(() => consumptionRepo.getBySmallItemId(widget.smallItemId)),
        retryOnFailure(() => smallItemRepo.getAll()),
      ]);

      final purchases = results[0] as List<InventoryPurchaseRecordModel>;
      final suppIns = results[1] as List<InventorySuppInRecordModel>;
      final consumptions = results[2] as List<InventoryConsumptionRecordModel>;
      final smallOptions = results[3] as List<StorageSmallItemOption>;
      final email = context.read<AuthService>().user?.email;

      final name = smallOptions
          .firstWhere((o) => o.id == widget.smallItemId,
              orElse: () => StorageSmallItemOption(
                  id: widget.smallItemId, name: '小项${widget.smallItemId}'))
          .name;

      if (!DemoMode.smallItemVisibleToUser(email, name)) {
        if (mounted) {
          setState(() {
            _smallItemName = name;
            _currentBalance = 0;
            _inRecords = [];
            _outRecords = [];
            _loading = false;
            _error = '当前账号无法查看该小项数据';
          });
        }
        return;
      }

      final scoped = DemoMode.scopeInventoryRaw(
        email: email,
        purchases: purchases,
        suppIn: suppIns,
        consumptions: consumptions,
        smallOptions: smallOptions,
      );

      final inRecords = <_InRecord>[];
      for (var p in scoped.purchases) {
        for (var i = 0;
            i < p.storageSmallItemIds.length &&
                i < p.storageBigItems.length &&
                i < p.quantities.length;
            i++) {
          if (p.storageSmallItemIds[i] == widget.smallItemId) {
            inRecords.add(_InRecord(
              source: _InRecordSource.purchase,
              data: p,
              smallItemId: widget.smallItemId,
              quantity: p.quantities[i],
              date: p.purchaseDate,
              displayTitle: '进货',
              remark: p.remark,
            ));
          }
        }
      }
      for (var r in scoped.suppIn) {
        inRecords.add(_InRecord(
          source: _InRecordSource.suppIn,
          data: r,
          smallItemId: r.storageSmallItemId,
          quantity: r.quantity,
          date: r.supplementDate,
          displayTitle: '补充入库',
          remark: r.remark,
        ));
      }
      inRecords.sort((a, b) => b.date.compareTo(a.date));

      var balance = 0;
      for (var r in inRecords) {
        balance += r.quantity;
      }
      for (var r in scoped.consumptions) {
        balance -= r.quantity;
      }

      final scopedOutRecords = scoped.consumptions;

      final cachedData = _ItemDetailCache(
        name: name,
        balance: balance,
        inRecords: inRecords,
        outRecords: scopedOutRecords,
      );

      if (mounted) {
        cache.set(cacheKey, cachedData);
        setState(() {
          _smallItemName = name;
          _currentBalance = balance;
          _inRecords = inRecords;
          _outRecords = scopedOutRecords;
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

  Future<void> _confirmDeleteSuppIn(InventorySuppInRecordModel r) async {
    final ok = await showConfirmDeleteDialog(
      context,
      title: '删除补充入库',
      content: '确定删除该补充入库记录吗？',
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<InventorySuppInRepository>().delete(r.id);
      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateInventory();
        context.read<DataCache>().remove(_cacheKey(context));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：${toUserFriendlyError(e)}')),
        );
      }
    }
  }

  Future<void> _confirmDeletePurchase(InventoryPurchaseRecordModel p) async {
    final ok = await showConfirmDeleteDialog(
      context,
      title: '删除进货记录',
      content: '确定删除该进货记录吗？删除后该进货单中所有商品的数量将从库存中扣除。',
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<InventoryPurchaseRepository>().delete(p.id);
      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateInventory();
        context.read<DataCache>().remove(_cacheKey(context));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：${toUserFriendlyError(e)}')),
        );
      }
    }
  }

  Future<void> _confirmDeleteConsumption(InventoryConsumptionRecordModel r) async {
    final src = r.sourceStorageRecordId;
    final title = src != null ? '撤销出库（回退库存）' : '删除出库记录';
    final content = src != null
        ? '该条为新建储值时的自动出库。删除后本小项库存将增加 ${r.quantity}，客户名下的储值记录不会自动删除。'
        : '确定删除该出库记录吗？删除后库存将增加 ${r.quantity}。';
    final ok = await showConfirmDeleteDialog(
      context,
      title: title,
      content: content,
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<InventoryConsumptionRepository>().delete(r.id);
      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateInventory();
        context.read<DataCache>().remove(_cacheKey(context));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：${toUserFriendlyError(e)}')),
        );
      }
    }
  }

  String _formatOutDate(InventoryConsumptionRecordModel r) =>
      '${r.consumptionDate.year}-${r.consumptionDate.month.toString().padLeft(2, '0')}-${r.consumptionDate.day.toString().padLeft(2, '0')}';

  static final _remarkStripAutoPrefix = RegExp(r'^储值出库\s+\S+\s+');

  String _compactOutboundRemark(String? remark) {
    if (remark == null || remark.trim().isEmpty) return '';
    var s = remark.trim();
    s = s.replaceFirst(_remarkStripAutoPrefix, '');
    if (s.startsWith('自动出库 ·')) {
      s = s.substring('自动出库 ·'.length).trim();
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: FullPageLoadingPlaceholder()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('库存详情')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error!, style: TextStyle(color: Colors.red[800])),
                const SizedBox(height: 20),
                FilledButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_smallItemName),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('补充入库'),
            onPressed: () {
              final uri = Uri(path: '/inventory/supp-in/new', queryParameters: {'item': widget.smallItemId.toString(), 'name': _smallItemName});
              context.push(uri.toString());
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.remove),
            label: const Text('出库'),
            onPressed: () {
              final uri = Uri(path: '/inventory/supp-out/new', queryParameters: {'item': widget.smallItemId.toString(), 'name': _smallItemName});
              context.push(uri.toString());
            },
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
                    Text('当前库存', style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '$_currentBalance',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('入库记录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._inRecords.map((r) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(r.displayTitle ?? '入库'),
                    subtitle: Text(
                      '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')} · 数量 ${r.quantity}${r.remark != null && r.remark!.isNotEmpty ? ' · ${r.remark}' : ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('+${r.quantity}', style: TextStyle(color: Colors.green[700])),
                        if (r.source == _InRecordSource.suppIn)
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => context.push('/inventory/supp-in/${r.data.id}/edit'),
                          ),
                        if (r.source == _InRecordSource.suppIn)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _confirmDeleteSuppIn(r.data),
                          ),
                        if (r.source == _InRecordSource.purchase) ...[
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => context.push('/inventory/purchase/${r.data.id}/edit'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _confirmDeletePurchase(r.data),
                          ),
                        ],
                      ],
                    ),
                  ),
                )),
            const SizedBox(height: 24),
            Text('出库记录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._outRecords.map((r) {
              final src = r.sourceStorageRecordId;
              final extra = _compactOutboundRemark(r.remark);
              final subtitleText = extra.isEmpty
                  ? '数量 ${r.quantity} · ${src != null ? '自动' : '手工'}'
                  : '数量 ${r.quantity} · ${src != null ? '自动' : '手工'} · $extra';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(_formatOutDate(r)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(subtitleText),
                      if (src != null)
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => context.push('/storage/$src'),
                          child: const Text('关联储值'),
                        ),
                    ],
                  ),
                  isThreeLine: src != null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('-${r.quantity}', style: TextStyle(color: Colors.orange[700])),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => context.push('/inventory/supp-out/${r.id}/edit'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: src != null ? '撤销出库' : '删除',
                        onPressed: () => _confirmDeleteConsumption(r),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ItemDetailCache {
  _ItemDetailCache({
    required this.name,
    required this.balance,
    required this.inRecords,
    required this.outRecords,
  });
  final String name;
  final int balance;
  final List<_InRecord> inRecords;
  final List<InventoryConsumptionRecordModel> outRecords;
}
