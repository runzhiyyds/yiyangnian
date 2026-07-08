import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/demo_mode.dart';
import '../../core/error_message.dart';
import '../../core/retry_helper.dart';
import '../auth/auth_service.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'inventory_models.dart';
import 'inventory_supp_in_repository.dart';
import 'widgets/quantity_stepper.dart';

class InventorySuppInEditScreen extends StatefulWidget {
  const InventorySuppInEditScreen({
    super.key,
    this.recordId,
    this.initialSmallItemId,
    this.initialSmallItemName,
  });

  final int? recordId;
  final int? initialSmallItemId;
  /// 从大项小项管理页进入时传入，用于只读展示
  final String? initialSmallItemName;

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

  String _cacheKey(BuildContext context) =>
      DemoMode.inventorySmallOptionsCacheKey(
          context.read<AuthService>().user?.email);

  @override
  void initState() {
    super.initState();
    _remarkController = TextEditingController();
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
          _selectedSmallItemId = widget.initialSmallItemId ?? _smallItemOptions.first.id;
        }
      });
    }
  }

  Future<void> _loadRecord() async {
    final repo = context.read<InventorySuppInRepository>();
    final r = await retryOnFailure(() => repo.getById(widget.recordId!));
    if (r != null && mounted) {
      setState(() {
        _selectedSmallItemId = r.storageSmallItemId;
        _supplementDate = r.supplementDate;
        _quantity = r.quantity;
        _remarkController.text = r.remark ?? '';
      });
    }
  }

  Future<void> _save() async {
    if (_selectedSmallItemId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择储值小项')),
      );
      return;
    }
    if (_quantity < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('数量不能为负')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功')),
        );
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

  bool get _isFromContext => widget.initialSmallItemId != null && widget.initialSmallItemName != null;

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.recordId != null;
    final title = isEdit
        ? '编辑补充入库'
        : (_isFromContext ? '为「${widget.initialSmallItemName}」补充入库' : '新增补充入库');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('小项', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
                              Text(widget.initialSmallItemName!, style: Theme.of(context).textTheme.titleMedium),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    DropdownButtonFormField<int>(
                      value: _smallItemOptions.any((o) => o.id == _selectedSmallItemId)
                          ? _selectedSmallItemId
                          : (_smallItemOptions.isNotEmpty
                              ? _smallItemOptions.first.id
                              : null),
                      decoration: const InputDecoration(labelText: '储值小项'),
                      items: _smallItemOptions
                          .map((o) => DropdownMenuItem(
                                value: o.id,
                                child: Text(o.name),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedSmallItemId = v);
                      },
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('数量', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: 16),
                      QuantityStepper(
                        value: _quantity,
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
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _supplementDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        locale: const Locale('zh', 'CN'),
                      );
                      if (d != null) setState(() => _supplementDate = d);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _remarkController,
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
        ],
      ),
    );
  }
}
