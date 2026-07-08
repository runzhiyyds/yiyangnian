import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/error_message.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_placeholder.dart';
import 'consumption_model.dart';
import 'consumption_repository.dart';
import '../storage/storage_model.dart';
import '../storage/storage_repository.dart';
import '../storage/storage_small_item_picker.dart';
import '../storage_options/storage_small_item_repository.dart';

class ConsumptionEditScreen extends StatefulWidget {
  const ConsumptionEditScreen({
    super.key,
    this.consumptionId,
    this.storageId,
  });

  final int? consumptionId;
  final int? storageId;

  @override
  State<ConsumptionEditScreen> createState() => _ConsumptionEditScreenState();
}

class _ConsumptionEditScreenState extends State<ConsumptionEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _remarkController;

  StorageRecordModel? _storage;
  List<int> _selectedProjectIds = [];
  DateTime _consumptionDate = DateTime.now();
  bool _loading = false;
  String? _error;
  String? _projectSelectionError;

  @override
  void initState() {
    super.initState();
    _remarkController = TextEditingController();
    if (widget.consumptionId != null) {
      _loadConsumption();
    } else if (widget.storageId != null) {
      _loadStorage();
    }
  }

  ConsumptionRecordModel? _existingConsumption;

  static String _cacheKeyConsumption(int id) => 'consumption_$id';
  static String _cacheKeyStorage(int id) => 'storage_$id';

  Future<void> _loadConsumption() async {
    final id = widget.consumptionId!;
    final cache = context.read<DataCache>();
    var c = cache.get<ConsumptionRecordModel>(_cacheKeyConsumption(id));
    if (c == null) {
      final repo = context.read<ConsumptionRepository>();
      c = await repo.getById(id);
      if (c != null) cache.set(_cacheKeyConsumption(id), c);
    }
    if (c != null && mounted) {
      _existingConsumption = c;
      _consumptionDate = c.consumptionDate;
      // 多项目优先，若为空则回退到单项目 ID
      final ids = c.consumptionProjectIds.isNotEmpty
          ? c.consumptionProjectIds
          : (c.consumptionProjectId != null ? [c.consumptionProjectId!] : <int>[]);
      _selectedProjectIds = ids;
      _remarkController.text = c.remark ?? '';
      final storageId = c.storageRecordId;
      var s = cache.get<StorageRecordModel>(_cacheKeyStorage(storageId));
      if (s == null) {
        final storageRepo = context.read<StorageRepository>();
        s = await storageRepo.getById(storageId);
        if (!mounted) return;
        if (s != null) cache.set(_cacheKeyStorage(storageId), s);
      }
      if (!mounted) return;
      _storage = s;
      setState(() {});
    }
  }

  /// 从储值详情返回后刷新关联储值（及编辑态下的消费）
  Future<void> _reloadStorageAndConsumption() async {
    final cache = context.read<DataCache>();
    if (widget.consumptionId != null) {
      cache.remove(_cacheKeyConsumption(widget.consumptionId!));
      final sid = _existingConsumption?.storageRecordId;
      if (sid != null) cache.remove(_cacheKeyStorage(sid));
      await _loadConsumption();
    } else if (widget.storageId != null) {
      cache.remove(_cacheKeyStorage(widget.storageId!));
      await _loadStorage();
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadStorage() async {
    final id = widget.storageId!;
    final cache = context.read<DataCache>();
    var s = cache.get<StorageRecordModel>(_cacheKeyStorage(id));
    if (s == null) {
      final repo = context.read<StorageRepository>();
      s = await repo.getById(id);
      if (s != null) cache.set(_cacheKeyStorage(id), s);
    }
    if (s != null && mounted) {
      _storage = s;
      _consumptionDate = DateTime.now();
      // 若储值记录尚未配置小项，则允许在消费中自由选择/新建小项
      _selectedProjectIds = s.storageSmallItemIds.isNotEmpty
          ? [s.storageSmallItemIds.first]
          : [];
      setState(() {});
    }
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final ok = await showConfirmDeleteDialog(
      context,
      title: '删除消费',
      content: '确定删除该消费记录吗？',
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<ConsumptionRepository>().delete(widget.consumptionId!);
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

  Future<void> _save() async {
    if (_storage == null) return;

    final isEdit = widget.consumptionId != null;
    if (_selectedProjectIds.isEmpty) {
      setState(() => _projectSelectionError = '请至少选择一个消费项目');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请至少选择一个消费项目'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _projectSelectionError = null);

    // 若本次选择的小项与储值当前配置不一致（包括储值尚未配置小项），则询问如何处理
    bool syncStorageSmallItems = false;
    final storageSet = _storage!.storageSmallItemIds.toSet();
    final newSet = _selectedProjectIds.toSet();
    final needPrompt =
        storageSet.length != newSet.length || !storageSet.containsAll(newSet);
    if (needPrompt) {
      // 第一步：让用户选择策略
      final mode = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('是否同步更新储值小项？'),
          content: const Text(
              '本次消费选择的小项与该笔储值当前配置的小项不同，如何处理？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'consumption_only'),
              child: const Text('仅把小项写入本次消费'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'sync_storage'),
              child: const Text('同步更新该笔储值的小项'),
            ),
          ],
        ),
      );
      if (mode == null) return;
      syncStorageSmallItems = mode == 'sync_storage';

      // 第二步：对所选策略做一次确认
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('请确认操作'),
          content: Text(syncStorageSmallItems
              ? '将更新该笔储值记录的小项为本次选择的小项，确认吗？'
              : '仅将小项写入本次消费记录，不修改储值记录的小项，确认吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<ConsumptionRepository>();
      final projIds = _selectedProjectIds;
      ConsumptionRecordModel? created;

      if (isEdit) {
        final record = ConsumptionRecordModel(
          id: widget.consumptionId!,
          code: _existingConsumption?.code ?? '',
          consumptionDate: _consumptionDate,
          storageRecordId: _storage!.id,
          consumptionProjectId: projIds.isNotEmpty ? projIds.first : null,
          consumptionProjectIds: projIds,
          remark: _remarkController.text.trim().isEmpty
              ? null
              : _remarkController.text.trim(),
        );
        await repo.update(record);
      } else {
        created = await repo.create(ConsumptionRecordModel(
          id: 0,
          code: '',
          consumptionDate: _consumptionDate,
          storageRecordId: _storage!.id,
          consumptionProjectId: projIds.isNotEmpty ? projIds.first : null,
          consumptionProjectIds: projIds,
          remark: _remarkController.text.trim().isEmpty
              ? null
              : _remarkController.text.trim(),
        ));
      }

      // 根据选择，是否同步更新储值记录中的小项
      if (syncStorageSmallItems) {
        final storageRepo = context.read<StorageRepository>();
        final s = _storage!;
        final updated = StorageRecordModel(
          id: s.id,
          code: s.code,
          customerName: s.customerName,
          storageBigItems: s.storageBigItems,
          storageSmallItemIds: projIds.isEmpty ? s.storageSmallItemIds : projIds,
          amount: s.amount,
          totalCount: s.totalCount,
          storageDate: s.storageDate,
          remark: s.remark,
          createdAt: s.createdAt,
        );
        await storageRepo.update(updated);
        _storage = updated;
      }

      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateStorageAndConsumption();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEdit ? '保存成功' : '已新增 1 条消费记录')),
        );
        if (isEdit) {
          context.pop();
        } else {
          context.pop(created!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = toUserFriendlyError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_storage == null && !_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('消费记录')),
        body: const Center(child: FullPageLoadingPlaceholder()),
      );
    }

    final smallItemRepo = context.read<StorageSmallItemRepository>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.consumptionId != null ? '编辑消费' : '新增消费'),
        actions: [
          if (widget.consumptionId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _loading ? null : () => _confirmDelete(),
            ),
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: FutureBuilder(
        future: smallItemRepo.getAll(),
        builder: (context, snapshot) {
          final allOptions = snapshot.data ?? [];
          final validIds = _storage!.storageSmallItemIds;
          // 若储值尚未配置小项，则消费页可从全部小项中选择 / 创建（含新建）
          final projectOptions = validIds.isEmpty
              ? allOptions
              : allOptions.where((o) => validIds.contains(o.id)).toList();
          // 储值无小项时即使 projectOptions 为空也显示选择器，以便用户新建小项
          final showPicker = validIds.isEmpty || projectOptions.isNotEmpty;

          final s = _storage!;
          final storageDateStr =
              '${s.storageDate.year}-${s.storageDate.month.toString().padLeft(2, '0')}-${s.storageDate.day.toString().padLeft(2, '0')}';

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                ],
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  child: InkWell(
                    onTap: () async {
                      await context.push('/storage/${s.id}');
                      if (!context.mounted) return;
                      await _reloadStorageAndConsumption();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Theme.of(context).colorScheme.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '父级储值记录',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  s.customerName,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$storageDateStr · ¥${s.amount.toStringAsFixed(0)} · 编号 ${s.code}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey[700],
                                      ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: () async {
                              await context.push('/storage/${s.id}');
                              if (!context.mounted) return;
                              await _reloadStorageAndConsumption();
                            },
                            child: const Text('查看储值'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('消费日期'),
                  subtitle: Text(
                    '${_consumptionDate.year}-${_consumptionDate.month.toString().padLeft(2, '0')}-${_consumptionDate.day.toString().padLeft(2, '0')}',
                  ),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _consumptionDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      locale: const Locale('zh', 'CN'),
                    );
                    if (d != null) setState(() => _consumptionDate = d);
                  },
                ),
                if (showPicker) ...[
                  const SizedBox(height: 16),
                  Text(
                    '消费项目（可多选）*',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: _projectSelectionError != null ? Colors.red : null,
                    ),
                  ),
                  if (_projectSelectionError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _projectSelectionError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                  ],
                  StorageSmallItemPicker(
                    options: projectOptions,
                    selectedIds: _selectedProjectIds,
                    onAdd: (id) {
                      setState(() {
                        _projectSelectionError = null;
                        if (!_selectedProjectIds.contains(id)) {
                          _selectedProjectIds.add(id);
                        }
                      });
                    },
                    onRemove: (id) {
                      setState(() {
                        _selectedProjectIds.remove(id);
                      });
                    },
                    // 当储值未配置小项时，允许在消费页面创建小项；否则仅从储值已有小项中选择
                    onCreateNew: (name) async {
                      final repo = context.read<StorageSmallItemRepository>();
                      final opt = await repo.getOrCreate(name);
                      return opt.id;
                    },
                    allowCreate: validIds.isEmpty,
                    addButtonLabelWhenEmpty: '选择消费项目',
                    addButtonLabelWhenNotEmpty: '修改 / 添加消费项目',
                    subtleButton: true,
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _remarkController,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    hintText: '可选',
                  ),
                  maxLines: 2,
                ),
                if (widget.consumptionId != null &&
                    _existingConsumption?.code != null &&
                    _existingConsumption!.code.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('消费编号'),
                    subtitle: Text(
                      _existingConsumption!.code,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
