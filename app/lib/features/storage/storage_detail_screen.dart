import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/error_message.dart';
import '../../widgets/confirm_dialog.dart';
import '../../core/retry_helper.dart';
import '../../core/write_request_id.dart';
import '../../widgets/loading_placeholder.dart';
import '../../core/formula_helper.dart';
import '../customer/customer_repository.dart';
import '../consumption/consumption_model.dart';
import '../consumption/consumption_multi_add_sheet.dart';
import '../consumption/consumption_repository.dart';
import '../storage_options/storage_big_item_repository.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'storage_model.dart';
import 'storage_repository.dart';

class _StorageDetailCache {
  _StorageDetailCache({
    required this.storage,
    required this.consumptions,
    required this.smallItemNames,
    required this.remainingCount,
  });
  final StorageRecordModel storage;
  final List<ConsumptionRecordModel> consumptions;
  final Map<int, String> smallItemNames;
  final int remainingCount;
}

class StorageDetailScreen extends StatefulWidget {
  const StorageDetailScreen({super.key, required this.storageId});

  final int storageId;

  @override
  State<StorageDetailScreen> createState() => _StorageDetailScreenState();
}

class _StorageDetailScreenState extends State<StorageDetailScreen> {
  StorageRecordModel? _storage;
  List<ConsumptionRecordModel> _consumptions = [];
  Map<int, String> _smallItemNames = {};
  int _remainingCount = 0;
  bool _loading = true;
  String? _error;
  bool _loadInProgress = false;
  bool _batchWriteInProgress = false;
  String? _batchWriteRequestId;
  late final DataRefreshNotifier _refreshNotifier;

  String get _title {
    if (_storage == null) return '储值详情';
    final s = _storage!;
    final smallStr = s.storageSmallItemIds
        .map((id) => _smallItemNames[id] ?? id.toString())
        .join('、');
    return smallStr.isNotEmpty
        ? '${s.customerName} · $smallStr'
        : s.customerName;
  }

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

  static String _cacheKey(int id) => 'storage_detail_$id';

  Future<void> _load() async {
    if (!mounted) return;
    final id = widget.storageId;
    final cache = context.read<DataCache>();
    final revision = cache.revision;
    bool current() => mounted && cache.revision == revision;
    final cached = cache.get<_StorageDetailCache>(_cacheKey(id));
    if (cached != null) {
      setState(() {
        _storage = cached.storage;
        _consumptions = cached.consumptions;
        _smallItemNames = cached.smallItemNames;
        _remainingCount = cached.remainingCount;
        _loading = false;
        _error = null;
      });
      return;
    }
    if (_loadInProgress) return;
    _loadInProgress = true;

    final storageRepo = context.read<StorageRepository>();
    final consumptionRepo = context.read<ConsumptionRepository>();
    final smallItemRepo = context.read<StorageSmallItemRepository>();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await retryOnFailure(
        () => Future.wait([
          storageRepo.getById(id),
          consumptionRepo.getByStorage(id),
          smallItemRepo.getAll(),
        ]),
      );
      if (!current()) return;
      final storage = results[0] as StorageRecordModel?;
      if (storage == null) {
        if (mounted) context.pop();
        return;
      }
      final consumptions = results[1] as List<ConsumptionRecordModel>;
      final remaining = storage.totalCount - consumptions.length;
      final options = results[2] as List<StorageSmallItemOption>;
      final nameMap = {for (var o in options) o.id: o.name};

      if (current()) {
        cache.set(
          _cacheKey(id),
          _StorageDetailCache(
            storage: storage,
            consumptions: consumptions,
            smallItemNames: nameMap,
            remainingCount: remaining,
          ),
        );
        setState(() {
          _storage = storage;
          _consumptions = consumptions;
          _remainingCount = remaining;
          _smallItemNames = nameMap;
          _loading = false;
        });
      }
    } catch (e) {
      if (current()) {
        setState(() {
          _error = toUserFriendlyError(e);
          _loading = false;
        });
      }
    } finally {
      _loadInProgress = false;
      if (mounted && cache.revision != revision) _load();
    }
  }

  Future<void> _confirmDeleteConsumption(ConsumptionRecordModel c) async {
    final ok = await showConfirmDeleteDialog(
      context,
      title: '删除消费',
      content: '确定删除该消费记录吗？',
    );
    if (ok != true || !mounted) return;
    // 乐观更新：先从列表移除并更新剩余次数，再请求接口；失败时回滚
    final previousConsumptions = List<ConsumptionRecordModel>.from(
      _consumptions,
    );
    final previousRemaining = _remainingCount;
    setState(() {
      _consumptions = _consumptions.where((x) => x.id != c.id).toList();
      _remainingCount = _remainingCount + 1;
    });
    context.read<DataRefreshNotifier>().invalidateStorageAndConsumption();
    try {
      await context.read<ConsumptionRepository>().delete(c.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _consumptions = previousConsumptions;
          _remainingCount = previousRemaining;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：${toUserFriendlyError(e)}')),
        );
      }
    }
  }

  Future<void> _confirmDeleteStorage() async {
    if (_storage == null) return;
    final s = _storage!;
    final ok = await showConfirmDeleteDialog(
      context,
      title: '删除储值',
      content: '确定删除该储值记录吗？将同时删除其下所有消费记录，此操作不可恢复。',
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<StorageRepository>().deleteCascade(s.id);
      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateStorageAndConsumption();
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：${toUserFriendlyError(e)}')),
        );
      }
    }
  }

  Future<void> _updateStorage(StorageRecordModel updated) async {
    final repo = context.read<StorageRepository>();
    await repo.update(updated);
    if (mounted) {
      context.read<DataRefreshNotifier>().invalidateStorageAndConsumption();
      _load();
    }
  }

  Future<void> _showCustomerInfo() async {
    if (_storage == null) return;
    final customerRepo = context.read<CustomerRepository>();
    final customer = await customerRepo.getByName(_storage!.customerName);
    if (customer == null || !mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                customer.name,
                style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _InfoRow(label: '手机号', value: customer.phone ?? '-'),
              _InfoRow(label: '农历生日', value: customer.lunarBirthday ?? '-'),
              _InfoRow(
                label: '公历生日',
                value: customer.solarBirthday != null
                    ? '${customer.solarBirthday!.year}-${customer.solarBirthday!.month.toString().padLeft(2, '0')}-${customer.solarBirthday!.day.toString().padLeft(2, '0')}'
                    : '-',
              ),
              _InfoRow(label: '属相', value: customer.zodiac ?? '-'),
              _InfoRow(label: '年龄', value: customer.age?.toString() ?? '-'),
              _InfoRow(label: '住址', value: customer.address ?? '-'),
              _InfoRow(
                label: '生命密码',
                value: customer.lifeNumber?.toString() ?? '-',
              ),
              _InfoRow(label: '症状', value: customer.symptoms ?? '-'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('编辑客户信息'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await context.push('/customer/edit', extra: customer.name);
                    if (mounted) _load();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editBigItems() async {
    if (_storage == null) return;
    final s = _storage!;
    final bigRepo = context.read<StorageBigItemRepository>();
    List<StorageBigItemOption> options;
    try {
      options = await retryOnFailure(() => bigRepo.getAll());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(toUserFriendlyError(e))));
      }
      return;
    }
    if (!mounted) return;
    if (options.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无大项选项，请先在储值/库存管理中维护。')));
      return;
    }

    int? selectedId;
    if (s.storageBigItems.isNotEmpty) {
      final name = s.storageBigItems.first;
      for (final o in options) {
        if (o.name == name) {
          selectedId = o.id;
          break;
        }
      }
    }
    selectedId ??= options.first.id;

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑储值大项'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: options.map((opt) {
                final sel = selectedId == opt.id;
                return ChoiceChip(
                  label: Text(opt.name),
                  selected: sel,
                  onSelected: (_) => setDialogState(() => selectedId = opt.id),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selectedId),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    String? bigName;
    for (final o in options) {
      if (o.id == result) {
        bigName = o.name;
        break;
      }
    }
    if (bigName == null) return;
    await _updateStorage(
      StorageRecordModel(
        id: s.id,
        code: s.code,
        customerName: s.customerName,
        storageBigItems: [bigName],
        storageSmallItemIds: s.storageSmallItemIds,
        amount: s.amount,
        totalCount: s.totalCount,
        storageDate: s.storageDate,
        remark: s.remark,
      ),
    );
  }

  Future<void> _editSmallItems() async {
    if (_storage == null) return;
    final s = _storage!;
    final smallItemRepo = context.read<StorageSmallItemRepository>();
    var optionsList = <StorageSmallItemOption>[...await smallItemRepo.getAll()];
    var selectedIds = List<int>.from(s.storageSmallItemIds);
    final controller = TextEditingController();
    String search = '';

    final result = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = search.isEmpty
              ? optionsList
              : optionsList
                    .where(
                      (o) =>
                          o.name.toLowerCase().contains(search.toLowerCase()),
                    )
                    .toList();
          return AlertDialog(
            title: const Text('编辑储值小项'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: '输入搜索'),
                    onChanged: (v) => setDialogState(() => search = v),
                  ),
                  const SizedBox(height: 12),
                  ...filtered.map((opt) {
                    final sel = selectedIds.contains(opt.id);
                    return CheckboxListTile(
                      title: Text(opt.name),
                      value: sel,
                      onChanged: (v) {
                        setDialogState(() {
                          if (v == true)
                            selectedIds.add(opt.id);
                          else
                            selectedIds.remove(opt.id);
                        });
                      },
                    );
                  }),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text(
                      '创建选项',
                      style: TextStyle(color: Colors.blue),
                    ),
                    onTap: () async {
                      final name = await showDialog<String>(
                        context: ctx,
                        builder: (c) {
                          final tc = TextEditingController();
                          return AlertDialog(
                            title: const Text('新建储值小项'),
                            content: TextField(
                              controller: tc,
                              decoration: const InputDecoration(
                                labelText: '名称',
                              ),
                              autofocus: true,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(c, tc.text.trim()),
                                child: const Text('确定'),
                              ),
                            ],
                          );
                        },
                      );
                      if (name != null && name.isNotEmpty) {
                        final opt = await smallItemRepo.getOrCreate(name);
                        setDialogState(() {
                          selectedIds.add(opt.id);
                          optionsList.add(opt);
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, selectedIds),
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null && mounted) {
      await _updateStorage(
        StorageRecordModel(
          id: s.id,
          code: s.code,
          customerName: s.customerName,
          storageBigItems: s.storageBigItems,
          storageSmallItemIds: result,
          amount: s.amount,
          totalCount: s.totalCount,
          storageDate: s.storageDate,
          remark: s.remark,
        ),
      );
    }
  }

  Future<void> _editAmount() async {
    if (_storage == null) return;
    final s = _storage!;
    final controller = TextEditingController(text: s.amount.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑储值金额'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(
            labelText: '金额（元）',
            hintText: '支持公式，如 1000*0.8=',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v =
                  double.tryParse(controller.text) ??
                  tryParseFormula(controller.text);
              if (v != null && v >= 0) Navigator.pop(ctx, v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      await _updateStorage(
        StorageRecordModel(
          id: s.id,
          code: s.code,
          customerName: s.customerName,
          storageBigItems: s.storageBigItems,
          storageSmallItemIds: s.storageSmallItemIds,
          amount: result,
          totalCount: s.totalCount,
          storageDate: s.storageDate,
          remark: s.remark,
        ),
      );
    }
  }

  Future<void> _editTotalCount() async {
    if (_storage == null) return;
    final s = _storage!;
    final controller = TextEditingController(text: s.totalCount.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑总储值次数'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '总次数'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text);
              if (v != null && v >= 0) Navigator.pop(ctx, v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      await _updateStorage(
        StorageRecordModel(
          id: s.id,
          code: s.code,
          customerName: s.customerName,
          storageBigItems: s.storageBigItems,
          storageSmallItemIds: s.storageSmallItemIds,
          amount: s.amount,
          totalCount: result,
          storageDate: s.storageDate,
          remark: s.remark,
        ),
      );
    }
  }

  Future<void> _editStorageDate() async {
    if (_storage == null) return;
    final s = _storage!;
    final d = await showDatePicker(
      context: context,
      initialDate: s.storageDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('zh', 'CN'),
    );
    if (d != null && mounted) {
      await _updateStorage(
        StorageRecordModel(
          id: s.id,
          code: s.code,
          customerName: s.customerName,
          storageBigItems: s.storageBigItems,
          storageSmallItemIds: s.storageSmallItemIds,
          amount: s.amount,
          totalCount: s.totalCount,
          storageDate: d,
          remark: s.remark,
        ),
      );
    }
  }

  Future<void> _editRemark() async {
    if (_storage == null) return;
    final s = _storage!;
    final controller = TextEditingController(text: s.remark ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑备注'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '请输入备注信息'),
          maxLines: 3,
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
    if (result != null && mounted) {
      await _updateStorage(
        StorageRecordModel(
          id: s.id,
          code: s.code,
          customerName: s.customerName,
          storageBigItems: s.storageBigItems,
          storageSmallItemIds: s.storageSmallItemIds,
          amount: s.amount,
          totalCount: s.totalCount,
          storageDate: s.storageDate,
          remark: result.isEmpty ? null : result,
        ),
      );
    }
  }

  Future<void> _batchAddConsumption() async {
    if (_storage == null || _batchWriteInProgress) return;
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: '1');
        return AlertDialog(
          title: const Text('批量登记'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '仅填写数量，将按当前储值小项自动创建消费记录。',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '新增条数'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final v = int.tryParse(controller.text);
                if (v != null && v > 0) {
                  Navigator.pop(ctx, v);
                }
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (n == null || n < 1) return;

    if (_remainingCount < n) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('剩余消费次数不足，当前剩余 $_remainingCount 次')),
        );
      }
      return;
    }

    final consumptionRepo = context.read<ConsumptionRepository>();
    final smallItemIds = _storage!.storageSmallItemIds;
    final projectId = smallItemIds.isNotEmpty ? smallItemIds.first : null;

    _batchWriteInProgress = true;
    final requestId = _batchWriteRequestId ??= newWriteRequestId();
    try {
      for (var i = 0; i < n; i++) {
        await consumptionRepo.create(
          ConsumptionRecordModel(
            id: 0,
            code: '',
            consumptionDate: DateTime.now(),
            storageRecordId: widget.storageId,
            consumptionProjectId: projectId,
            consumptionProjectIds: projectId != null ? [projectId] : const [],
            clientRequestId: childWriteRequestId(requestId, i),
          ),
        );
      }

      _batchWriteRequestId = null;
      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateStorageAndConsumption();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已新增 $n 条消费记录')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(toUserFriendlyError(e))));
      }
    } finally {
      _batchWriteInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('储值详情')),
        body: const Center(child: FullPageLoadingPlaceholder()),
      );
    }
    if (_error != null || _storage == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('储值详情')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final s = _storage!;
    final smallItemStr = s.storageSmallItemIds
        .map((id) => _smallItemNames[id] ?? id.toString())
        .join('、');
    final dateStr =
        '${s.storageDate.year}-${s.storageDate.month.toString().padLeft(2, '0')}-${s.storageDate.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除储值',
            onPressed: () => _confirmDeleteStorage(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EditableField(
                      label: '客户',
                      value: s.customerName,
                      onTap: _showCustomerInfo,
                    ),
                    _EditableField(
                      label: '储值大项',
                      value: s.storageBigItems.join('、'),
                      onTap: _editBigItems,
                    ),
                    _EditableField(
                      label: '储值小项',
                      value: smallItemStr.isEmpty ? '-' : smallItemStr,
                      onTap: _editSmallItems,
                    ),
                    _EditableField(
                      label: '储值金额',
                      value: '¥${s.amount.toStringAsFixed(2)}',
                      onTap: _editAmount,
                    ),
                    _EditableField(
                      label: '总次数',
                      value: '${s.totalCount}',
                      onTap: _editTotalCount,
                    ),
                    _EditableField(
                      label: '剩余次数',
                      value: '$_remainingCount',
                      onTap: null,
                    ),
                    _EditableField(
                      label: '储值时间',
                      value: dateStr,
                      onTap: _editStorageDate,
                    ),
                    _EditableField(label: '储值编号', value: s.code, onTap: null),
                    _EditableField(
                      label: '备注',
                      value: (s.remark ?? '').isEmpty ? '-' : s.remark!,
                      onTap: _editRemark,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('新增消费'),
                onPressed: () async {
                  if (_remainingCount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('剩余消费次数不足，当前剩余 $_remainingCount 次'),
                      ),
                    );
                    return;
                  }
                  final result =
                      await showModalBottomSheet<List<ConsumptionRecordModel>>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (ctx) => FractionallySizedBox(
                          heightFactor: 0.9,
                          child: ConsumptionMultiAddSheet(
                            storage: s,
                            remainingCount: _remainingCount,
                          ),
                        ),
                      );
                  if (mounted && result != null && result.isNotEmpty) {
                    setState(() {
                      _consumptions = [...result, ..._consumptions];
                      _remainingCount = _remainingCount - result.length;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('批量登记（仅填数量）'),
                onPressed: _batchAddConsumption,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '消费记录 (${_consumptions.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._consumptions.map((c) {
              final ids = c.consumptionProjectIds.isNotEmpty
                  ? c.consumptionProjectIds
                  : (c.consumptionProjectId != null
                        ? [c.consumptionProjectId!]
                        : <int>[]);
              final names = ids
                  .map((id) => _smallItemNames[id] ?? '')
                  .where((n) => n.isNotEmpty)
                  .toList();
              final projectsLabel = names.isNotEmpty ? names.join(' - ') : '';
              final dateStr = c.consumptionDate.toString().split(' ')[0];
              final display = projectsLabel.isNotEmpty
                  ? '$projectsLabel · $dateStr'
                  : dateStr;
              return ListTile(
                title: Text(display),
                subtitle: (c.remark ?? '').isNotEmpty
                    ? Text(
                        c.remark ?? '',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: '删除',
                      onPressed: () => _confirmDeleteConsumption(c),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () async {
                        await context.push('/consumption/${c.id}/edit');
                        if (mounted) {
                          context
                              .read<DataRefreshNotifier>()
                              .invalidateStorageAndConsumption();
                          _load();
                        }
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '【$label】',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _EditableField({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '【$label】',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15))),
          if (onTap != null)
            Icon(Icons.edit, size: 16, color: Colors.grey[600]),
        ],
      ),
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: row,
      );
    }
    return row;
  }
}
