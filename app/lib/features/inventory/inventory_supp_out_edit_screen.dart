import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/demo_mode.dart';
import '../../core/error_message.dart';
import '../../core/retry_helper.dart';
import '../auth/auth_service.dart';
import '../storage/storage_model.dart';
import '../storage/storage_repository.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'inventory_consumption_repository.dart';
import 'inventory_models.dart';
import 'widgets/quantity_stepper.dart';
import 'widgets/inventory_void_dialog.dart';

class InventorySuppOutEditScreen extends StatefulWidget {
  const InventorySuppOutEditScreen({
    super.key,
    this.recordId,
    this.initialSmallItemId,
    this.initialSmallItemName,
    this.initialReadOnly = false,
  });

  final int? recordId;
  final int? initialSmallItemId;

  /// 从大项小项管理页进入时传入，用于只读展示
  final String? initialSmallItemName;
  final bool initialReadOnly;

  @override
  State<InventorySuppOutEditScreen> createState() =>
      _InventorySuppOutEditScreenState();
}

class _InventorySuppOutEditScreenState
    extends State<InventorySuppOutEditScreen> {
  late TextEditingController _remarkController;

  List<StorageSmallItemOption> _smallItemOptions = [];
  int _selectedSmallItemId = 0;
  DateTime _consumptionDate = DateTime.now();
  int _quantity = 0;
  bool _loading = false;
  String? _error;
  late bool _isEditing;
  InventoryConsumptionRecordModel? _loadedRecord;
  StorageRecordModel? _sourceStorage;
  bool _sourceStorageLoading = false;

  String _cacheKey(BuildContext context) =>
      DemoMode.inventorySmallOptionsCacheKey(
        context.read<AuthService>().user?.email,
      );

  @override
  void initState() {
    super.initState();
    _remarkController = TextEditingController();
    _isEditing = !widget.initialReadOnly || widget.recordId == null;
    _loadOptions();
    if (widget.recordId != null) {
      _loadRecord();
    } else if (widget.initialSmallItemId != null) {
      _selectedSmallItemId = widget.initialSmallItemId!;
    }
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final cache = context.read<DataCache>();
    final key = _cacheKey(context);
    final email = context.read<AuthService>().user?.email;
    var opts = cache.get<List<StorageSmallItemOption>>(key);
    if (opts == null) {
      final repo = context.read<StorageSmallItemRepository>();
      final all = await retryOnFailure(() => repo.getAll());
      opts = DemoMode.filterSmallItemOptions(email, all);
      if (mounted) cache.set(key, opts);
    }
    if (mounted) {
      setState(() {
        _smallItemOptions = opts ?? [];
        if (_selectedSmallItemId == 0 && _smallItemOptions.isNotEmpty) {
          _selectedSmallItemId =
              widget.initialSmallItemId ?? _smallItemOptions.first.id;
        }
      });
    }
  }

  Future<void> _loadRecord() async {
    final repo = context.read<InventoryConsumptionRepository>();
    final r = await retryOnFailure(() => repo.getById(widget.recordId!));
    if (r != null && mounted) {
      setState(() {
        _loadedRecord = r;
        _selectedSmallItemId = r.storageSmallItemId;
        _consumptionDate = r.consumptionDate;
        _quantity = r.quantity;
        _remarkController.text = r.remark ?? '';
      });
      await _loadSourceStorage(r);
    }
  }

  bool _isAutomaticOutbound(InventoryConsumptionRecordModel record) =>
      record.sourceStorageRecordId != null ||
      (record.remark ?? '').trim().startsWith('自动出库');

  Future<void> _loadSourceStorage(
    InventoryConsumptionRecordModel record,
  ) async {
    final sourceId = record.sourceStorageRecordId;
    if (sourceId == null) return;
    setState(() => _sourceStorageLoading = true);
    try {
      final source = await retryOnFailure(
        () => context.read<StorageRepository>().getById(sourceId),
      );
      if (!mounted || _loadedRecord?.id != record.id) return;
      setState(() => _sourceStorage = source);
    } catch (_) {
      // 出库详情仍可正常查看；来源区域会提示暂时无法读取。
    } finally {
      if (mounted && _loadedRecord?.id == record.id) {
        setState(() => _sourceStorageLoading = false);
      }
    }
  }

  Future<void> _openSourceStorage() async {
    final storage = _sourceStorage;
    if (storage == null) return;
    await context.push('/storage/${storage.id}');
  }

  Future<void> _save() async {
    if (_selectedSmallItemId <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择储值小项')));
      return;
    }
    if (_quantity <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('出库数量需大于0')));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<InventoryConsumptionRepository>();
      final record = InventoryConsumptionRecordModel(
        id: widget.recordId ?? 0,
        consumptionDate: _consumptionDate,
        storageSmallItemId: _selectedSmallItemId,
        quantity: _quantity,
        sourceStorageRecordId: _loadedRecord?.sourceStorageRecordId,
        occurredAt: combineInventoryDateAndTime(
          _consumptionDate,
          _loadedRecord?.occurredAt,
        ),
        occurredAtEstimated: _loadedRecord?.occurredAtEstimated ?? false,
        remark: _remarkController.text.trim().isEmpty
            ? null
            : _remarkController.text.trim(),
      );

      if (widget.recordId != null) {
        await repo.update(record);
      } else {
        await repo.create(record);
      }

      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateInventory();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存成功')));
        context.pop();
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

  bool get _isFromContext =>
      widget.initialSmallItemId != null && widget.initialSmallItemName != null;

  Future<void> _voidRecord() async {
    final record = _loadedRecord;
    if (record == null || record.isVoided) return;
    final reason = await showInventoryVoidDialog(
      context,
      title: '撤销出库',
      impact: '撤销后库存将回加 ${record.quantity} 件。关联的客户储值记录不会自动撤销。',
    );
    if (reason == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final voided = await context
          .read<InventoryConsumptionRepository>()
          .voidRecord(record.id, reason: reason);
      if (!mounted) return;
      setState(() {
        _loadedRecord = voided;
        _isEditing = false;
        _loading = false;
      });
      context.read<DataRefreshNotifier>().invalidateInventory();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已撤销出库，操作记录已保留')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = toUserFriendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.recordId != null;
    final isVoided = _loadedRecord?.isVoided ?? false;
    final isAutomaticOutbound =
        _loadedRecord != null && _isAutomaticOutbound(_loadedRecord!);
    final title = isEdit
        ? (_isEditing ? '编辑出库' : '出库详情')
        : (_isFromContext ? '为「${widget.initialSmallItemName}」出库' : '新增出库');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (isEdit && !_isEditing)
            TextButton.icon(
              onPressed: isVoided
                  ? null
                  : () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('编辑'),
            )
          else
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isEdit && !_isEditing) ...[
            Card(
              color: isVoided
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: Icon(
                  isVoided
                      ? Icons.history_toggle_off
                      : Icons.visibility_outlined,
                ),
                title: Text(isVoided ? '该记录已撤销' : '当前为浏览态'),
                subtitle: Text(
                  isVoided
                      ? '撤销时间：${formatInventoryAuditTime(_loadedRecord!.voidedAt!)}\n'
                            '撤销原因：${_loadedRecord!.voidReason ?? '未填写'}'
                      : '如需调整，请点击右上角“编辑”',
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
          ],
          if (isEdit && isAutomaticOutbound) ...[
            _buildSourceStorageCard(context),
            const SizedBox(height: 16),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isFromContext)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '小项',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                              Text(
                                widget.initialSmallItemName!,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue:
                          _smallItemOptions.any(
                            (o) => o.id == _selectedSmallItemId,
                          )
                          ? _selectedSmallItemId
                          : (_smallItemOptions.isNotEmpty
                                ? _smallItemOptions.first.id
                                : null),
                      decoration: const InputDecoration(labelText: '储值小项'),
                      items: _smallItemOptions
                          .map(
                            (o) => DropdownMenuItem(
                              value: o.id,
                              child: Text(o.name),
                            ),
                          )
                          .toList(),
                      onChanged: !_isEditing
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() => _selectedSmallItemId = v);
                              }
                            },
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '数量',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 16),
                      QuantityStepper(
                        value: _quantity,
                        enabled: _isEditing,
                        onChanged: (v) => setState(() => _quantity = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('出库日期'),
                    subtitle: Text(
                      '${_consumptionDate.year}-${_consumptionDate.month.toString().padLeft(2, '0')}-${_consumptionDate.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: !_isEditing
                        ? null
                        : () async {
                            final d = await pickInventoryBusinessDate(
                              context,
                              current: _consumptionDate,
                              warnAboutReordering: isEdit,
                            );
                            if (d != null) setState(() => _consumptionDate = d);
                          },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _remarkController,
                    enabled: _isEditing,
                    decoration: const InputDecoration(
                      labelText: '备注',
                      hintText: '可选',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          if (isEdit && !_isEditing && !isVoided) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _loading ? null : _voidRecord,
              icon: const Icon(Icons.undo),
              label: const Text('撤销出库并保留记录'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceStorageCard(BuildContext context) {
    final source = _sourceStorage;
    final sourceId = _loadedRecord?.sourceStorageRecordId;
    String subtitle;
    if (_sourceStorageLoading) {
      subtitle = '正在读取关联储值…';
    } else if (source != null) {
      final date = source.storageDate;
      final dateText =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      subtitle =
          '${source.customerName} · ${source.code}\n储值日期：$dateText · 金额：¥${source.amount.toStringAsFixed(0)}';
    } else if (sourceId == null) {
      subtitle = '原关联储值记录已被删除，当前只能保留自动出库痕迹。';
    } else {
      subtitle = '暂时无法读取关联储值，请稍后重试。';
    }

    return Card(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('由客户储值自动出库'),
              subtitle: Text(subtitle),
              trailing: source == null
                  ? null
                  : TextButton(
                      onPressed: _openSourceStorage,
                      child: const Text('查看储值'),
                    ),
            ),
            Text(
              '这条库存记录与客户储值关联；修改出库不会同步修改原储值。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
