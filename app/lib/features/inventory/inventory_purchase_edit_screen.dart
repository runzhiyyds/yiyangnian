import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/demo_mode.dart';
import '../../core/error_message.dart';
import '../../core/retry_helper.dart';
import '../auth/auth_service.dart';
import '../storage_options/storage_big_item_repository.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'inventory_models.dart';
import 'inventory_purchase_repository.dart';
import 'widgets/quantity_stepper.dart';

class InventoryPurchaseEditScreen extends StatefulWidget {
  const InventoryPurchaseEditScreen({
    super.key,
    this.purchaseId,
    this.initialReadOnly = false,
  });

  final int? purchaseId;
  /// 已有记录默认可从只读浏览态进入，避免误触修改。
  final bool initialReadOnly;

  @override
  State<InventoryPurchaseEditScreen> createState() =>
      _InventoryPurchaseEditScreenState();
}

class _InventoryPurchaseEditScreenState extends State<InventoryPurchaseEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _totalAmountController;
  late TextEditingController _remarkController;
  late TextEditingController _smallItemDisplayController;

  String _bigItemName = '';
  int _smallItemId = 0;
  int _quantity = 0;
  DateTime _purchaseDate = DateTime.now();
  String _existingCode = '';
  List<StorageBigItemOption> _bigItemOptions = [];
  List<StorageSmallItemOption> _smallItemOptions = [];
  bool _loading = false;
  late bool _isEditing;
  String? _error;

  String _cacheKeyBig(BuildContext context) =>
      DemoMode.inventoryBigOptionsCacheKey(
          context.read<AuthService>().user?.email);

  String _cacheKeySmall(BuildContext context) =>
      DemoMode.inventorySmallOptionsCacheKey(
          context.read<AuthService>().user?.email);

  @override
  void initState() {
    super.initState();
    _totalAmountController = TextEditingController(text: '0');
    _remarkController = TextEditingController();
    _smallItemDisplayController = TextEditingController(text: '请选择储值小项');
    _isEditing = !widget.initialReadOnly || widget.purchaseId == null;
    _loadOptions();
    if (widget.purchaseId != null) {
      _loadPurchase();
    }
  }

  @override
  void dispose() {
    _totalAmountController.dispose();
    _remarkController.dispose();
    _smallItemDisplayController.dispose();
    super.dispose();
  }

  void _updateSmallItemDisplay() {
    final list = _smallItemsUnderBigItem;
    final found = list.where((o) => o.id == _smallItemId);
    _smallItemDisplayController.text = found.isNotEmpty
        ? found.first.name
        : (list.isNotEmpty ? list.first.name : '请选择储值小项');
  }

  int? _getBigItemId() {
    if (_bigItemName.isEmpty) return null;
    try {
      return _bigItemOptions.firstWhere((b) => b.name == _bigItemName).id;
    } catch (_) {
      return null;
    }
  }

  List<StorageSmallItemOption> get _smallItemsUnderBigItem {
    final bigId = _getBigItemId();
    return _smallItemOptions.where((s) => s.storageBigItemId == bigId).toList();
  }

  Future<void> _loadOptions() async {
    final cache = context.read<DataCache>();
    final keyBig = _cacheKeyBig(context);
    final keySmall = _cacheKeySmall(context);
    var big = cache.get<List<StorageBigItemOption>>(keyBig);
    var small = cache.get<List<StorageSmallItemOption>>(keySmall);
    if (big == null || small == null) {
      final bigRepo = context.read<StorageBigItemRepository>();
      final smallRepo = context.read<StorageSmallItemRepository>();
      final allBig = await retryOnFailure(() => bigRepo.getAll());
      final allSmall = await retryOnFailure(() => smallRepo.getAll());
      final email = context.read<AuthService>().user?.email;
      big = allBig;
      small = DemoMode.filterSmallItemOptions(email, allSmall);
      if (mounted) {
        cache.set(keyBig, big, ttl: const Duration(hours: 1));
        cache.set(keySmall, small, ttl: const Duration(hours: 1));
      }
    }
    if (mounted) {
      final bigList = big ?? [];
      final smallList = small ?? [];
      setState(() {
        _bigItemOptions = bigList;
        _smallItemOptions = smallList;
        if (_bigItemName.isEmpty && bigList.isNotEmpty) {
          _bigItemName = bigList.first.name;
        }
        int? bigId;
        for (final b in bigList) {
          if (b.name == _bigItemName) {
            bigId = b.id;
            break;
          }
        }
        if (bigId == null && bigList.isNotEmpty) bigId = bigList.first.id;
        final underBig = smallList.where((s) => s.storageBigItemId == bigId).toList();
        if (_smallItemId == 0 && underBig.isNotEmpty) {
          _smallItemId = underBig.first.id;
        } else if (_smallItemId != 0 && !underBig.any((s) => s.id == _smallItemId)) {
          _smallItemId = underBig.isNotEmpty ? underBig.first.id : 0;
        }
      });
      _updateSmallItemDisplay();
    }
  }

  Future<void> _addBigItem() async {
    final controller = TextEditingController(text: _bigItemName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增储值大项'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '大项名称',
            hintText: '如：藏红方、御至宝',
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
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final repo = context.read<StorageBigItemRepository>();
      final opt = await retryOnFailure(() => repo.getOrCreate(name));
      if (!mounted) return;
      final cache = context.read<DataCache>();
      setState(() {
        if (_bigItemOptions.every((o) => o.id != opt.id)) {
          _bigItemOptions = [..._bigItemOptions, opt]..sort((a, b) => a.name.compareTo(b.name));
        }
        _bigItemName = opt.name;
      });
      cache.set(_cacheKeyBig(context), _bigItemOptions, ttl: const Duration(hours: 1));
      // 让储值编辑等其它页面的下拉选项也能刷新
      context.read<DataRefreshNotifier>().invalidateStorageOptions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增大项失败：${toUserFriendlyError(e)}')),
      );
    }
  }

  /// 从选择器内调用，当前大项下无小项时直接弹窗新增；返回新小项 id 或 null
  Future<int?> _addSmallItemFromPicker() async {
    final bigName = _bigItemName.isNotEmpty ? _bigItemName : '当前大项';
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('新增小项（$bigName）'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '小项名称',
            hintText: '如：面膜、精华液',
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
    if (name == null || name.trim().isEmpty || !mounted) return null;
    try {
      final repo = context.read<StorageSmallItemRepository>();
      final bigId = _getBigItemId();
      final opt = await retryOnFailure(() => repo.getOrCreate(name, storageBigItemId: bigId));
      if (!mounted) return null;
      final cache = context.read<DataCache>();
      setState(() {
        if (_smallItemOptions.every((o) => o.id != opt.id)) {
          _smallItemOptions = [..._smallItemOptions, opt]..sort((a, b) => a.name.compareTo(b.name));
        }
        _smallItemId = opt.id;
        _updateSmallItemDisplay();
      });
      cache.set(_cacheKeySmall(context), _smallItemOptions, ttl: const Duration(hours: 1));
      context.read<DataRefreshNotifier>().invalidateStorageOptions();
      return opt.id;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增小项失败：${toUserFriendlyError(e)}')),
      );
      return null;
    }
  }

  Future<void> _addSmallItem() async {
    final result = await _addSmallItemFromPicker();
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已新增小项')),
      );
    }
  }

  Future<void> _pickSmallItem() async {
    if (_bigItemOptions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先新增大项')),
      );
      return;
    }
    final currentId = _smallItemId;
    final optionsUnderBig = _smallItemsUnderBigItem;
    if (optionsUnderBig.isEmpty) {
      if (!mounted) return;
      final added = await _addSmallItemFromPicker();
      if (added != null && mounted) {
        setState(() {
          _smallItemId = added;
          _updateSmallItemDisplay();
        });
      }
      return;
    }
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final searchController = TextEditingController();
        List<StorageSmallItemOption> filtered = List.of(optionsUnderBig);
        return StatefulBuilder(
          builder: (ctx, setModalState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.5,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          labelText: '搜索储值小项',
                          hintText: '输入名称关键字',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) {
                          final q = value.trim();
                          setModalState(() {
                            if (q.isEmpty) {
                              filtered = List.of(optionsUnderBig);
                            } else {
                              filtered = optionsUnderBig
                                  .where((o) =>
                                      o.name.contains(q) ||
                                      o.name.toLowerCase().contains(q.toLowerCase()))
                                  .toList();
                            }
                          });
                        },
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.add_circle_outline),
                      title: const Text('新增小项'),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final added = await _addSmallItemFromPicker();
                        if (added != null && mounted) {
                          setState(() {
                            _smallItemId = added;
                            _updateSmallItemDisplay();
                          });
                        }
                      },
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, index) {
                          final opt = filtered[index];
                          final selected = opt.id == currentId;
                          return ListTile(
                            leading: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: selected
                                  ? Theme.of(ctx).colorScheme.primary
                                  : null,
                            ),
                            title: Text(opt.name),
                            onTap: () => Navigator.pop(ctx, opt.id),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (result != null && mounted) {
      setState(() {
        _smallItemId = result;
        _updateSmallItemDisplay();
      });
    }
  }

  Future<void> _loadPurchase() async {
    final repo = context.read<InventoryPurchaseRepository>();
    final p = await retryOnFailure(() => repo.getById(widget.purchaseId!));
    if (p != null && mounted) {
      setState(() {
        _existingCode = p.code;
        _purchaseDate = p.purchaseDate;
        _totalAmountController.text = p.totalAmount.toStringAsFixed(0);
        _remarkController.text = p.remark ?? '';
        if (p.storageSmallItemIds.isNotEmpty &&
            p.storageBigItems.isNotEmpty &&
            p.quantities.isNotEmpty) {
          _bigItemName = p.storageBigItems.first;
          _smallItemId = p.storageSmallItemIds.first;
          _quantity = p.quantities.first;
        }
      });
      _updateSmallItemDisplay();
    }
  }

  Future<void> _save() async {
    if (_smallItemId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择储值小项')),
      );
      return;
    }
    if (_quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效数量（>0）')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<InventoryPurchaseRepository>();
      final totalAmount = double.tryParse(_totalAmountController.text) ?? 0;

      final record = InventoryPurchaseRecordModel(
        id: widget.purchaseId ?? 0,
        code: widget.purchaseId != null ? _existingCode : '',
        purchaseDate: _purchaseDate,
        storageBigItems: [_bigItemName],
        storageSmallItemIds: [_smallItemId],
        quantities: [_quantity],
        totalAmount: totalAmount,
        remark: _remarkController.text.trim().isEmpty
            ? null
            : _remarkController.text.trim(),
      );

      if (widget.purchaseId != null) {
        await repo.update(record);
      } else {
        await repo.create(record);
      }

      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateInventory();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功')),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExisting = widget.purchaseId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(!isExisting ? '添加进货' : (_isEditing ? '编辑进货' : '进货详情')),
        actions: [
          if (isExisting && !_isEditing)
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isExisting && !_isEditing) ...[
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const ListTile(
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('当前为浏览态'),
                  subtitle: Text('内容不可修改；如需调整，请点击右上角“编辑”'),
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
                    Text('进货信息',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('进货日期'),
                      subtitle: Text(
                        '${_purchaseDate.year}-${_purchaseDate.month.toString().padLeft(2, '0')}-${_purchaseDate.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: !_isEditing ? null : () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _purchaseDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          locale: const Locale('zh', 'CN'),
                        );
                        if (d != null) setState(() => _purchaseDate = d);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _totalAmountController,
                      enabled: _isEditing,
                      decoration: const InputDecoration(
                        labelText: '总金额（元）',
                        hintText: '可选',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
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
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('进货明细',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('一次进货仅补充一个小项的库存',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            )),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _bigItemOptions.any((o) => o.name == _bigItemName)
                          ? _bigItemName
                          : (_bigItemOptions.isNotEmpty
                              ? _bigItemOptions.first.name
                              : null),
                      decoration: const InputDecoration(
                        labelText: '大项',
                        isDense: true,
                      ),
                      isExpanded: true,
                      items: _bigItemOptions
                          .map((o) => DropdownMenuItem(
                                value: o.name,
                                child: Text(o.name,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
      onChanged: !_isEditing ? null : (v) {
        if (v != null) {
          setState(() {
            _bigItemName = v;
            final underBig = _smallItemsUnderBigItem;
            if (!underBig.any((s) => s.id == _smallItemId)) {
              _smallItemId = underBig.isNotEmpty ? underBig.first.id : 0;
            }
            _updateSmallItemDisplay();
          });
        }
      },
                    ),
                    if (_isEditing)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _loading ? null : _addBigItem,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('新增大项'),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: '小项',
                        hintText: '请选择储值小项',
                        isDense: true,
                      ),
                      controller: _smallItemDisplayController,
                      enabled: _isEditing,
                      onTap: _loading || !_isEditing ? null : _pickSmallItem,
                    ),
                    if (_isEditing)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _loading ? null : _addSmallItem,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('新增小项'),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('数量',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(width: 12),
                        QuantityStepper(
                          value: _quantity,
                          enabled: _isEditing,
                          onChanged: (v) => setState(() => _quantity = v),
                        ),
                      ],
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
}
