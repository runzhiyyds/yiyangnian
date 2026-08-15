import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/error_message.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_placeholder.dart';
import '../../core/retry_helper.dart';
import 'customer_model.dart';
import 'customer_repository.dart';
import '../storage/storage_model.dart';
import '../storage/storage_repository.dart';
import '../storage_options/storage_small_item_repository.dart';
import '../consumption/consumption_edit_screen.dart';
import '../consumption/consumption_model.dart';
import '../consumption/consumption_repository.dart';

class _CustomerDetailCache {
  _CustomerDetailCache({
    required this.customer,
    required this.storages,
    required this.smallItemNames,
    required this.totalDeposit,
    required this.earliestStorageDate,
    required this.totalRemaining,
    required this.storageCodes,
    required this.consumptionsByStorage,
  });
  final CustomerModel customer;
  final List<StorageRecordModel> storages;
  final Map<int, String> smallItemNames;
  final double totalDeposit;
  final DateTime? earliestStorageDate;
  final int totalRemaining;
  final List<String> storageCodes;
  final Map<int, List<ConsumptionRecordModel>> consumptionsByStorage;
}

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerName});

  final String customerName;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  CustomerModel? _customer;
  List<StorageRecordModel> _storages = [];
  Map<int, String> _smallItemNames = {};
  /// 当前选中的储值 ID（用于右侧消费列表），默认选中最新一条
  int? _selectedStorageId;
  /// 当前客户下各储值对应的消费记录（按储值 ID 聚合）
  final Map<int, List<ConsumptionRecordModel>> _consumptionsByStorage = {};
  double _totalDeposit = 0;
  DateTime? _earliestStorageDate;
  int _totalRemaining = 0;
  List<String> _storageCodes = [];
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

  static String _cacheKey(String name) => 'customer_detail_$name';

  Future<void> _load() async {
    if (!mounted) return;
    final name = widget.customerName;
    final cache = context.read<DataCache>();
    final cached = cache.get<_CustomerDetailCache>(_cacheKey(name));
    if (cached != null) {
      setState(() {
        _customer = cached.customer;
        _storages = cached.storages;
        _smallItemNames = cached.smallItemNames;
        _totalDeposit = cached.totalDeposit;
        _earliestStorageDate = cached.earliestStorageDate;
        _totalRemaining = cached.totalRemaining;
        _storageCodes = cached.storageCodes;
        _consumptionsByStorage.clear();
        _consumptionsByStorage.addAll(cached.consumptionsByStorage);
        _loading = false;
        _error = null;
      });
      return;
    }
    if (_loadInProgress) return;
    _loadInProgress = true;

    final customerRepo = context.read<CustomerRepository>();
    final storageRepo = context.read<StorageRepository>();
    final smallItemRepo = context.read<StorageSmallItemRepository>();
    final consumptionRepo = context.read<ConsumptionRepository>();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await retryOnFailure(() => Future.wait([
        customerRepo.getByName(name),
        storageRepo.getByCustomer(name),
        smallItemRepo.getAll(),
        customerRepo.getTotalDeposit(name),
        customerRepo.getEarliestStorageDate(name),
        customerRepo.getTotalRemainingConsumption(name),
        customerRepo.getStorageCodes(name),
      ]));
      final customer = results[0] as CustomerModel?;
      if (customer == null) {
        if (mounted) context.pop();
        return;
      }
      final storages = results[1] as List<StorageRecordModel>;
      final options = results[2] as List;
      final totalDeposit = results[3] as double;
      final earliest = results[4] as DateTime?;
      final totalRemaining = results[5] as int;
      final codes = results[6] as List<String>;
      final opts = options as List<StorageSmallItemOption>;
      final nameMap = {for (var o in opts) o.id: o.name};

      if (mounted) {
        // 加载每条储值对应的消费记录，用于右侧列表
        _consumptionsByStorage.clear();
        for (final s in storages) {
          final list = await consumptionRepo.getByStorage(s.id);
          _consumptionsByStorage[s.id] = list;
        }

        cache.set(
          _cacheKey(name),
          _CustomerDetailCache(
            customer: customer,
            storages: storages,
            smallItemNames: nameMap,
            totalDeposit: totalDeposit,
            earliestStorageDate: earliest,
            totalRemaining: totalRemaining,
            storageCodes: codes,
            consumptionsByStorage: Map.fromEntries(
              _consumptionsByStorage.entries.map((e) => MapEntry(e.key, List.from(e.value)))),
          ),
        );
        setState(() {
          _customer = customer;
          _storages = storages;
          _smallItemNames = nameMap;
          _totalDeposit = totalDeposit;
          _earliestStorageDate = earliest;
          _totalRemaining = totalRemaining;
          _storageCodes = codes;
          if (_storages.isNotEmpty) {
            // 默认选中最新一条（假设列表已按时间倒序）
            _selectedStorageId = _storages.first.id;
          } else {
            _selectedStorageId = null;
          }
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

  int _remainingForStorage(StorageRecordModel s) {
    final consumed = (_consumptionsByStorage[s.id] ?? []).length;
    return (s.totalCount - consumed).clamp(0, s.totalCount);
  }

  void _showConsumptionDetailDialog(BuildContext context, ConsumptionRecordModel c) {
    final dateStr =
        '${c.consumptionDate.year}-${c.consumptionDate.month.toString().padLeft(2, '0')}-${c.consumptionDate.day.toString().padLeft(2, '0')}';
    final projectIds = c.consumptionProjectIds.isNotEmpty
        ? c.consumptionProjectIds
        : (c.consumptionProjectId != null ? [c.consumptionProjectId!] : <int>[]);
    final names = projectIds
        .map((id) => _smallItemNames[id] ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final projectLabel = names.isNotEmpty ? names.join('、') : '消费';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c.code.isNotEmpty ? c.code : '消费记录'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StorageDetailRow(label: '消费项目', value: projectLabel),
              _StorageDetailRow(label: '消费日期', value: dateStr),
              if (c.remark != null && c.remark!.isNotEmpty)
                _StorageDetailRow(label: '备注', value: c.remark!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.push('/consumption/${c.id}/edit');
              if (mounted) _load();
            },
            child: const Text('查看详情'),
          ),
        ],
      ),
    );
  }

  void _showStorageDetailDialog(BuildContext context, StorageRecordModel s) {
    final bigStr = s.storageBigItems.join('、');
    final smallStr = s.storageSmallItemIds
        .map((id) => _smallItemNames[id] ?? id.toString())
        .join('、');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.code),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bigStr.isNotEmpty) _StorageDetailRow(label: '大项', value: bigStr),
              if (smallStr.isNotEmpty) _StorageDetailRow(label: '小项', value: smallStr),
              _StorageDetailRow(label: '金额', value: '¥${s.amount.toStringAsFixed(2)}'),
              _StorageDetailRow(label: '总次数', value: '${s.totalCount}'),
              _StorageDetailRow(label: '剩余次数', value: '${_remainingForStorage(s)}'),
              _StorageDetailRow(
                label: '储值日期',
                value: '${s.storageDate.year}-${s.storageDate.month.toString().padLeft(2, '0')}-${s.storageDate.day.toString().padLeft(2, '0')}',
              ),
              if ((s.remark ?? '').isNotEmpty) _StorageDetailRow(label: '备注', value: s.remark!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.push('/storage/${s.id}');
              if (mounted) _load();
            },
            child: const Text('查看详情'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteStorage(StorageRecordModel s) async {
    final ok = await showConfirmDeleteDialog(
      context,
      title: '删除储值',
      content: '确定删除该储值记录吗？将同时删除其下所有消费记录。',
    );
    if (ok != true || !mounted) return;
    // 乐观更新：先从列表移除，再请求接口；失败时回滚
    final previousStorages = List<StorageRecordModel>.from(_storages);
    setState(() {
      _storages = _storages.where((x) => x.id != s.id).toList();
    });
    context.read<DataRefreshNotifier>().invalidateStorageAndConsumption();
    try {
      await context.read<StorageRepository>().deleteCascade(s.id);
      if (mounted) _load(); // 刷新汇总等
    } catch (e) {
      if (mounted) {
        setState(() => _storages = previousStorages);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：${toUserFriendlyError(e)}')),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final c = _customer;
    if (c == null) return;
    final ok = await showConfirmDeleteDialog(
      context,
      title: '删除客户',
      content: '确定删除客户「${c.name}」吗？将同时删除其下所有储值记录及消费记录，此操作不可恢复。',
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<CustomerRepository>().deleteCascade(c.name);
      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateCustomerAndTree();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.customerName)),
        body: const Center(child: FullPageLoadingPlaceholder()),
      );
    }
    if (_error != null || _customer == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.customerName)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  _load();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final c = _customer!;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: Text(c.name),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: '编辑客户',
                  onPressed: () async {
                    await context.push('/customer/edit', extra: c.name);
                    if (mounted) _load();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除客户',
                  onPressed: () => _confirmDelete(context),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoCard(
                      title: '基本信息',
                      children: [
                        _InfoRow(label: '手机号', value: c.phone ?? '-'),
                        _InfoRow(label: '农历生日', value: c.lunarBirthday ?? '-'),
                        _InfoRow(
                          label: '公历生日',
                          value: c.solarBirthday != null
                              ? '${c.solarBirthday!.year}-${c.solarBirthday!.month.toString().padLeft(2, '0')}-${c.solarBirthday!.day.toString().padLeft(2, '0')}'
                              : '-',
                        ),
                        _InfoRow(label: '属相', value: c.zodiac ?? '-'),
                        _InfoRow(label: '年龄', value: c.age?.toString() ?? '-'),
                        _InfoRow(label: '住址', value: c.address ?? '-'),
                        _InfoRow(label: '生命密码', value: c.lifeNumber?.toString() ?? '-'),
                        _InfoRow(label: '症状', value: c.symptoms ?? '-'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoCard(
                      title: '储值汇总',
                      children: [
                        _InfoRow(
                            label: '累计储值',
                            value: '¥${_totalDeposit.toStringAsFixed(2)}'),
                        _InfoRow(
                            label: '最早启用套盒时间',
                            value: _earliestStorageDate != null
                                ? '${_earliestStorageDate!.year}-${_earliestStorageDate!.month.toString().padLeft(2, '0')}-${_earliestStorageDate!.day.toString().padLeft(2, '0')}'
                                : '-'),
                        _InfoRow(label: '剩余可消费总次数', value: '$_totalRemaining'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('新增储值'),
                            onPressed: () async {
                              await context.push('/storage/new', extra: {'customer': c.name});
                              if (mounted) _load();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy),
                            label: const Text('复制储值结构新建客户'),
                            onPressed: () async {
                              await context.push('/customer/new', extra: {'template': c.name});
                              if (mounted) context.pop();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('储值与消费', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 720) {
                          if (_storages.isEmpty) {
                            return const Card(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: Text('暂无储值记录')),
                              ),
                            );
                          }
                          return Column(
                            children: _storages.map((s) => _StorageCard(
                              storage: s,
                              smallItemNames: _smallItemNames,
                              onTap: () async {
                                await context.push('/storage/${s.id}');
                                if (mounted) _load();
                              },
                              onCopy: () async {
                                await context.push(
                                  '/storage/new',
                                  extra: {'customer': c.name, 'copy': s.id},
                                );
                                if (mounted) _load();
                              },
                              onDelete: () => _deleteStorage(s),
                            )).toList(),
                          );
                        }
                        return SizedBox(
                          height: 420,
                          child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 左侧：储值列表（仅标题，无三点菜单，点击右列顶部展示详情与操作）
                          Expanded(
                            flex: 3,
                            child: Card(
                              margin: EdgeInsets.zero,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                                    child: Text('储值记录',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 13)),
                                  ),
                                  const Divider(height: 1),
                                  Expanded(
                                    child: _storages.isEmpty
                                        ? const Center(child: Text('暂无储值记录', style: TextStyle(fontSize: 13)))
                                        : ListView.builder(
                                            padding: const EdgeInsets.symmetric(vertical: 4),
                                            itemCount: _storages.length,
                                            itemBuilder: (context, index) {
                                              final s = _storages[index];
                                              final selected = s.id == _selectedStorageId;
                                              final bigStr = s.storageBigItems.join('、');
                                              final smallStr = s.storageSmallItemIds
                                                  .map((id) => _smallItemNames[id] ?? id.toString())
                                                  .join('、');
                                              final title = bigStr.isNotEmpty && smallStr.isNotEmpty
                                                  ? '$bigStr · $smallStr'
                                                  : (bigStr.isNotEmpty
                                                      ? bigStr
                                                      : (smallStr.isNotEmpty ? smallStr : s.code));
                                              return InkWell(
                                                onTap: () {
                                                  if (selected) {
                                                    _showStorageDetailDialog(context, s);
                                                  } else {
                                                    setState(() {
                                                      _selectedStorageId = s.id;
                                                    });
                                                  }
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  color: selected
                                                      ? Theme.of(context).colorScheme.primary.withOpacity(0.06)
                                                      : null,
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        title,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '¥${s.amount.toStringAsFixed(0)} · 剩余${_remainingForStorage(s)}次',
                                                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 中间分割线尽量窄
                          Container(width: 1, color: Colors.grey[300]),
                          // 右侧：选中储值详情+操作在顶部，消费列表在下（无 icon）
                          Expanded(
                            flex: 4,
                            child: Card(
                              margin: EdgeInsets.zero,
                              child: _buildRightPane(context, c),
                            ),
                          ),
                        ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightPane(BuildContext context, CustomerModel customer) {
    final id = _selectedStorageId;
    if (id == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text('消费记录', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 13)),
          ),
          const Divider(height: 1),
          const Expanded(child: Center(child: Text('请选择左侧储值查看消费明细', style: TextStyle(fontSize: 13)))),
        ],
      );
    }
    final s = _storages.firstWhere((x) => x.id == id);
    final list = _consumptionsByStorage[id] ?? const [];
    final bigStr = s.storageBigItems.join('、');
    final smallStr = s.storageSmallItemIds
        .map((id) => _smallItemNames[id] ?? id.toString())
        .join('、');
    final title = bigStr.isNotEmpty && smallStr.isNotEmpty
        ? '$bigStr · $smallStr'
        : (bigStr.isNotEmpty ? bigStr : (smallStr.isNotEmpty ? smallStr : s.code));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 右列顶部：所选储值详情 + 操作键
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '${s.code} · ¥${s.amount.toStringAsFixed(0)} · 剩余${_remainingForStorage(s)}次',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () async {
                      await context.push('/storage/${s.id}');
                      if (mounted) _load();
                    },
                    child: const Text('查看详情', style: TextStyle(fontSize: 12)),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () async {
                      final result = await showModalBottomSheet<ConsumptionRecordModel>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (ctx) => DraggableScrollableSheet(
                          initialChildSize: 0.85,
                          minChildSize: 0.5,
                          maxChildSize: 0.95,
                          expand: false,
                          builder: (_, __) => ConsumptionEditScreen(storageId: s.id),
                        ),
                      );
                      if (mounted && result != null) {
                        setState(() {
                          final list = _consumptionsByStorage[s.id] ?? [];
                          _consumptionsByStorage[s.id] = [result, ...list];
                        });
                      }
                    },
                    child: const Text('新增消费', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Text(
            '消费记录',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('暂无消费记录', style: TextStyle(fontSize: 13)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final c = list[index];
                    return _buildConsumptionTile(context, c, s.id);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConsumptionTile(BuildContext context, ConsumptionRecordModel c, int storageId) {
    final dateStr =
        '${c.consumptionDate.year}-${c.consumptionDate.month.toString().padLeft(2, '0')}-${c.consumptionDate.day.toString().padLeft(2, '0')}';
    final projectIds = c.consumptionProjectIds.isNotEmpty
        ? c.consumptionProjectIds
        : (c.consumptionProjectId != null ? [c.consumptionProjectId!] : <int>[]);
    final names = projectIds
        .map((id) => _smallItemNames[id] ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final projectLabel = names.isNotEmpty ? names.join('、') : '消费';
    return InkWell(
      onTap: () => _showConsumptionDetailDialog(context, c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(projectLabel, style: const TextStyle(fontSize: 13)),
                  Text(
                    dateStr + (c.remark != null && c.remark!.isNotEmpty ? ' · ${c.remark}' : ''),
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: '删除',
              onPressed: () => _confirmDeleteConsumption(c, storageId),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteConsumption(ConsumptionRecordModel c, int storageId) async {
    final ok = await showConfirmDeleteDialog(
      context,
      title: '删除消费',
      content: '确定删除该消费记录吗？',
    );
    if (ok != true || !mounted) return;
    final previousList = List<ConsumptionRecordModel>.from(_consumptionsByStorage[storageId] ?? []);
    setState(() {
      final list = _consumptionsByStorage[storageId] ?? [];
      _consumptionsByStorage[storageId] = list.where((x) => x.id != c.id).toList();
    });
    context.read<DataRefreshNotifier>().invalidateStorageAndConsumption();
    try {
      await context.read<ConsumptionRepository>().delete(c.id);
    } catch (e) {
      if (mounted) {
        setState(() => _consumptionsByStorage[storageId] = previousList);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：${toUserFriendlyError(e)}')),
        );
      }
    }
  }
}

class _StorageDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _StorageDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
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
            width: 120,
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  final StorageRecordModel storage;
  final Map<int, String> smallItemNames;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const _StorageCard({
    required this.storage,
    required this.smallItemNames,
    required this.onTap,
    required this.onCopy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bigStr = storage.storageBigItems.join('、');
    final smallStr = storage.storageSmallItemIds
        .map((id) => smallItemNames[id] ?? id.toString())
        .join('、');
    final title = bigStr.isNotEmpty && smallStr.isNotEmpty
        ? '$bigStr · $smallStr'
        : (bigStr.isNotEmpty ? bigStr : (smallStr.isNotEmpty ? smallStr : storage.code));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('¥${storage.amount.toStringAsFixed(0)}'),
            if ((storage.remark ?? '').isNotEmpty)
              Text(
                storage.remark ?? '',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'copy', child: Text('复制新增储值')),
            const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
          ],
          onSelected: (v) {
            if (v == 'copy') onCopy();
            if (v == 'delete') onDelete();
          },
        ),
        onTap: onTap,
      ),
    );
  }
}
