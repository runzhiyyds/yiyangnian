import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error_message.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_placeholder.dart';
import '../../core/retry_helper.dart';
import '../../core/data_refresh.dart';
import '../../core/demo_mode.dart';
import '../auth/auth_service.dart';
import '../storage_options/storage_big_item_repository.dart';
import '../storage_options/storage_small_item_repository.dart';
import '../storage/storage_repository.dart';
import '../storage/storage_model.dart';
import '../consumption/consumption_repository.dart';
import '../consumption/consumption_model.dart';
import 'inventory_models.dart';
import 'inventory_purchase_repository.dart';
import 'inventory_supp_in_repository.dart';
import 'inventory_consumption_repository.dart';
import 'inventory_movement.dart';
import 'widgets/inventory_linked_storages.dart';
import 'widgets/inventory_movement_timeline.dart';

class InventoryOptionsScreen extends StatefulWidget {
  const InventoryOptionsScreen({super.key});

  @override
  State<InventoryOptionsScreen> createState() => _InventoryOptionsScreenState();
}

class _InventoryOptionsScreenState extends State<InventoryOptionsScreen> {
  bool _loading = true;
  String? _error;
  List<StorageBigItemOption> _bigItems = [];
  List<StorageSmallItemOption> _smallItems = [];
  String _selectedBigName = '全部';
  int? _selectedSmallId;
  final _smallItemSearchController = TextEditingController();
  final Map<int, List<StorageRecordModel>> _storagesBySmallId = {};
  final Map<int, List<ConsumptionRecordModel>> _consumptionsBySmallId = {};
  final Map<int, int> _balanceBySmallItem = {};
  final Map<int, List<InventoryMovement>> _movementsBySmallId = {};
  late final DataRefreshNotifier _refreshNotifier;

  @override
  void initState() {
    super.initState();
    _refreshNotifier = context.read<DataRefreshNotifier>();
    _refreshNotifier.addListener(_onDataChanged);
    _load();
    _smallItemSearchController.addListener(() => setState(() {}));
  }

  void _onDataChanged() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    _refreshNotifier.removeListener(_onDataChanged);
    _smallItemSearchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bigRepo = context.read<StorageBigItemRepository>();
      final smallRepo = context.read<StorageSmallItemRepository>();
      final storageRepo = context.read<StorageRepository>();
      final consumptionRepo = context.read<ConsumptionRepository>();
      final purchaseRepo = context.read<InventoryPurchaseRepository>();
      final suppInRepo = context.read<InventorySuppInRepository>();
      final invConsumptionRepo = context.read<InventoryConsumptionRepository>();
      final results = await Future.wait([
        retryOnFailure(() => bigRepo.getAll()),
        retryOnFailure(() => smallRepo.getAll()),
        retryOnFailure(
          () => storageRepo.getByStorageDateRange(
            DateTime(2000),
            DateTime.now().add(const Duration(days: 3650)),
          ),
        ),
        retryOnFailure(
          () => consumptionRepo.getByDateRange(
            DateTime(2000),
            DateTime.now().add(const Duration(days: 3650)),
          ),
        ),
        retryOnFailure(() => purchaseRepo.getAll()),
        retryOnFailure(() => suppInRepo.getAll()),
        retryOnFailure(() => invConsumptionRepo.getAll()),
      ]);
      final big = results[0] as List<StorageBigItemOption>;
      final small = results[1] as List<StorageSmallItemOption>;
      final storages = results[2] as List<StorageRecordModel>;
      final consumptions = results[3] as List<ConsumptionRecordModel>;
      final purchases = results[4] as List<InventoryPurchaseRecordModel>;
      final allSuppIn = results[5] as List<InventorySuppInRecordModel>;
      final allInvConsumption =
          results[6] as List<InventoryConsumptionRecordModel>;
      if (!mounted) return;

      final email = context.read<AuthService>().user?.email;
      final scopedSmall = DemoMode.filterSmallItemOptions(email, small);
      final scopedStorages = DemoMode.filterStorages(email, storages);
      final storageMap = {for (final s in storages) s.id: s};
      final scopedConsumptions = DemoMode.filterConsumptions(
        email,
        consumptions,
        storageMap,
      );
      final scoped = DemoMode.scopeInventoryRaw(
        email: email,
        purchases: purchases,
        suppIn: allSuppIn,
        consumptions: allInvConsumption,
        smallOptions: small,
      );
      final scopedPurchases = scoped.purchases;
      final scopedSuppIn = scoped.suppIn;
      final scopedInvConsumption = scoped.consumptions;
      final sourceStorages = {
        for (final record in scopedStorages) record.id: record,
      };

      final balanceBySmallItem = DemoMode.computeInventoryBalances(
        purchases: scopedPurchases,
        suppIn: scopedSuppIn,
        consumptions: scopedInvConsumption,
        smallOptions: scopedSmall,
      );

      final movementsBySmallId = <int, List<InventoryMovement>>{
        for (final item in scopedSmall)
          item.id: InventoryMovementLedger.forItem(
            smallItemId: item.id,
            purchases: scopedPurchases,
            supplementaryIn: scopedSuppIn,
            outbound: scopedInvConsumption,
            sourceStorages: sourceStorages,
          ),
      };

      setState(() {
        _bigItems = big;
        _smallItems = scopedSmall;
        _balanceBySmallItem.clear();
        _balanceBySmallItem.addAll(balanceBySmallItem);
        _movementsBySmallId.clear();
        _movementsBySmallId.addAll(movementsBySmallId);
        _storagesBySmallId.clear();
        for (final s in scopedStorages) {
          for (final id in s.storageSmallItemIds) {
            _storagesBySmallId.putIfAbsent(id, () => []).add(s);
          }
        }
        _consumptionsBySmallId.clear();
        for (final c in scopedConsumptions) {
          final ids = c.consumptionProjectIds.isNotEmpty
              ? c.consumptionProjectIds
              : (c.consumptionProjectId != null
                    ? [c.consumptionProjectId!]
                    : <int>[]);
          for (final id in ids) {
            _consumptionsBySmallId.putIfAbsent(id, () => []).add(c);
          }
        }
        if (_selectedSmallId == null && _smallItems.isNotEmpty) {
          _selectedSmallId = _smallItems.first.id;
        } else if (_selectedSmallId != null &&
            !_smallItems.any((s) => s.id == _selectedSmallId)) {
          _selectedSmallId = _smallItems.isNotEmpty
              ? _smallItems.first.id
              : null;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = toUserFriendlyError(e);
      });
    }
  }

  int? _getSelectedBigItemId() {
    if (_selectedBigName == '全部' || _selectedBigName == '未归类') return null;
    try {
      return _bigItems.firstWhere((b) => b.name == _selectedBigName).id;
    } catch (_) {
      return null;
    }
  }

  int _countSmallItemsByBig(int? bigId) {
    return _smallItems.where((s) => s.storageBigItemId == bigId).length;
  }

  Future<void> _addSmallItem(String? selectedBigName) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          selectedBigName != null ? '新增小项（$selectedBigName）' : '新增小项',
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '小项名称',
            hintText: '请输入小项名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final repo = context.read<StorageSmallItemRepository>();
      final bigId = selectedBigName != null && selectedBigName != '未归类'
          ? _bigItems
                .cast<StorageBigItemOption?>()
                .firstWhere(
                  (x) => x?.name == selectedBigName,
                  orElse: () => null,
                )
                ?.id
          : null;
      await retryOnFailure(
        () => repo.getOrCreate(name, storageBigItemId: bigId),
      );
      if (!mounted) return;
      context.read<DataRefreshNotifier>().invalidateStorageOptions();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已新增小项「$name」')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('新增失败：${toUserFriendlyError(e)}')));
    }
  }

  Future<void> _assignBigItem(StorageSmallItemOption opt) async {
    final currentBigId = opt.storageBigItemId;
    final currentBigName = currentBigId == null
        ? '未归类'
        : _bigItems
                  .cast<StorageBigItemOption?>()
                  .firstWhere((x) => x?.id == currentBigId, orElse: () => null)
                  ?.name ??
              '未归类';
    int? selectedBigId = currentBigId;
    final result = await showDialog<Map<String, int?>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('归类大项'),
            content: SingleChildScrollView(
              child: RadioGroup<int?>(
                groupValue: selectedBigId,
                onChanged: (value) => setState(() => selectedBigId = value),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '小项「${opt.name}」当前归属：$currentBigName',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '选择目标大项：',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      dense: true,
                      title: const Text('未归类'),
                      leading: const Radio<int?>(value: null),
                      onTap: () => setState(() => selectedBigId = null),
                    ),
                    ..._bigItems.map(
                      (b) => ListTile(
                        dense: true,
                        title: Text(b.name),
                        leading: Radio<int?>(value: b.id),
                        onTap: () => setState(() => selectedBigId = b.id),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, {'bigId': selectedBigId}),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    if (!mounted) return;
    final newBigId = result['bigId'];
    if (newBigId == currentBigId) return;
    try {
      final repo = context.read<StorageSmallItemRepository>();
      await retryOnFailure(() => repo.updateBigItem(opt.id, newBigId));
      if (!mounted) return;
      context.read<DataRefreshNotifier>().invalidateStorageOptions();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已归类到${newBigId == null ? '未归类' : _bigItems.firstWhere((b) => b.id == newBigId).name}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('归类失败：${toUserFriendlyError(e)}')));
    }
  }

  Future<void> _renameSmallItem(StorageSmallItemOption opt) async {
    final controller = TextEditingController(text: opt.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名小项'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '小项名称',
            hintText: '请输入新的小项名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final repo = context.read<StorageSmallItemRepository>();
      await retryOnFailure(() => repo.update(opt.id, name));
      if (!mounted) return;
      context.read<DataRefreshNotifier>().invalidateStorageOptions();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重命名失败：${toUserFriendlyError(e)}')),
      );
    }
  }

  Future<void> _deleteSmallItem(StorageSmallItemOption opt) async {
    try {
      final relatedStorages = (_storagesBySmallId[opt.id] ?? const []).length;
      final relatedConsumptions =
          (_consumptionsBySmallId[opt.id] ?? const []).length;
      final relatedInventoryMovements =
          (_movementsBySmallId[opt.id] ?? const []).length;

      if (relatedStorages > 0 ||
          relatedConsumptions > 0 ||
          relatedInventoryMovements > 0) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('无法删除小项'),
            content: Text(
              '当前有 $relatedStorages 条储值记录、$relatedConsumptions 条消费记录、$relatedInventoryMovements 条库存变化与该小项关联。历史库存记录需要永久留痕，因此不能删除该小项。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
        return;
      }

      final ok = await showConfirmDeleteDialog(
        context,
        title: '删除小项',
        content: '确定删除小项「${opt.name}」吗？该操作不可恢复。',
      );
      if (ok != true || !mounted) return;

      final client = Supabase.instance.client; // 直接通过 supabase client 删除选项
      await client.from('storage_small_item_options').delete().eq('id', opt.id);
      if (!mounted) return;
      context.read<DataRefreshNotifier>().invalidateStorageOptions();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：${toUserFriendlyError(e)}')));
    }
  }

  Widget _buildSmallItemList(
    BuildContext context,
    List<StorageSmallItemOption> items, {
    required bool compact,
  }) {
    return ListView.builder(
      padding: compact
          ? const EdgeInsets.fromLTRB(16, 8, 16, 24)
          : const EdgeInsets.fromLTRB(12, 8, 4, 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = item.id == _selectedSmallId;
        final balance = _balanceBySmallItem[item.id] ?? 0;
        final storageCount = (_storagesBySmallId[item.id] ?? const []).length;
        final consumptionCount =
            (_consumptionsBySmallId[item.id] ?? const []).length;

        if (compact) {
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              minTileHeight: 64,
              title: Text(
                item.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '库存 $balance · 储值 $storageCount · 消费 $consumptionCount',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await context.push('/inventory/item/${item.id}');
                if (!context.mounted) return;
                context.read<DataRefreshNotifier>().invalidateInventory();
                await _load();
              },
            ),
          );
        }

        return InkWell(
          onTap: () => setState(() => _selectedSmallId = item.id),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 4),
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                Text(
                  '库$balance · 储$storageCount · 消$consumptionCount',
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInventoryContent(
    BuildContext context,
    List<StorageSmallItemOption> items,
    String selectedBig,
    BoxConstraints constraints,
  ) {
    final compact = constraints.maxWidth < 720;
    final addButton = Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(16, 12, 16, 8)
          : const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text('新增小项'),
        onPressed: () => _addSmallItem(selectedBig),
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          addButton,
          Expanded(child: _buildSmallItemList(context, items, compact: true)),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              addButton,
              const Divider(height: 1),
              Expanded(
                child: _buildSmallItemList(context, items, compact: false),
              ),
            ],
          ),
        ),
        Container(width: 1, color: Colors.grey[300]),
        Expanded(flex: 5, child: _buildLinkedDetailPane(context)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: FullPageLoadingPlaceholder()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    final selectedBig = _selectedBigName;
    final selectedBigId = _getSelectedBigItemId();
    final searchQuery = _smallItemSearchController.text.trim().toLowerCase();
    var smallInBig = selectedBig == '全部'
        ? _smallItems
        : _smallItems
              .where((s) => s.storageBigItemId == selectedBigId)
              .toList();
    if (searchQuery.isNotEmpty) {
      smallInBig = smallInBig
          .where((s) => s.name.toLowerCase().contains(searchQuery))
          .toList();
    }
    if (_selectedSmallId == null && smallInBig.isNotEmpty) {
      _selectedSmallId = smallInBig.first.id;
    } else if (_selectedSmallId != null &&
        !smallInBig.any((s) => s.id == _selectedSmallId)) {
      _selectedSmallId = smallInBig.isNotEmpty ? smallInBig.first.id : null;
    }

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedBig),
                  initialValue: selectedBig,
                  decoration: const InputDecoration(
                    labelText: '大项',
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '全部',
                      child: Text(
                        '全部 (${_smallItems.length})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ..._bigItems.map(
                      (b) => DropdownMenuItem(
                        value: b.name,
                        child: Text(
                          '${b.name} (${_countSmallItemsByBig(b.id)})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: '未归类',
                      child: Text(
                        '未归类 (${_countSmallItemsByBig(null)})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedBigName = v ?? '全部');
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _smallItemSearchController,
                  decoration: const InputDecoration(
                    labelText: '搜索小项',
                    hintText: '按名称搜索',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _smallItems.isEmpty
                ? EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: '暂无小项',
                    subtitle: '点击下方按钮新增小项，即可开始管理库存',
                    actionLabel: '新增小项',
                    onAction: () => _addSmallItem(selectedBig),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) => _buildInventoryContent(
                      context,
                      smallInBig,
                      selectedBig,
                      constraints,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _openSuppIn(int smallId, String smallItemName) {
    final uri = Uri(
      path: '/inventory/supp-in/new',
      queryParameters: {'item': smallId.toString(), 'name': smallItemName},
    );
    context.push(uri.toString()).then((_) {
      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateInventory();
        _load();
      }
    });
  }

  void _openSuppOut(int smallId, String smallItemName) {
    final uri = Uri(
      path: '/inventory/supp-out/new',
      queryParameters: {'item': smallId.toString(), 'name': smallItemName},
    );
    context.push(uri.toString()).then((_) {
      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateInventory();
        _load();
      }
    });
  }

  Widget _buildLinkedDetailPane(BuildContext context) {
    final smallId = _selectedSmallId;
    if (smallId == null) {
      return const Center(
        child: Text('请选择左侧的小项', style: TextStyle(fontSize: 13)),
      );
    }
    StorageSmallItemOption? opt;
    for (final x in _smallItems) {
      if (x.id == smallId) {
        opt = x;
        break;
      }
    }
    if (opt == null) {
      return const Center(
        child: Text('请选择左侧的小项', style: TextStyle(fontSize: 13)),
      );
    }
    final optVal = opt;
    final balance = _balanceBySmallItem[smallId] ?? 0;
    final storages = _storagesBySmallId[smallId] ?? const [];
    final consumptions = _consumptionsBySmallId[smallId] ?? const [];
    final movements = _movementsBySmallId[smallId] ?? const [];
    final bigName = optVal.storageBigItemId == null
        ? '未归类'
        : _bigItems
                  .cast<StorageBigItemOption?>()
                  .firstWhere(
                    (b) => b?.id == optVal.storageBigItemId,
                    orElse: () => null,
                  )
                  ?.name ??
              '未归类';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${optVal.name} · $bigName',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '库$balance  储${storages.length}  消${consumptions.length}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _openSuppIn(smallId, optVal.name),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_circle_outline, size: 18),
                        SizedBox(width: 6),
                        Text('补充入库', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _openSuppOut(smallId, optVal.name),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.remove_circle_outline, size: 18),
                        SizedBox(width: 6),
                        Text('出库', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _assignBigItem(optVal),
                    child: const Text('归类大项', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _renameSmallItem(optVal),
                    child: const Text('重命名', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: Colors.red,
                    ),
                    onPressed: () => _deleteSmallItem(optVal),
                    child: const Text('删除', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            children: [
              InventoryLinkedStorages(
                storages: storages,
                maxVisible: 5,
                onTap: (storage) => context
                    .push('/storage/${storage.id}')
                    .then((_) => mounted ? _load() : null),
                onViewAll: () => context
                    .push('/inventory/item/$smallId')
                    .then((_) => mounted ? _load() : null),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '库存变化记录',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context
                        .push('/inventory/item/$smallId')
                        .then((_) => mounted ? _load() : null),
                    child: const Text('查看全部'),
                  ),
                ],
              ),
              InventoryMovementTimeline(
                movements: movements.take(8).toList(),
                compact: true,
                onTap: (movement) => context
                    .push(movement.route)
                    .then((_) => mounted ? _load() : null),
                onOpenSourceStorage: (storageId) => context
                    .push('/storage/$storageId')
                    .then((_) => mounted ? _load() : null),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
