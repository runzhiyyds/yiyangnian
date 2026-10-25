import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/demo_mode.dart';
import '../../core/error_message.dart';
import '../../core/retry_helper.dart';
import '../../core/write_request_id.dart';
import '../auth/auth_service.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'inventory_models.dart';
import 'inventory_supp_in_repository.dart';
import 'widgets/quantity_stepper.dart';
import 'widgets/inventory_void_dialog.dart';

class InventorySuppInEditScreen extends StatefulWidget {
  const InventorySuppInEditScreen({
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
  State<InventorySuppInEditScreen> createState() =>
      _InventorySuppInEditScreenState();
}

class _InventorySuppInEditScreenState extends State<InventorySuppInEditScreen> {
  late TextEditingController _remarkController;

  List<StorageSmallItemOption> _smallItemOptions = [];
  int _selectedSmallItemId = 0;
  DateTime _supplementDate = DateTime.now();
  int _quantity = 0;
  bool _loading = false;
  String? _error;
  late bool _isEditing;
  InventorySuppInRecordModel? _loadedRecord;
  final String _createRequestId = newWriteRequestId();

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
    var opts = cache.get<List<StorageSmallItemOption>>(key);
    if (opts == null) {
      final repo = context.read<StorageSmallItemRepository>();
      final all = await retryOnFailure(() => repo.getAll());
      final email = context.read<AuthService>().user?.email;
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
    final repo = context.read<InventorySuppInRepository>();
    final r = await retryOnFailure(() => repo.getById(widget.recordId!));
    if (r != null && mounted) {
      setState(() {
        _loadedRecord = r;
        _selectedSmallItemId = r.storageSmallItemId;
        _supplementDate = r.supplementDate;
        _quantity = r.quantity;
        _remarkController.text = r.remark ?? '';
      });
    }
  }

  Future<void> _save() async {
    if (_loading) return;
    if (_selectedSmallItemId <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择储值小项')));
      return;
    }
    if (_quantity <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('入库数量需大于0')));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<InventorySuppInRepository>();
      final record = InventorySuppInRecordModel(
        id: widget.recordId ?? 0,
        supplementDate: _supplementDate,
        storageSmallItemId: _selectedSmallItemId,
        quantity: _quantity,
        occurredAt: combineInventoryDateAndTime(
          _supplementDate,
          _loadedRecord?.occurredAt,
        ),
        occurredAtEstimated: _loadedRecord?.occurredAtEstimated ?? false,
        remark: _remarkController.text.trim().isEmpty
            ? null
            : _remarkController.text.trim(),
        clientRequestId: _loadedRecord?.clientRequestId ?? _createRequestId,
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
      title: '撤销补充入库',
      impact: '撤销后库存将减少 ${record.quantity} 件。',
    );
    if (reason == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final voided = await context.read<InventorySuppInRepository>().voidRecord(
        record.id,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        _loadedRecord = voided;
        _isEditing = false;
        _loading = false;
      });
      context.read<DataRefreshNotifier>().invalidateInventory();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已撤销补充入库，操作记录已保留')));
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
    final title = isEdit
        ? (_isEditing ? '编辑补充入库' : '补充入库详情')
        : (_isFromContext ? '为「${widget.initialSmallItemName}」补充入库' : '新增补充入库');

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
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
                      value:
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
                              if (v != null)
                                setState(() => _selectedSmallItemId = v);
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
                    title: const Text('入库日期'),
                    subtitle: Text(
                      '${_supplementDate.year}-${_supplementDate.month.toString().padLeft(2, '0')}-${_supplementDate.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: !_isEditing
                        ? null
                        : () async {
                            final d = await pickInventoryBusinessDate(
                              context,
                              current: _supplementDate,
                              warnAboutReordering: isEdit,
                            );
                            if (d != null) setState(() => _supplementDate = d);
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
              label: const Text('撤销入库并保留记录'),
            ),
          ],
        ],
      ),
    );
  }
}
